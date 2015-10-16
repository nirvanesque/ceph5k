#!/usr/bin/env ruby
# Copyright (c) 2015-16 Anirvan BASU, INRIA Rennes - Bretagne Atlantique
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License. 

require 'cute'
require 'logger'
require 'cute/taktuk'
require 'net/sftp'
require 'erb'
require 'socket'
require 'trollop'
require 'json'

g5k = Cute::G5K::API.new()


# banner for script
opts = Trollop::options do
  version "ceph-deploy 0.0.1 (c) 2015-16 Anirvan BASU, INRIA RBA"
  banner <<-EOS
ceph-client.rb is a script for deploying a Ceph client to interact with an already deployed Ceph cluster and/or the Ceph production cluster.

Usage:
       ceph-client.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => "sophia"
  opt :g5kCluster, "Grid 5000 cluster in specified site", :type => String, :default => ""
  opt :release, "Ceph Release name", :type => String, :default => "firefly"
  opt :env, "G5K environment to be deployed", :type => String, :default => "jessie-x64-nfs"
  opt :dfsName, "Name of Grid'5000 job for Ceph DFS cluster", :type => String, :default => "cephDeploy"
  opt :clientName, "Name of Grid'5000 job for Ceph client", :type => String, :default => "cephClient"
  opt :numClients, "No. of Ceph clients to create", :default => 1
  opt :walltime, "Wall time for Ceph client to be deployed", :type => String, :default => "01:00:00"
end

# Move CLI arguments into variables. Later change to class attributes.
argSite = opts[:site] # site name. 
argG5KCluster = opts[:g5kCluster] # G5K cluster name if specified. 
argRelease = opts[:release] # Ceph release name. 
argEnvClient = opts[:env] # Grid'5000 environment to deploy Ceph client. 
argDFSName = opts[:dfsName] # Grid'5000 Ceph cluster job name. 
argClientName = opts[:clientName] # Grid'5000 Ceph client job name. 
argNumClients = opts[:numClients] # number of nodes in Ceph cluster.
argWallTime = opts[:walltime] # walltime for the reservation.


# Show parameters for creating Ceph cluster
puts "Creating Ceph client with the following parameters:"
puts "Grid 5000 site: #{argSite}"
puts "Ceph Release: #{argRelease}"
puts "Grid'5000 deployment for Ceph client: #{argEnvClient}"
puts "For Ceph cluster deployment: #{argDFSName}"
puts "Total number of Ceph clients: #{argNumClients}"
puts "Deployment time: #{argWallTime}\n" + "\n"

# Get all jobs submitted in a cluster
jobs = g5k.get_my_jobs(argSite) 

# get the jobs with name "cephCluster" and "cephClient"
jobCephCluster = nil
jobCephClient = nil
jobs.each do |job|
puts job["name"]
   if job["name"] == argDFSName # Get the Ceph cluster job, if it exists
      jobCephCluster = job
   end
   if job["name"] == argClientName # Get the Ceph client job, if it exists
      jobCephClient = job
   end
end

nodes = nil
unless jobCephCluster.nil? # No deployed cluster --> use client with Ceph production only
   nodes = jobCephCluster["assigned_nodes"] # get nodes for deployed Ceph cluster
else
   puts "Deployed Ceph cluster does not exist on #{argSite}."
   puts "Will use Ceph client with production cluster only."
end

if jobCephClient.nil? # reserve node & deploy Ceph Client
   jobCephClient = g5k.reserve(:name => argClientName, :nodes => argNumClients, :site => argSite, :walltime => argWallTime, :env => argEnvClient, :keys => "~/public/id_rsa")

else # jobCephClient exists already, just redeploy it
   depCephClient = g5k.deploy(jobCephClient, :env => argEnvClient, :keys => "~/public/id_rsa", :wait => true)
end

# At this point job was created or fetched
puts "Ceph Client job created / recovered." + "\n"

# Change to be read/write from YAML file
nodes = jobCephCluster["assigned_nodes"]
monitor = nodes[0] # Currently single monitor. Later make multiple monitors.
clients = jobCephClient["assigned_nodes"] # Currently single client. Later make multiple clients.
osdNodes = nodes - [monitor]

# At this point the necessary jobs were created / fetched.
puts "Deploying Ceph client(s) on nodes: #{clients}" + "\n"


#1 Preflight Checklist
puts "Doing pre-flight checklist..."
# Add (release) Keys to each Ceph node
# rls_key_url = 'https://git.ceph.com/?p=ceph.git;a=blob_plain;f=keys/release.asc'
Cute::TakTuk.start(clients, :user => "root") do |tak|
#     tak.exec!("curl #{rls_key_url} > release.asc")
     tak.put("/home/abasu/public/release.asc", "/root/release.asc")
     tak.exec!("cat ./release.asc  | apt-key add -")
     tak.loop()
end


# Add Ceph & Extras to each Ceph node ('firefly' is the most complete, later use CLI argument)
ceph_extras =  'http://ceph.com/packages/ceph-extras/debian wheezy main'
ceph_update =  'http://ceph.com/debian-#{argRelease}/ wheezy main'

Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.exec!("echo deb #{ceph_extras}  | sudo tee /etc/apt/sources.list.d/ceph-extras.list")
     tak.exec!("echo deb #{ceph_update}  | sudo tee /etc/apt/sources.list.d/ceph.list")
     tak.exec!("export http_proxy=http://proxy:3128; export https_proxy=https://proxy:3128; sudo apt-get update -y && sudo apt-get install -y ceph-deploy")
     tak.loop()
end


# Get config file from monitor
Net::SFTP.start(monitor, 'root') do |sftp|
  sftp.download!("/root/.ssh/config", "/tmp/config")
end

# Prepare .ssh/config file locally
configFile = File.open("/tmp/config", "a") do |file|
   clients.each do |node|
      file.puts("Host #{node}")
      file.puts("   Hostname #{node}")
      file.puts("   User root")
      file.puts("   StrictHostKeyChecking no")
   end
end

# Copy updated config for Ceph to monitor node
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.put("/tmp/config", "/root/.ssh/config") # copy updated config file to monitor
     tak.loop()
end


# Push ssh public key to all nodes
Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.put(".ssh/#{ssh_key}.pub", "/root/.ssh/#{ssh_key}.pub")
     tak.exec!("cat /root/.ssh/#{ssh_key}.pub >> /root/.ssh/authorized_keys")
     tak.loop()
end

# Preflight checklist completed.
puts "Pre-flight checklist completed." + "\n"


# Purging any previous Ceph installations.
puts "Purging any previous Ceph installations..."

clientsShort = clients.map do |node|  # array of short names of nodes
     node.split(".").first
end
clientsList = clientsShort.join(' ') # text list of short names separated by spaces

# Cleanup: Purge previous Ceph installations if any & clear config
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy purge #{clientsList}")
     tak.exec!("ceph-deploy forgetkeys")
     tak.exec!("rm -f ceph.conf")
     tak.loop()
end

# Purged previous Ceph installations.
puts "Purged previous Ceph installations." + "\n"


# Creating & installing Ceph cluster.
puts "Creating & installing Ceph cluster..."

# Create the ceph cluster on the monitor node
monitorShort = monitor.split(".").first
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy new #{monitorShort}")
     tak.loop()
end


# Get initial config file from ceph master/monitor
Net::SFTP.start(monitor, 'root') do |sftp|
  sftp.download!("ceph.conf", "ceph.conf")
end

# Read the following important parameters from file & keep in memory
fsid = ""
confFile = File.open("ceph.conf", "r") do |file|
   file.each_line do |line|
      if line.include? "fsid"
         fsid = line.split(" = ").last.split("\n").first
      end
   end
end

# Update lines for Ceph client in ceph.conf file
# Prepare the list of short names of all monitors as a text string
monAllNodesShort = monAllNodes.map do |node|  # array of short names of monitors
     node.split(".").first
end
monAllNodesList = monAllNodesShort.join(', ') # text list of short names separated by comma

# Prepare the list of IP addresses of all monitors as a text string
monAllNodesIP = monAllNodes.map do |node|  # array of IP addresses of monitors
     Socket.getaddrinfo(node, "http", nil, :STREAM)[0][2]
end
monAllNodesIPList = monAllNodesIP.join(', ') # text list of IP address separated by comma

# Read template file ceph.conf.erb
template = ERB.new File.new("./dss5k/ceph.conf.erb").read, nil, "%"
# Fill up variables
mon_initial_members = monAllNodesList
mon_host = monAllNodesIPList
public_network = monAllNodesIP[0]
radosgw_host = monAllNodes[0]
# Write result to config file ceph.conf
cephFileText = template.result(binding)
File.open("ceph.conf", 'w+') do |file|
   file.write(cephFileText)
end


# Then put ceph.conf file to all nodes
Cute::TakTuk.start(nodes, :user => "root") do |tak|
     tak.exec!("rm ceph.conf")
     tak.exec!("mkdir /etc/ceph; touch /etc/ceph/ceph.conf")
     tak.put("ceph.conf", "ceph.conf")
     tak.put("ceph.conf", "/etc/ceph/ceph.conf")
     tak.loop()
end


# Install ceph on all client nodes
clientNodesShort = [] # array of short names for all client nodes
clients.each do |node|
     clientShort = node.split(".").first
     clientNodesShort += clientShort
     Cute::TakTuk.start([node], :user => "root") do |tak|
          tak.exec!("export https_proxy=\"https://proxy:3128\"; export http_proxy=\"http://proxy:3128\"; ceph-deploy install --release #{argRelease} #{clientShort}")
          tak.loop()
     end
end

# Ceph installation on all nodes completed.
puts "Ceph client installation completed." + "\n"


# Monitor added and prepared.
puts "Adding Ceph client(s) #{clients} to cluster ..."

# Push config file and admin keys from monitor node to all ceph clients
clientNodesList = clientNodesShort.join(' ') # short names of all nodes other than master
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy --overwrite-conf admin #{monitorShort} #{clientNodesList}")
     tak.loop()
end

# Ensure correct permissions for ceph.client.admin.keyring
Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.exec!("chmod +r /etc/ceph/ceph.client.admin.keyring")
     tak.loop()
end

# Clients added to cluster.
puts "Client added to Ceph cluster." + "\n"


# Finally check if Ceph Cluster was correctly deployed - result should be "active+clean"
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     result = tak.exec!("ceph status")
     end_result = result[monitor][:output]
     if end_result.include? "active+clean"
        puts "Ceph cluster up and running. In state 'active+clean'." + "\n"
     end
     tak.loop()
end



# Creating & pushing config file for Ceph production cluster.
puts "Creating & pushing config file for Ceph production cluster ..."

# Prepare ceph.conf file for production Ceph cluster
configFile = File.open("/tmp/ceph.conf", "w") do |file|
   file.puts("[global]")
   file.puts("  mon initial members = ceph0,ceph1,ceph2")
   file.puts("  mon host = 172.16.111.30,172.16.111.31,172.16.111.32")
end

# Then put ceph.conf file to all client nodes
user = g5k.g5k_user
Cute::TakTuk.start(clients, :user => "root") do |tak|
     result = tak.exec!("curl -k https://api.grid5000.fr/sid/storage/ceph/auths/#{user}.keyring | cat - > /etc/ceph/ceph.client.#{user}.keyring")
puts result
     tak.exec!("rm -rf prod/")
     tak.exec!("mkdir prod/; touch prod/ceph.conf")
     tak.put("/tmp/ceph.conf", "prod/ceph.conf")
     tak.loop()
end

# Created & pushed config file for Ceph production cluster.
puts "Created & pushed config file for Ceph production cluster to all clients." + "\n"


