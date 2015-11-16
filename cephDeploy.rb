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
require "net/http"
require "uri"


g5k = Cute::G5K::API.new()
user = g5k.g5k_user

# Populate the hash with default parameters from YAML file.
defaults = begin
  YAML.load(File.open("dss5k/config/defaults.yml"))
rescue ArgumentError => e
  puts "Could not parse YAML: #{e.message}"
end

# banner for script
opts = Trollop::options do
  version "ceph-deploy 0.0.3 (c) 2015-16 Anirvan BASU, INRIA RBA"
  banner <<-EOS
ceph-deploy.rb is a script for deploying a Ceph DFS on reserved nodes.

Usage:
       ceph-deploy.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
  opt :g5kCluster, "Grid 5000 cluster in specified site", :type => String, :default => defaults["g5kCluster"]
  opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
  opt :env, "G5K environment to be deployed", :type => String, :default => defaults["env"]
  opt :jobName, "Name of Grid'5000 job if already created", :type => String, :default => defaults["jobName"]
  opt :cephCluster, "Ceph cluster name", :type => String, :default => defaults["cephCluster"]
  opt :numNodes, "Nodes in Ceph cluster", :default => defaults["numNodes"]
  opt :walltime, "Wall time for Ceph cluster deployed", :type => String, :default => defaults["walltime"]
  opt :multiOSD, "Multiple OSDs on each node", :default => defaults["multiOSD"]
  opt :poolName, "Name of pool to create on Ceph clusters", :type => String, :default => defaults["poolName"]
  opt :poolSize, "Size of pool to create on Ceph clusters", :default => defaults["poolSize"]
  opt :rbdName, "Name of rbd to create inside Ceph pool", :type => String, :default => defaults["rbdName"]
  opt :rbdSize, "Size of rbd to create inside Ceph pool", :default => defaults["rbdSize"]
  opt :fileSystem, "File System to be formatted on created RBDs", :type => String, :default => defaults["fileSystem"]
  opt :mntDepl, "Mount point for RBD on deployed cluster", :type => String, :default => defaults["mntDepl"]
  opt :mntProd, "Mount point for RBD on production cluster", :type => String, :default => defaults["mntProd"]
end

# Move CLI arguments into variables. Later change to class attributes.
argSite = opts[:site] # site name. 
argG5KCluster = opts[:g5kCluster] # G5K cluster name if specified. 
argRelease = opts[:release] # Ceph release name. 
argEnv = opts[:env] # Grid'5000 environment to deploy. 
argEnvClient = "jessie-x64-nfs" # Grid'5000 environment to deploy Ceph client. 
argJobName = opts[:jobName] # Grid'5000 ndoes reservation job. 
argCephCluster = opts[:cephCluster] # Ceph cluster name.
argNumNodes = opts[:numNodes] # number of nodes in Ceph cluster.
argWallTime = opts[:walltime] # walltime for the reservation.
argMultiOSD = opts[:multiOSD] # Multiple OSDs on each node.
argPoolName = "#{user}_" + opts[:poolName] # Name of pool to create on clusters.
argPoolSize = opts[:poolSize] # Size of pool to create on clusters.
argRBDName = "#{user}_" + opts[:rbdName] # Name of pool to create on clusters.
argRBDSize = opts[:rbdSize] # Size of pool to create on clusters.
argFileSystem = opts[:fileSystem] # File System to be formatted on created RBDs.
argMntDepl = opts[:mntDepl] # Mount point for RBD on deployed cluster.
argMntProd = opts[:mntProd] # Mount point for RBD on production cluster.

# Show parameters for creating Ceph cluster
puts "Deploying Ceph cluster with the following parameters:"
puts "Grid 5000 site: #{argSite}"
puts "Grid 5000 cluster: #{argG5KCluster}"
puts "Ceph Release: #{argRelease}"
puts "Grid'5000 deployment: #{argEnv}"
puts "Grid'5000 deployment for Ceph client: #{argEnvClient}"
puts "Job name (for nodes reservation): #{argJobName}"
puts "Ceph cluster name: #{argCephCluster}"
puts "Total nodes in Ceph cluster: #{argNumNodes}"
puts "Deployment time: #{argWallTime}\n"
puts "Option for multiple OSDs per node: #{argMultiOSD}\n" + "\n"

# Get all jobs submitted in a cluster
jobs = g5k.get_my_jobs(argSite) 

# get the job with name "cephCluster"
jobCephCluster = nil
jobs.each do |job|
   if job["name"] == argJobName # if job exists already, refresh the deployment
      jobCephCluster = job
      clientNode = jobCephCluster["assigned_nodes"][1]
      dfsNodes = jobCephCluster["assigned_nodes"] - [clientNode]

      depCeph = g5k.deploy(jobCephCluster, :nodes => dfsNodes, :env => argEnv, :keys => "~/public/id_rsa")
      depCephClient = g5k.deploy(jobCephCluster, :nodes => [clientNode], :env => argEnvClient, :keys => "~/public/id_rsa")

      g5k.wait_for_deploy(jobCephCluster)
   end
end

# Finally, if job does not yet exist reserve nodes and deploy
if jobCephCluster == nil
   jobCephCluster = g5k.reserve(:name => argJobName, :nodes => argNumNodes, :site => argSite, :cluster => argG5KCluster, :walltime => argWallTime, :keys => "~/public/id_rsa", :type => :deploy)

   clientNode = jobCephCluster["assigned_nodes"][1]
   dfsNodes = jobCephCluster["assigned_nodes"] - [clientNode]

   depCeph = g5k.deploy(jobCephCluster, :nodes => dfsNodes, :env => argEnv, :keys => "~/public/id_rsa")
   depCephClient = g5k.deploy(jobCephCluster, :nodes => [clientNode], :env => argEnvClient, :keys => "~/public/id_rsa")

   g5k.wait_for_deploy(jobCephCluster)

end

# At this point job was created or fetched
puts "Ceph deployment job details recovered." + "\n"

# Change to be read/write from YAML file
nodes = jobCephCluster["assigned_nodes"]
monitor = nodes[0] # Currently single monitor. Later make multiple monitors.
client = nodes[1] # Currently single client. Later make multiple clients.
osdNodes = nodes - [monitor] - [client]
dataDir = "/tmp"
radosGW = monitor # as of now the machine is the same for monitor & rados GW
monAllNodes = [monitor] # List of all monitors. As of now, only single monitor.

# At this point job was created / fetched
puts "Deploying Ceph cluster #{argCephCluster} as follows:"
puts "Cluster on nodes: #{nodes}" 
puts "Monitor(s) node on: #{monAllNodes}"
puts "Client(s) node on: #{client}"
puts "OSDs on: #{osdNodes}" + "\n"


#1 Preflight Checklist
puts "Doing pre-flight checklist..."
# Add (release) Keys to each Ceph node
Cute::TakTuk.start(nodes, :user => "root") do |tak|
     tak.put("/home/#{user}/public/release.asc", "/root/release.asc")
     tak.exec!("cat ./release.asc  | apt-key add -")
     tak.loop()
end


# Add Ceph & Extras to each Ceph node ('firefly' is the most complete, later use CLI argument)
ceph_extras =  'http://ceph.com/packages/ceph-extras/debian wheezy main'
ceph_update =  'http://ceph.com/debian-#{argRelease}/ wheezy main'

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
puts "Pre-flight checklist completed." + "\n"


# Purging any previous Ceph installations.
puts "Purging any previous Ceph installations..."

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


# Install ceph on all nodes of cluster
nodes.each do |node|
     nodeShort = node.split(".").first
     Cute::TakTuk.start([node], :user => "root") do |tak|
          tak.exec!("export https_proxy=\"https://proxy:3128\"; export http_proxy=\"http://proxy:3128\"; ceph-deploy install --release #{argRelease} #{nodeShort}")
          tak.loop()
     end
end

# Ceph installation on all nodes completed.
puts "Ceph cluster installation completed." + "\n"


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
puts "Monitor & Client added to Ceph cluster." + "\n"


# Prepare & Activate OSDs.
puts "Preparing & activating OSDs..."

osdIndex = 0 # Iteration counter for OSDs created.
# mkdir, Prepare & Activate each OSD
if argMultiOSD # Option for activating multiple OSDs per node

   osdNodes.each do |node|    # loop over all OSD nodes
     nodeShort = node.split(".").first       # the shortname of the node
     g5kCluster = nodeShort.split("-").first # the G5K cluster of the node
     storageDevices = []

     # Prepare URI & get node resources.
     nodeURI = "https://api.grid5000.fr/stable/sites/#{argSite}/clusters/#{g5kCluster}/nodes/#{nodeShort}"
     uri = URI(nodeURI)
     http = Net::HTTP.new(uri.host, uri.port)
     request = Net::HTTP::Get.new(uri.request_uri)
     http.use_ssl = true
     http.verify_mode = OpenSSL::SSL::VERIFY_NONE
     response = http.request(request)
     result = response.body if response.is_a?(Net::HTTPSuccess)

     # Understand node resources
     parsedResult = JSON.parse(result)
     storageDevices = parsedResult["storage_devices"] # Get list of storage devices

     storageDevices.each do |storageDev, index| # loop over each physical disc
        device = storageDev["device"]
        nodeShort = node.split(".").first

        if device == "sda" # deploy OSD only on partition /dev/sda5
           Cute::TakTuk.start([node], :user => "root") do |tak|
               tak.exec!("umount /tmp")
               tak.exec!("mkdir -p /osd.#{osdIndex}")
               tak.exec!("mount /dev/#{device}5 /osd.#{osdIndex}")
               tak.loop()
           end
           Cute::TakTuk.start([monitor], :user => "root") do |tak|
               tak.exec!("ceph-deploy osd prepare #{nodeShort}:/osd.#{osdIndex}")
               tak.exec!("ceph-deploy osd activate #{nodeShort}:/osd.#{osdIndex}")
               tak.loop()
           end
           puts "Prepared & activated OSD.#{osdIndex} on: #{nodeShort}:/dev/#{device}5.\n"

        else  # case of /dev/sdb, /dev/sdc, required to zap disc before deploy 
           # Remove all partitions, create primary partition (1), install FS
           Cute::TakTuk.start([node], :user => "root") do |tak|
               tak.exec!("parted -s /dev/#{device} mklabel msdos")
               tak.exec!("parted -s /dev/#{device} --align optimal mkpart primary 0 100%")
               tak.exec!("mkfs -t #{argFileSystem} /dev/#{device}1")
               tak.loop()
           end # end of TakTuk loop for OSD node

           # Mount the partition on /osd# 
           Cute::TakTuk.start([node], :user => "root") do |tak|
               tak.exec!("rm -rf /osd.#{osdIndex}")
               tak.exec!("mkdir /osd.#{osdIndex}")
               tak.exec!("mount /dev/#{device}1 /osd.#{osdIndex}")
               tak.loop()
           end

           # Prepare & Activate the OSD 
           Cute::TakTuk.start([monitor], :user => "root") do |tak|
               tak.exec!("ceph-deploy osd prepare #{nodeShort}:/osd.#{osdIndex}")
               tak.exec!("ceph-deploy osd activate #{nodeShort}:/osd.#{osdIndex}")
               tak.loop()
           end # end of TakTuk loop for monitor
           puts "Prepared & activated OSD.#{osdIndex} on: #{nodeShort}:/dev/#{device}1.\n"

        end # end of if-else device == "sda"
        osdIndex += 1

     end # loop over storage devices

   end # loop over all OSD nodes

else # Option for single OSD per node

   osdNodes.each do |node|
        nodeShort = node.split(".").first

        Cute::TakTuk.start([node], :user => "root") do |tak|
          tak.exec!("rm -rf /osd.#{osdIndex}")
          tak.exec!("umount /tmp")
          tak.exec!("mkdir /osd.#{osdIndex}")
          tak.exec!("mount /dev/sda5 /osd.#{osdIndex}")
          tak.loop()
        end # end of TakTuk loop for OSD node

        Cute::TakTuk.start([monitor], :user => "root") do |tak|
          tak.exec!("ceph-deploy osd prepare #{nodeShort}:/osd.#{osdIndex}")
          tak.exec!("ceph-deploy osd activate #{nodeShort}:/osd.#{osdIndex}")
          tak.loop()
        end # end of TakTuk loop for monitor

   end # loop over all OSD nodes

end # if-else for single/multi-OSD per node


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
puts "Ceph configuration & keyrings distributed throughout cluster." + "\n"


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
puts "Creating & pushing config file to Ceph client for Ceph production cluster ..."

# Prepare ceph.conf file for production Ceph cluster
configFile = File.open("/tmp/ceph.conf", "w") do |file|
   file.puts("[global]")
   file.puts("  mon initial members = ceph0,ceph1,ceph2")
   file.puts("  mon host = 172.16.111.30,172.16.111.31,172.16.111.32")
end

# Then put ceph.conf file to all client nodes
Cute::TakTuk.start([client], :user => "root") do |tak|
     tak.exec!("rm -rf prod/")
     tak.exec!("mkdir prod/ && touch prod/ceph.conf")
     tak.put("/tmp/ceph.conf", "/root/prod/ceph.conf")
     tak.put("/tmp/ceph.client.#{user}.keyring", "/etc/ceph/ceph.client.#{user}.keyring")
     tak.loop()
end

# Created & pushed config file for Ceph production cluster.
puts "Created & pushed config file for Ceph production cluster to all clients." + "\n"



# Creating Ceph pools on deployed and production clusters.
puts "Creating Ceph pools on deployed and production clusters ..."
poolsList = []
userPool = ""
# Create Ceph pools & RBD
Cute::TakTuk.start([client], :user => "root") do |tak|
     tak.exec!("modprobe rbd")
     # Create pools & RBD on deployed cluster
     tak.exec!("rados mkpool #{argPoolName}")
     tak.exec!("rbd create #{argRBDName} --pool #{argPoolName} --size #{argRBDSize}")

     # Create pools & RBD on production cluster
     result = tak.exec!("rados -c /root/prod/ceph.conf --id #{user} lspools")

     if result[client][:output].include? "#{user}"
        poolsList = result[client][:output].split("\n")
     end
     poolsList.each do |pool|  # logic: it will take the alphabetic-last pool from user
        if pool.include? "#{user}"
           userPool = pool
        end
     end
puts userPool
     unless userPool == ""
        tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} create #{argRBDName} --size #{argRBDSize} -k /etc/ceph/ceph.client.#{user}.keyring")
     else
#       tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} mkpool #{argPoolName} --keyfile /etc/ceph/ceph.client.#{user}.keyring")
        puts "Create at least one RBD pool from the Ceph production frontend\n\n"
        puts "Use this link to create pool: https://api.grid5000.fr/sid/storage/ceph/ui/"
        puts "Then rerun this script.\n"
     end
     tak.loop()
end

# Created & pushed config file for Ceph clusters.
puts "Created Ceph pools on deployed and production clusters as follows :" + "\n"
puts "On deployed cluster:\n"
puts "Pool name: #{argPoolName} , RBD Name: #{argRBDName} , RBD Size: #{argRBDSize} " + "\n"
puts "Created Ceph pools on deployed and production clusters as follows :" + "\n"
puts "On production cluster:\n"
puts "Pool name: #{userPool} , RBD Name: #{argRBDName} , RBD Size: #{argRBDSize} " + "\n"



# Map RBD and create File Systems.
puts "Mapping RBDs in deployed and production Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|
     # Map RBD & create FS on deployed cluster
     tak.exec!("rbd map #{argRBDName} --pool #{argPoolName}")
     tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{argPoolName}/#{argRBDName}")

     # Map RBD & create FS on production cluster
     tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} map #{argRBDName} -k /etc/ceph/ceph.client.#{user}.keyring")
     tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{userPool}/#{argRBDName}")

     tak.loop()
end

# Mapped RBDs and created File Systems.
puts "Mapped RBDs and created File Systems." + "\n"


# Mount RBDs as File Systems.
puts "Mounting RBDs as File Systems in deployed and production Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|
     # mount RBD from deployed cluster
     tak.exec!("rmdir /mnt/#{argMntDepl}")
     tak.exec!("mkdir /mnt/#{argMntDepl}")
     tak.exec!("mount /dev/rbd/#{argPoolName}/#{argRBDName} /mnt/#{argMntDepl}")

     # mount RBD from production cluster
     tak.exec!("rmdir /mnt/#{argMntProd}")
     tak.exec!("mkdir /mnt/#{argMntProd}")
     tak.exec!("mount /dev/rbd/#{userPool}/#{argRBDName} /mnt/#{argMntProd}")

     tak.loop()
end

# Mounted RBDs as File Systems.
puts "Mounted RBDs as File Systems." + "\n"

