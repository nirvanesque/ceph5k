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
rbdDeployed.rb is a script for creating RBD and FS on deployed Ceph cluster.

Usage:
       rbdDeployed.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
  opt :'job-name', "Name of Grid'5000 job if already created", :type => String, :default => defaults["job-name"]
  opt :'pool-name', "Name of pool to create on Ceph clusters", :type => String, :default => defaults["pool-name"]
  opt :'pool-size', "Size of pool to create on Ceph clusters", :default => defaults["poolSize"]
  opt :'rbd-name', "Name of rbd to create inside Ceph pool", :type => String, :default => defaults["rbd-name"]
  opt :'rbd-size', "Size of rbd to create inside Ceph pool", :default => defaults["rbd-size"]
  opt :'file-system', "File System to be formatted on created RBDs", :type => String, :default => defaults["file-system"]
  opt :'mnt-depl', "Mount point for RBD on deployed cluster", :type => String, :default => defaults["mnt-depl"]
end

# Move CLI arguments into variables. Later change to class attributes.
argSite = opts[:site] # site name. 
argJobName = opts[:'job-name'] # Grid'5000 ndoes reservation job. 
argPoolName = "#{user}_" + opts[:'pool-name'] # Name of pool to create on clusters.
argPoolSize = opts[:'pool-size'] # Size of pool to create on clusters.
argRBDName = "#{user}_" + opts[:'rbd-name'] # Name of pool to create on clusters.
argRBDSize = opts[:'rbd-size'] # Size of pool to create on clusters.
argFileSystem = opts[:'file-system'] # File System to be formatted on created RBDs.
argMntDepl = opts[:'mnt-depl'] # Mount point for RBD on deployed cluster.

# Get all jobs submitted in a cluster
jobs = g5k.get_my_jobs(argSite) 

# get the job with name "cephCluster"
jobCephCluster = nil
jobs.each do |job|
   if job["name"] == argJobName # if job exists already, refresh the deployment
      jobCephCluster = job
   end
end


# At this point job details were fetched
puts "Ceph deployment job details recovered." + "\n"

# Change to be read/write from YAML file
nodes = jobCephCluster["assigned_nodes"]
monitor = nodes[0] # Currently single monitor. Later make multiple monitors.
client = nodes[1] # Currently single client. Later make multiple clients.
osdNodes = nodes - [monitor] - [client]
monAllNodes = [monitor] # List of all monitors. As of now, only single monitor.

# Remind where is the Ceph client
puts "Ceph client on: #{client}" + "\n"


# Creating Ceph pools on deployed and production clusters.
puts "Creating Ceph pool on deployed cluster ..."
poolsList = []
userPool = ""
userRBD = ""
prodCluster = false
# Create Ceph pools & RBD
Cute::TakTuk.start([client], :user => "root") do |tak|
     tak.exec!("modprobe rbd")
     # Create pools & RBD on deployed cluster
     tak.exec!("rados mkpool #{argPoolName}")
     tak.exec!("rbd create #{argRBDName} --pool #{argPoolName} --size #{argRBDSize}")

     tak.loop()
end

# Created Pool & RBD for Ceph deployed cluster.
puts "Created Ceph pool on deployed cluster as follows :" + "\n"
puts "Pool name: #{argPoolName} , RBD Name: #{argRBDName} , RBD Size: #{argRBDSize} " + "\n"


# Map RBD and create File Systems.
puts "Mapping RBD in deployed Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|
     # Map RBD & create FS on deployed cluster
     result = tak.exec!("rbd map #{argRBDName} --pool #{argPoolName}")
     tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{argPoolName}/#{argRBDName}")
     if result[client][:status] == 0
        puts "Mapped RBD #{argRBDName} on deployed Ceph." + "\n"
     end

     tak.loop()
end


# Mount RBDs as File Systems.
puts "Mounting RBD as File System in deployed Ceph cluster ..."
Cute::TakTuk.start([client], :user => "root") do |tak|

     # mount RBD from deployed cluster
     tak.exec!("umount /dev/rbd/#{argPoolName}/#{argRBDName} /mnt/#{argMntDepl}")
     tak.exec!("rmdir /mnt/#{argMntDepl}")
     tak.exec!("mkdir /mnt/#{argMntDepl}")
     result = tak.exec!("mount /dev/rbd/#{argPoolName}/#{argRBDName} /mnt/#{argMntDepl}")
     if result[client][:status] == 0
        puts "Mounted RBD as File System on deployed Ceph." + "\n"
     end

     tak.loop()
end


