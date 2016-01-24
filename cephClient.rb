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
cephClient.rb is a script for creating RBD and FS on deployed Ceph cluster.

Usage:
       cephClient.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :jobid, "Oarsub ID of the client job", :default => 0
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
  opt :cluster, "Grid 5000 cluster in specified site", :type => String, :default => defaults["cluster"]
  opt :'job-name', "Grid'5000 job name for deployed Ceph cluster", :type => String, :default => defaults["job-name"]
  opt :walltime, "Wall time for Ceph cluster deployed", :type => String, :default => defaults["walltime"]

  opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
  opt :'pool-name', "Pool name on Ceph cluster (userid_ added)", :type => String, :default => defaults["pool-name"]
  opt :'pool-size', "Pool size on Ceph cluster", :default => defaults["poolSize"]
  opt :'rbd-name', "RBD name for Ceph pool (userid_ added)", :type => String, :default => defaults["rbd-name"]
  opt :'rbd-size', "RBD size on Ceph pool", :default => defaults["rbd-size"]
  opt :'file-system', "File System to be formatted on created RBDs", :type => String, :default => defaults["file-system"]
  opt :'mnt-depl', "Mount point for RBD on deployed cluster", :type => String, :default => defaults["mnt-depl"]

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
argJobName = opts[:'job-name'] # Grid'5000 job for deployed Ceph cluster. 
argG5KCluster = opts[:cluster] # G5K cluster name if specified. 
argWallTime = opts[:walltime] # walltime for the client reservation.

argRelease = opts[:release] # Ceph release name. 
argPoolName = "#{user}_" + opts[:'pool-name'] # Name of pool to create on clusters.
argPoolSize = opts[:'pool-size'] # Size of pool to create on clusters.
argRBDName = "#{user}_" + opts[:'rbd-name'] # Name of pool to create on clusters.
argRBDSize = opts[:'rbd-size'] # Size of pool to create on clusters.
argFileSystem = opts[:'file-system'] # File System to be formatted on created RBDs.
argMntDepl = opts[:'mnt-depl'] # Mount point for RBD in deployed cluster.

argEnvClient = opts[:'env-client'] # Grid'5000 environment to deploy Ceph clients. 
argJobClient = opts[:'job-client'] # Grid'5000 job name for Ceph clients. 
argNumClient = opts[:'num-clients'] # Nodes in Ceph Client cluster.
argClientPoolName = "#{user}_" + opts[:'client-pool-name'] # Pool name on each Ceph client.
argClientPoolSize = opts[:'client-pool-size'] # Pool size on each Ceph client.
argClientRBDName = "#{user}_" + opts[:'client-rbd-name'] # RBD name for each Ceph client.
argClientRBDSize = opts[:'client-rbd-size'] # RBD size for each Ceph client.


# get the job with name "cephCluster"
jobCephCluster = nil # Job for deployed Ceph cluster
monitor = "" # Monitor for deployed Ceph cluster
# Get all jobs submitted in a cluster
jobs = g5k.get_my_jobs(argSite, state = "running") 

# get the job with name "cephDeploy"
jobs.each do |job|
   if job["name"] == argJobName # if job exists already, get nodes
      jobCephCluster = job
      monitor = jobCephCluster["assigned_nodes"][0]
   end # if job["name"] == argJobName
end # jobs.each do |job|

# Abort script if no deployed Ceph cluster
abort("No deployed Ceph cluster found. First deploy Ceph cluster, then run script.") if jobCephCluster.nil?

# Remind where is the deployed Ceph monitor
puts "Deployed Ceph cluster details:"
puts "   monitor on: #{monitor}" + "\n"


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
puts "Ceph client job details recovered." + "\n" if !jobCephClient.nil?



# Finally, if Ceph client job does not yet exist reserve nodes
if jobCephClient.nil?

   puts "No existing Ceph client job, creating one with parameters." + "\n" 
   jobCephClient = g5k.reserve(:name => argJobClient, :nodes => argNumClient, :site => argSite, :cluster => argG5KCluster, :walltime => argWallTime, :type => :deploy)
   clients = jobCephCluster["assigned_nodes"][1]

end # if jobCephClient.nil?

puts "Deploying #{argEnvClient} on client node(s): #{clients}" + "\n"
# Finally, deploy the client nodes with respective environments
# depCephClient = g5k.deploy(jobCephClient, :nodes => clients, :env => argEnvClient)
# g5k.wait_for_deploy(jobCephClient)



# Install & administer clients to Ceph deployed cluster.
puts "Adding following clients to deployed Ceph cluster:"
clients.each do |client|
     clientShort = client.split(".").first
     Cute::TakTuk.start([monitor], :user => "root") do |tak|
          tak.exec!("ceph-deploy install --release #{argRelease} #{clientShort}")
          result = tak.exec!("ceph-deploy --overwrite-conf admin #{clientShort}")
          puts "Added client: #{client}" if result[monitor][:status] == 0
          tak.loop()
     end
end # clients.each do


# Create Ceph pools on deployed cluster.
puts "Creating Ceph pools on deployed cluster ..."
# Create Ceph pools & RBDs
Cute::TakTuk.start(clients, :user => "root") do |tak|
     tak.exec!("modprobe rbd")
     tak.exec!("rados mkpool #{argClientPoolName}")
     tak.exec!("rbd create #{argClientRBDName} --pool #{argClientPoolName} --size #{argClientRBDSize}")
     tak.loop()
end

# Created Pools & RBDs for Ceph deployed cluster.
puts "Created Ceph pool on deployed cluster as follows :" + "\n"
puts "Pool name: #{argClientPoolName} , RBD Name: #{argClientRBDName} , RBD Size: #{argClientRBDSize} " + "\n"


# Map RBDs and create File Systems.
puts "Mapping RBD in deployed Ceph clusters ..."
Cute::TakTuk.start(clients, :user => "root") do |tak|
     # Map RBD & create FS on deployed cluster
     tak.exec!("rbd map #{argClientRBDName} --pool #{argClientPoolName}")
     result = tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{argClientPoolName}/#{argClientRBDName}")
     tak.loop()
end
# Mapped RBDs & created FS for clients on Ceph deployed cluster.
puts "Mapped RBDs #{argRBDName} for clients on deployed Ceph." + "\n"


# Mount RBDs on clients.
puts "Mounting RBDs in deployed Ceph clusters on client(s) ..."
clients.each do |client|
   Cute::TakTuk.start([client], :user => "root") do |tak|

        # mount RBD from deployed cluster
        tak.exec!("umount /dev/rbd/#{argClientPoolName}/#{argClientRBDName} /mnt/#{argMntDepl}")
        tak.exec!("rmdir /mnt/#{argMntDepl}")
        tak.exec!("mkdir /mnt/#{argMntDepl}")
        result = tak.exec!("mount /dev/rbd/#{argClientPoolName}/#{argClientRBDName} /mnt/#{argMntDepl}")
        puts "Mounted Ceph RBD on client: #{client}" + "\n" if result[:status] == 0
        tak.loop()
   end
end # clients.each do

