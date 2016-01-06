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

if (["--def-conf", "-d"].include?(ARGV[0])  && !ARGV[1].empty? )
   configFile = ARGV[1] # assign file location to variable configFile
   ARGV.delete_at(0)    # clean up ARGV array
   ARGV.delete_at(0)
else
   configFile = "dss5k/config/defaults.yml" # default config file is used.
end    # if (["--def-conf", "-d"])

# Populate the hash with default parameters from YAML file.
defaults = begin
  YAML.load(File.open(configFile))
rescue ArgumentError => e
  puts "Could not parse YAML: #{e.message}"
end

# banner for script
opts = Trollop::options do
  version "ceph5k 0.0.4 (c) 2015-16 Anirvan BASU, INRIA RBA"
  banner <<-EOS
cephRBD.rb is a script for creating RBD and FS on deployed Ceph and production Ceph.

Usage:
       cephRBD.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :jobid, "Oarsub ID of the job", :default => 0
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
  opt :cluster, "Grid 5000 cluster in specified site", :type => String, :default => defaults["cluster"]
  opt :'job-name', "Name of Grid'5000 job if already created", :type => String, :default => defaults["job-name"]
  opt :'job-client', "Name of Grid'5000 Client job if already created", :type => String, :default => defaults["job-client"]
  opt :'num-clients', "No of clients in Ceph cluster", :default => defaults["num-clients"]
  opt :walltime, "Wall time for Ceph cluster deployed", :type => String, :default => defaults["walltime"]
  opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
  opt :'env-client', "G5K environment for Ceph client", :type => String, :default => defaults["env-client"]
  opt :'pool-name', "Name of pool to create on Ceph clusters", :type => String, :default => defaults["pool-name"]
  opt :'pool-size', "Size of pool to create on Ceph clusters", :default => defaults["poolSize"]
  opt :'rbd-name', "Name of rbd to create inside Ceph pool", :type => String, :default => defaults["rbd-name"]
  opt :'rbd-size', "Size of rbd to create inside Ceph pool", :default => defaults["rbd-size"]
  opt :'file-system', "File System to be formatted on created RBDs", :type => String, :default => defaults["file-system"]
  opt :'mnt-depl', "Mount point for RBD on deployed cluster", :type => String, :default => defaults["mnt-depl"]
  opt :'mnt-prod', "Mount point for RBD on production cluster", :type => String, :default => defaults["mnt-prod"]
end

# Move CLI arguments into variables. Later change to class attributes.
argJobID = opts[:jobid] # Oarsub ID of the Ceph client job. 
argSite = opts[:site] # site name. 
argG5KCluster = opts[:cluster] # G5K cluster name if specified. 
argJobName = opts[:'job-name'] # Grid'5000 Ceph cluster reservation job. 
argJobClient = opts[:'job-client'] # Grid'5000 Ceph client reservation job. 
argEnvClient = opts[:'env-client'] # Grid'5000 environment to deploy Ceph client. 
argNumClients = opts[:'num-clients'] # number of clients in Ceph cluster.
argWallTime = opts[:walltime] # walltime for the reservation.
argRelease = opts[:release] # Ceph release name. 
argPoolName = "#{user}_" + opts[:'pool-name'] # Name of pool to create on clusters.
argPoolSize = opts[:'pool-size'] # Size of pool to create on clusters.
argRBDName = "#{user}_" + opts[:'rbd-name'] # Name of pool to create on clusters.
argRBDSize = opts[:'rbd-size'] # Size of pool to create on clusters.
argFileSystem = opts[:'file-system'] # File System to be formatted on created RBDs.
argMntDepl = opts[:'mnt-depl'] # Mount point for RBD on deployed cluster.
argMntProd = opts[:'mnt-prod'] # Mount point for RBD on production cluster.

# Get all jobs submitted in a cluster
jobs = g5k.get_my_jobs(argSite) 

# Get the job with name "cephClient"
jobCephClient  = nil
clients = []
monitor = ""

unless [nil, 0].include?(argJobID)
   # If jobID is specified, get the specific job
   jobCephClient = g5k.get_job(argSite, argJobID)
else
   # Get all jobs submitted in a cluster
   jobs = g5k.get_my_jobs(argSite, state = "running") 

   # get the job with name "cephClient" This contains the clients list.
   jobs.each do |job|
      if job["name"] == argJobClient # if job exists already, get nodes
         jobCephClient = job
         clients = jobCephClient["assigned_nodes"]
      end # if job["name"] == argJobClient
   end # jobs.each do |job|
end # if argJobID

# Finally, if Client job does not yet exist reserve nodes
if jobCephClient.nil?
   jobCephClient = g5k.reserve(:name => argJobClient, :nodes => argNumClients, :site => argSite, :cluster => argG5KCluster, :walltime => argWallTime, :keys => "~/public/id_rsa", :type => :deploy)
   clients = jobCephClient["assigned_nodes"]
end # if jobCephClient.nil?

# Then, deploy client nodes with respective environments
depCephClient = g5k.deploy(jobCephClient, :nodes => clients, :env => argEnvClient, :keys => "~/public/id_rsa")
g5k.wait_for_deploy(jobCephClient)


# Next, get the job with name "cephCluster" This contains the monitor node.
jobCephCluster = nil
jobs.each do |job|
   if job["name"] == argJobName # if Ceph cluster exists already, get the job details
      jobCephCluster = job
      monitor = jobCephCluster["assigned_nodes"][0]
   end # if job["name"] == argJobName
end  # jobs.each do |job|


# At this point all job details were fetched
puts "Ceph deployment & client job details recovered." + "\n"

# Read some parameters into variables
nodes = jobCephCluster["assigned_nodes"]
monitor = nodes[0] # Currently single monitor. Later make multiple monitors.
client = nodes[1] # Currently single client. Later make multiple clients.


# At this point job was created / fetched
puts "Deploying Ceph client(s) as follows:"
puts "Client(s) node on: #{clients}" + "\n"


#1 Preflight Checklist
puts "Doing pre-flight checklist..."
# Add (release) Keys to each Ceph node
Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.put("/home/#{user}/public/release.asc", "/root/release.asc")
     tak.exec!("cat ./release.asc  | apt-key add -")
     tak.loop()
end


# Add Ceph & Extras to each Ceph node ('firefly' is the most complete) - Is this reqd ?
ceph_extras =  'http://ceph.com/packages/ceph-extras/debian wheezy main'
ceph_update =  'http://ceph.com/debian-#{argRelease}/ wheezy main'

Cute::TakTuk.start(clients, :user => "root") do |tak|
#     tak.exec!("echo deb #{ceph_extras}  | sudo tee /etc/apt/sources.list.d/ceph-extras.list")
#     tak.exec!("echo deb #{ceph_update}  | sudo tee /etc/apt/sources.list.d/ceph.list")
      tak.exec!("export http_proxy=http://proxy:3128; export https_proxy=https://proxy:3128; sudo apt-get update -y && sudo apt-get install -y ceph-deploy")
     tak.loop()
end


# Get .ssh/config & ssh_config files from monitor
Net::SFTP.start(monitor, 'root') do |sftp|
  sftp.download!("/root/.ssh/config", "/tmp/config")
  sftp.download!("/etc/ssh/ssh_config", "ssh_config")
end

# Append to .ssh/config file locally, for each client node
configFile = File.open("/tmp/config", "a") do |file|
   clients.each do |node|
      file.puts("Host #{node}")
      file.puts("   Hostname #{node}")
      file.puts("   User root")
      file.puts("   StrictHostKeyChecking no")
   end
end


# Copy updated config for Ceph on monitor node
Cute::TakTuk.start([monitor], :user => "root") do |tak|
     tak.put("/tmp/config", "/root/.ssh/config") # copy the config file to monitor
     tak.loop()
end

# Push ssh_config file & ssh public key to all client nodes
ssh_key =  'id_rsa'
Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.put("ssh_config", "/etc/ssh/ssh_config")
     tak.put(".ssh/#{ssh_key}.pub", "/root/.ssh/#{ssh_key}.pub")
     tak.exec!("cat /root/.ssh/#{ssh_key}.pub >> /root/.ssh/authorized_keys")
     tak.loop()
end

# Preflight checklist completed.
puts "Pre-flight checklist completed." + "\n"




# Get config file from ceph monitor
Net::SFTP.start(monitor, 'root') do |sftp|
  sftp.download!("ceph.conf", "ceph.conf")
end

# Then put ceph.conf file to all client nodes
Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.exec!("rm ceph.conf")
     tak.exec!("mkdir /etc/ceph; touch /etc/ceph/ceph.conf")
     tak.put("ceph.conf", "ceph.conf")
     tak.put("ceph.conf", "/etc/ceph/ceph.conf")
     tak.loop()
end


# Install ceph on all client nodes
clients.each do |client|
     clientShort = client.split(".").first
     Cute::TakTuk.start([client], :user => "root") do |tak|
          tak.exec!("export https_proxy=\"https://proxy:3128\"; export http_proxy=\"http://proxy:3128\"; ceph-deploy install --release #{argRelease} #{clientShort}")
          tak.loop()
     end
end

# Ceph installation on all nodes completed.
puts "Ceph cluster installation completed." + "\n"



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

