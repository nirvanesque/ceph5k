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
   configFile = "ceph5k/config/defaults.yml" # default config file is used.
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
cephManaged.rb is a script for creating RBD and FS on deployed Ceph cluster.

Usage:
       cephManaged.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :jobid, "Oarsub ID of the client job", :default => 0
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
  opt :cluster, "Grid 5000 cluster in specified site", :type => String, :default => defaults["cluster"]
  opt :walltime, "Wall time for Ceph cluster deployed", :type => String, :default => defaults["walltime"]

  opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
  opt :'pool-name', "Pool name on Ceph cluster (userid_ added)", :type => String, :default => defaults["pool-name"]
  opt :'pool-size', "Pool size on Ceph cluster", :default => defaults["poolSize"]
  opt :'rbd-name', "RBD name for Ceph pool (userid_ added)", :type => String, :default => defaults["rbd-name"]
  opt :'rbd-size', "RBD size on Ceph pool", :default => defaults["rbd-size"]
  opt :'file-system', "File System to be formatted on created RBDs", :type => String, :default => defaults["file-system"]
  opt :'mnt-prod', "Mount point for RBD on managed cluster", :type => String, :default => defaults["mnt-prod"]

  opt :'job-client', "Grid'5000 job name for Ceph clients", :type => String, :default => defaults["job-client"]
  opt :'env-client', "G5K environment for client", :type => String, :default => defaults["env-client"]
  opt :'num-client', "Nodes in Ceph Client cluster", :default => defaults["num-client"]
  opt :'client-pool-name', "Pool name on each Ceph client (userid_ is added)", :type => String, :default => defaults["client-pool-name"]
  opt :'client-pool-size', "Pool size for each Ceph client (~ pool-size / num-clients)", :default => defaults["client-pool-size"]
  opt :'client-rbd-name', "RBD name on each Ceph client (userid_ added)", :type => String, :default => defaults["client-pool-name"]
  opt :'client-rbd-size', "RBD size for each Ceph client (~ pool-size / num-clients)", :default => defaults["client-pool-size"]

end

# Move CLI arguments into variables. Later change to class attributes.
argJobID = opts[:jobid] # Oarsub ID of the client job. 
argSite = opts[:site] # site name. 
argG5KCluster = opts[:cluster] # G5K cluster name if specified. 
argWallTime = opts[:walltime] # walltime for the client reservation.

argRelease = opts[:release] # Ceph release name. 
argPoolName = "#{user}_" + opts[:'pool-name'] # Name of pool to create on clusters.
argPoolSize = opts[:'pool-size'] # Size of pool to create on clusters.
argRBDName = "#{user}_" + opts[:'rbd-name'] # Name of pool to create on clusters.
argRBDSize = opts[:'rbd-size'] # Size of pool to create on clusters.
argFileSystem = opts[:'file-system'] # File System to be formatted on created RBDs.
argMntProd = opts[:'mnt-prod'] # Mount point for RBD on production cluster.


argEnvClient = opts[:'env-client'] # Grid'5000 environment to deploy Ceph clients. 
argJobClient = opts[:'job-client'] # Grid'5000 job name for Ceph clients. 
argNumClient = opts[:'num-client'] # Nodes in Ceph Client cluster.
argClientPoolName = "#{user}_" + opts[:'client-pool-name'] # Pool name on each Ceph client.
argClientRBDName = "#{user}_" + opts[:'client-rbd-name'] # RBD name for each Ceph client.
argClientPoolSize = opts[:'client-pool-size'] # Pool size on each Ceph client.
argClientRBDSize = opts[:'client-rbd-size'] # RBD size for each Ceph client.
# argClientPoolSize = (argPoolSize.to_i / argNumClient.to_i).floor # Calc. pool size automatically.
# argClientRBDSize = (argRBDSize.to_i / argNumClient.to_i).floor # Calc. RBD size automatically.


# Next get job for Ceph clients
jobCephClient = nil # Ceph client job
clients = [] # Array of client nodes

unless [nil, 0].include?(argJobID)
   # If jobID is specified, get the specific job
   jobCephClient = g5k.get_job(argSite, argJobID)
else
   # Get all jobs submitted in a cluster
   jobs = g5k.get_my_jobs(argSite, state = "running") 

   # get the job with name "cephClient"
   jobs.each do |job|
      if job["name"] == argJobClient # if client job exists already, get nodes
         jobCephClient = job
         clients = jobCephClient["assigned_nodes"]

      end # if job["name"] == argJobName
   end # jobs.each do |job|
end # if argJobID
# At this point job details were fetched
puts "Ceph client job details recovered." + "\n"  unless jobCephClient.nil?


# Finally, if Ceph client job does not yet exist reserve nodes
if jobCephClient.nil?

   puts "No existing Ceph client job, creating one with parameters." + "\n" 
   jobCephClient = g5k.reserve(:name => argJobClient, :nodes => argNumClient, :site => argSite, :cluster => argG5KCluster, :walltime => argWallTime, :type => :deploy)
   clients = jobCephClient["assigned_nodes"]

end # if jobCephClient.nil?


# Get the client for the managed Ceph cluster
# This is the 'first' node of the job
client = jobCephClient["assigned_nodes"][0]

deployDetails = jobCephClient["deploy"]
puts deployDetails
# Check if Ceph client is already connected to deployed Cluster.
deployFlag = false
unless jobCephClient["deploy"].nil? # if client deployment was already done

   # Check to see if client is already connected to deployed Ceph
   Cute::TakTuk.start([client], :user => "root") do |tak|
        result = tak.exec!("ceph status")
        deployFlag = true if result[client][:output].include? "active+clean"
        tak.loop()
   end # Cute::TakTuk.start([client]

end # if jobCephClient["deploy"].include?(client)

# Deploy the client node ONLY if not connected to deployed Ceph
if deployFlag
   puts "Client node #{client} already connected to deployed Ceph cluster" + "\n"
   puts "Moving on to add client to managed Ceph cluster without deployment" + "\n"
else
   puts "Deploying #{argEnvClient} on client node: #{client}" + "\n"
   depCephClient = g5k.deploy(jobCephClient, :nodes => [client], :env => argEnvClient) 
   g5k.wait_for_deploy(jobCephClient)
end

# Remind where is the Ceph client
puts "Managed Ceph client on: #{client}" + "\n"


# Prepare ceph.conf file for managed Ceph cluster
configFile = File.open("ceph5k/prod/ceph.conf", "w") do |file|
   file.puts("[global]")
   file.puts("  mon initial members = ceph0")
   file.puts("  mon host = 172.16.111.30")
end

# Then put ceph.conf file to the client
Cute::TakTuk.start([client], :user => "root") do |tak|
     tak.exec!("rm -rf prod/")
     tak.exec!("mkdir prod/ && touch prod/ceph.conf")
     tak.put("ceph5k/prod/ceph.conf", "/root/prod/ceph.conf")
     tak.put("/tmp/ceph.client.#{user}.keyring", "/etc/ceph/ceph.client.#{user}.keyring")
     tak.loop()
end

# Created & pushed config file for Managed Ceph cluster.
puts "Created & pushed config file for managed Ceph cluster to client." + "\n"


# Creating Ceph pools on managed cluster.
puts "Creating Ceph pool on managed cluster ..."
poolsList = []
userPool = ""
userPoolMatch = ""
userRBD = ""
prodCluster = false
abortFlag = false
# Create Ceph pools & RBD
Cute::TakTuk.start([client], :user => "root") do |tak|
     tak.exec!("modprobe rbd")
     # Create RBD on managed cluster
     result = tak.exec!("rados -c /root/prod/ceph.conf --id #{user} lspools")
     poolsList = result[client][:output].split("\n")

     poolCount = 0
     poolsList.each do |pool|  # logic: it will take the alphabetic-last pool from user
        userRBD = ""
        if pool.include? "#{user}"
           userPool = pool
           poolCount += 1
           userPoolMatch = pool if pool.include? "#{argPoolName}" # Perfect match of pool name
           # Check if RBD is already created, may contain data
           resultPool = tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} ls")

           unless resultPool[client][:output].nil? # means no rbd in userPool
              if resultPool[client][:output].include? "#{argRBDName}" 
                 userRBD = argRBDName # There is an rbd with name argRBDName already
              end # if resultPool[client][:output].include?
           end # unless resultPool[client][:output].nil?

        end # if pool.include? "#{user}"

     end # poolsList.each do

     unless userPool.empty?
        # If multiple pools from user, then confused, so exit.
        
        abort("Script exited - multiple Ceph pools for #{user}") if poolCount > 1 && userPoolMatch.empty?

        if userRBD.empty? # There was no rbd created for the user. So create it.
           result = tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} create #{argRBDName} --size #{argRBDSize} -k /etc/ceph/ceph.client.#{user}.keyring")
        end # if userRBD.empty?
     else   # There is no pool created on managed Ceph
      # Following command cannot be done at CLI on Ceph client
      # tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} mkpool #{argPoolName} --keyfile /etc/ceph/ceph.client.#{user}.keyring")
        puts "Create at least one RBD pool from the Ceph managed frontend\n\n"
        puts "Use this link to create pool: https://api.grid5000.fr/sid/storage/ceph/ui/"
        puts "Then rerun this script.\n"
        abortFlag = true
        break
     end # if userRBD.empty?
     tak.loop()
end

# Abort script if no pool in managed Ceph
abort("Script exited") if abortFlag

# Created Pool & RBD for Ceph cluster.
unless userPool.empty?
     puts "Created Ceph pool on managed cluster as follows :" + "\n"
     puts "On managed cluster:\n"
     puts "Pool name: #{userPool} , RBD Name: #{argRBDName} , RBD Size: #{argRBDSize} " + "\n"
end # unless userPool.empty?



# Map RBD and create File Systems.
puts "Mapping RBD in managed Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|
     # Map RBD & create FS on deployed cluster
     result = tak.exec!("rbd map #{argRBDName} --pool #{argPoolName}")
     tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{argPoolName}/#{argRBDName}")
     if result[client][:status] == 0
        puts "Mapped RBD #{argRBDName} on deployed Ceph." + "\n"
     end


     myRBDName = ""
     # Map RBD & create FS on managed cluster
     tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} map #{argRBDName} -k /etc/ceph/ceph.client.#{user}.keyring")
     if userRBD.empty? # Do it only the first time when the RBD is created.
        tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{userPool}/#{argRBDName}")
        myRBDName = argRBDName
     else              # This case is when RBD is already created earlier.
        myRBDName = userRBD
     end # if userRBD.empty?
     if result[client][:status] == 0
        puts "Mapped RBD #{myRBDName} on managed Ceph." + "\n"
     end

     tak.loop()
end


# Mount RBDs as File Systems.
puts "Mounting RBD as File Systems in managed Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|

     result = nil
     # mount RBD from managed cluster
     if userRBD.empty? # Do it only the first time when the RBD is created.
        tak.exec!("umount /dev/rbd/#{userPool}/#{argRBDName} /mnt/#{argMntProd}")
        tak.exec!("rmdir /mnt/#{argMntProd}")
        tak.exec!("mkdir /mnt/#{argMntProd}")
        result = tak.exec!("mount /dev/rbd/#{userPool}/#{argRBDName} /mnt/#{argMntProd}")
     else              # This case is when RBD is already created earlier.
        tak.exec!("umount /dev/rbd/#{userPool}/#{userRBD} /mnt/#{argMntProd}")
        tak.exec!("rmdir /mnt/#{argMntProd}")
        tak.exec!("mkdir /mnt/#{argMntProd}")
        result = tak.exec!("mount /dev/rbd/#{userPool}/#{userRBD} /mnt/#{argMntProd}")
     end # if userRBD.empty?

     if result[client][:status] == 0
        puts "Mounted RBD as File System on managed Ceph." + "\n"
     end

     tak.loop()
end

