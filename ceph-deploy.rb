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
ceph-deploy.rb is a script for deploying a Ceph DFS on reserved nodes.

Usage:
       ceph-deploy.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => "sophia"
  opt :release, "Ceph Release name", :type => String, :default => "firefly"
  opt :cluster, "Ceph cluster name", :type => String, :default => "ceph"
  opt :numNodes, "Nodes in Ceph cluster", :default => 5
  opt :walltime, "Wall time for Ceph cluster deployed", :type => String, :default => "01:00:00"
end

# Move CLI arguments into variables. Later change to class attributes.
argSite = opts[:site] # site name. 
argRelease = opts[:release] # Ceph release name. 
argCluster = opts[:cluster] # Ceph cluster name.
argNumNodes = opts[:numNodes] # number of nodes in Ceph cluster.
argWallTime = opts[:walltime] # walltime for the reservation.



# Show parameters for creating Ceph cluster
puts "Deploying Ceph cluster with the following parameters:"
puts "Grid 5000 site: #{argSite}"
puts "Ceph Release: #{argRelease}"
puts "Ceph cluster name: #{argCluster}"
puts "Total nodes in Ceph cluster: #{argNumNodes}"
puts "Deployment time: #{argWallTime}\n"

# Get all jobs submitted in a cluster
jobs = g5k.get_my_jobs(argSite) 

# get the job with name "cephCluster"
jobCephCluster = nil
jobs.each do |job|
   if job["name"] == "cephCluster" 
      jobCephCluster = job
      if jobCephCluster["deploy"] == nil # If undeployed, deploy it
         depCeph = g5k.deploy(jobCephCluster, :env => "wheezy-x64-nfs", :keys => "~/public/id_rsa", :wait => true)
      end
   end
end

# Finally, if job does not yet exist create with name "cephCluster"
if jobCephCluster == nil
   jobCephCluster = g5k.reserve(:name => "cephCluster", :nodes => argNumNodes, :site => argSite, :walltime => argWallTime, :env => "wheezy-x64-nfs", :keys => "~/public/id_rsa")
end

# At this point job was created or fetched
puts "Ceph deployment job details recovered."

# Change to be read/write from YAML file
nodes = jobCephCluster["assigned_nodes"]
monitor = nodes[0] # Currently single monitor. Later make multiple monitors.
osdNodes = nodes - [monitor]
dataDir = "/tmp"
radosGW = monitor # as of now the machine is the same for monitor & rados GW
monAllNodes = [monitor] # List of all monitors. As of now, only single monitor.

# At this point job was created / fetched
puts "Deploying Ceph cluster #{argCluster} as follows:"
puts "Cluster on nodes: #{nodes}" 
puts "Monitor(s) node on: #{monAllNodes}"
puts "OSDs on: #{osdNodes}\n"


#1 Preflight Checklist
puts "Doing pre-flight checklist..."
# Add (release) Keys to each Ceph node
# rls_key_url = 'https://git.ceph.com/?p=ceph.git;a=blob_plain;f=keys/release.asc'
Cute::TakTuk.start(nodes, :user => "root") do |tak|
#     tak.exec!("curl #{rls_key_url} > release.asc")
     tak.put("/home/abasu/public/release.asc", "/root/release.asc")
     tak.exec!("cat ./release.asc  | apt-key add -")
     tak.loop()
end


# Add Ceph & Extras to each Ceph node ('firefly' is the most complete, later use CLI argument)
ceph_extras =  'http://ceph.com/packages/ceph-extras/debian wheezy main'
ceph_update =  'http://ceph.com/debian-#{argRelease}/ wheezy main'
# ceph_version = 'http://ceph.com/debian-firefly/pool/main/c/ceph/ceph-common_0.80.9-1precise_amd64.deb'
# ceph_version = 'http://ceph.com/debian-hammer/pool/main/c/ceph-deploy/ceph-deploy_1.5.27precise_all.deb'


Cute::TakTuk.start(nodes, :user => "root") do |tak|
     tak.exec!("echo deb #{ceph_extras}  | sudo tee /etc/apt/sources.list.d/ceph-extras.list")
     tak.exec!("echo deb #{ceph_update}  | sudo tee /etc/apt/sources.list.d/ceph.list")
     tak.exec!("export http_proxy=http://proxy:3128; export https_proxy=https://proxy:3128; sudo apt-get update -y && sudo apt-get install -y ceph-deploy")
     tak.loop()
end


# Prepare .ssh/config file locally
configFile = File.open("/tmp/config", "w") do |file|
   nodes.each do |node|
      file.puts("Host #{node}")
      file.puts("   Hostname #{node}")
      file.puts("   User root")
      file.puts("   StrictHostKeyChecking no")
   end
end

# Get ssh_config file from master/monitor
Net::SFTP.start(monitor, 'root') do |sftp|
  sftp.download!("/etc/ssh/ssh_config", "ssh_config")
end

# In ssh_config file (local) add a line to avoid StrictHostKeyChecking
configFile = File.open("ssh_config", "a") do |file|
   file.puts("    StrictHostKeyChecking no") # append only once
end

# Copy ssh keys & config for Ceph on monitor/master node
ssh_key =  'id_rsa'
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.put(".ssh/#{ssh_key}", "/root/.ssh/#{ssh_key}") # copy the config file to master/monitor
     tak.put(".ssh/#{ssh_key}.pub", "/root/.ssh/#{ssh_key}.pub") # copy the config file to master/monitor
     tak.put("/tmp/config", "/root/.ssh/config") # copy the config file to master/monitor
     tak.loop()
end

# Push ssh_config file & ssh public key to all nodes
Cute::TakTuk.start(nodes, :user => "root") do |tak|
     tak.put("ssh_config", "/etc/ssh/ssh_config")
     tak.put(".ssh/#{ssh_key}.pub", "/root/.ssh/#{ssh_key}.pub")
     tak.exec!("cat /root/.ssh/#{ssh_key}.pub >> /root/.ssh/authorized_keys")
     tak.loop()
end

# Preflight checklist completed.
puts "Pre-flight checklist completed.\n"


# Creating & installing Ceph cluster.
puts "Creating & installing Ceph cluster..."

nodesShort = nodes.map do |node|  # array of short names of nodes
     node.split(".").first
end
nodesList = nodesShort.join(' ') # text list of short names separated by spaces

# Cleanup: Purge previous Ceph installations if any & clear config
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy purge #{nodesList}")
     tak.exec!("ceph-deploy forgetkeys")
     tak.exec!("rm -f ceph.conf")
     tak.loop()
end


# Create the ceph cluster
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

# Update certain lines in ceph.conf file
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
template = ERB.new File.new("ceph.conf.erb").read, nil, "%"
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


# Install ceph on all nodes of cluster
nodes.each do |node|
     nodeShort = node.split(".").first
     Cute::TakTuk.start([node], :user => "root") do |tak|
          tak.exec!("export https_proxy=\"https://proxy:3128\"; export http_proxy=\"http://proxy:3128\"; ceph-deploy install --release #{argRelease} #{nodeShort}")
          tak.loop()
     end
end

# Ceph installation on all nodes completed.
puts "Ceph cluster installation completed.\n"


# Adding & preparing monitor.
puts "Adding monitor #{monitor} to cluster..."

# Add initial monitor/master
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy --overwrite-conf mon create-initial")
     tak.loop()
end


# Push config file and admin keys from master/monitor/admin node to all ceph nodes
otherNodesShort = nodesShort - [monitorShort]
otherNodesList = otherNodesShort.join(' ') # short names of all nodes other than master
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy --overwrite-conf admin #{monitorShort} #{otherNodesList}")
     tak.loop()
end

# Ensure correct permissions for ceph.client.admin.keyring
Cute::TakTuk.start(nodes, :user => "root") do |tak|
     tak.exec!("chmod +r /etc/ceph/ceph.client.admin.keyring")
     tak.loop()
end

# Monitor added and prepared.
puts "Monitor added to Ceph cluster.\n"


# Prepare & Activate OSDs.
puts "Preparing & activating OSDs..."

# mkdir, Prepare & Activate each OSD
osdIndex = 0 # change to check if osdIndex file exists, then initialise from there
osdNodes.each_with_index do |node, index| # loop over all OSD nodes
     nodeShort = node.split(".").first       # the shortname of the node
     g5kCluster = nodeShort.split("-").first # the G5K cluster of the node
     Cute::TakTuk.start([node], :user => "root") do |tak|
          result = tak.exec!("curl -kn 'https://api.grid5000.fr/sid/sites/#{argSite}/clusters/#{g5kCluster}/nodes/#{nodeShort}'")
          output = result[node][:output]
          parsedOutput = JSON.parse(output)
          storageDevices = parsedOutput["storage_devices"]
          storageDevices.each do |storageDev| # loop over each physical disc
             device = storageDev["device"]
             unless device == "sda" # deploy OSD only on partition /dev/sda5
                tak.exec!("ceph-deploy osd prepare #{nodeShort}:/dev/#{device}5")
                tak.exec!("ceph-deploy osd activate #{nodeShort}:/dev/#{device}5")
                puts "Prepared & activated OSD: #{nodeShort}:/dev/#{device}5\n\n"
             else  # deploy OSD on all discs as /dev/sdb, /dev/sdc, ...
                tak.exec!("ceph-deploy osd prepare #{nodeShort}:/dev/#{device}")
                tak.exec!("ceph-deploy osd activate #{nodeShort}:/dev/#{device}")
                puts "Prepared & activated OSD: #{nodeShort}:/dev/#{device}\n\n"
             end
             osdIndex += 1
          end # loop over each physical disc
          tak.loop()
     end
end # loop over all OSD nodes


# Write to osdIndex & osdList files locally
confFile = File.open("osdIndex", "w"){ |file|
   file.puts("#{osdIndex + 1}") # Incremental number of last OSD data path
}
confFile = File.open("osdList", "w"){ |file|
   osdNodes.each do |node|
      file.puts("#{node}") # Incremental list of OSD nodes in cluster      
   end
}
confFile = File.open("monList", "w"){ |file|
   [monitor].each do |node|
      file.puts("#{node}") # Incremental list of last monitor nodes      
   end
}


# Then put osdIndex, osdList files to monitor
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("rm osdIndex osdList monList") # Delete old files, if any
     tak.put("osdIndex", "osdIndex")
     tak.put("osdList", "osdList")
     tak.put("monList", "monList")
     tak.loop()
end

# OSDs prepared & activated.
puts "Prepared & Activated following OSDs: #{osdNodes}\r\n"



# Distribute config & keyrings for cluster.
puts "Distributing config and keyrings for cluster..."

# Pull config and keyrings for cluster
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy config pull #{monitorShort}")
     tak.exec!("ceph-deploy gatherkeys #{monitorShort}")
     tak.loop()
end


# Push config file and admin keys from master/monitor/admin node to all ceph nodes
otherNodesShort = nodesShort - [monitorShort]
otherNodesList = otherNodesShort.join(' ') # short names of all nodes other than master
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.exec!("ceph-deploy admin #{monitorShort} #{otherNodesList}")
     tak.loop()
end


# Ensure correct permissions for ceph.client.admin.keyring
Cute::TakTuk.start(nodes, :user => "root") do |tak|
     tak.exec!("chmod +r /etc/ceph/ceph.client.admin.keyring")
     tak.loop()
end

# Config & keyrings distributed.
puts "Config & keyrings distributed throughout cluster.\n"


# Finally check if Ceph Cluster was correctly deployed - result should be "active+clean"
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     result = tak.exec!("ceph status")
     end_result = result[monitor][:output]
     if end_result.include? "active+clean"
        puts "Ceph cluster up and running. In state 'active+clean'.\n"
     end
     tak.loop()
end


