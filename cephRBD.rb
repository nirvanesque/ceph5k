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
cephRBD.rb is a script for creating RBD and FS on deployed Ceph and production Ceph.

Usage:
       cephRBD.rb [options]
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
  opt :'mnt-prod', "Mount point for RBD on production cluster", :type => String, :default => defaults["mnt-prod"]
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
argMntProd = opts[:'mnt-prod'] # Mount point for RBD on production cluster.

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
radosGW = monitor # as of now the machine is the same for monitor & rados GW
monAllNodes = [monitor] # List of all monitors. As of now, only single monitor.

# Remind where is the Ceph client
puts "Ceph client on: #{client}" + "\n"


# Prepare ceph.conf file for production Ceph cluster
configFile = File.open("ceph5k/prod/ceph.conf", "w") do |file|
   file.puts("[global]")
   file.puts("  mon initial members = ceph0,ceph1,ceph2")
   file.puts("  mon host = 172.16.111.30,172.16.111.31,172.16.111.32")
end

# Then put ceph.conf file to all client nodes
Cute::TakTuk.start([client], :user => "root") do |tak|
     tak.exec!("rm -rf prod/")
     tak.exec!("mkdir prod/ && touch prod/ceph.conf")
     tak.put("ceph5k/prod/ceph.conf", "/root/prod/ceph.conf")
     tak.put("/tmp/ceph.client.#{user}.keyring", "/etc/ceph/ceph.client.#{user}.keyring")
     tak.loop()
end

# Created & pushed config file for Ceph production cluster.
puts "Created & pushed config file for Ceph production cluster to all clients." + "\n"



# Creating Ceph pools on deployed and production clusters.
puts "Creating Ceph pools on deployed and production clusters ..."
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

     # Create RBD on production cluster
     result = tak.exec!("rados -c /root/prod/ceph.conf --id #{user} lspools")

     poolsList = result[client][:output].split("\n")

     poolsList.each do |pool|  # logic: it will take the alphabetic-last pool from user
        userRBD = ""
        if pool.include? "#{user}"
           userPool = pool

           # Check if RBD is already created, may contain data
           resultPool = tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} ls")
           unless resultPool[client][:output].nil? # means no rbd in userPool
              if resultPool[client][:output].include? "#{argRBDName}" 
                 userRBD = argRBDName # There is an rbd with name argRBDName already
              end # if resultPool[client][:output].include?
           end # unless resultPool[client][:output].nil?
puts userRBD
        end # if pool.include? "#{user}"

     end # poolsList.each do

     unless userPool.empty?
        if userRBD.empty? # There was no rbd created for the user. So create it.
           result = tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} create #{argRBDName} --size #{argRBDSize} -k /etc/ceph/ceph.client.#{user}.keyring")
puts result
        end # if userRBD.empty?
     else
      # Following command cannot be done at CLI on Ceph client
      # tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} mkpool #{argPoolName} --keyfile /etc/ceph/ceph.client.#{user}.keyring")
        puts "Create at least one RBD pool from the Ceph production frontend\n\n"
        puts "Use this link to create pool: https://api.grid5000.fr/sid/storage/ceph/ui/"
        puts "Then rerun this script.\n"
     end
     tak.loop()
end

# Created Pool & RBD for Ceph clusters.
puts "Created Ceph pools on deployed (and production) clusters as follows :" + "\n"
puts "On deployed cluster:\n"
puts "Pool name: #{argPoolName} , RBD Name: #{argRBDName} , RBD Size: #{argRBDSize} " + "\n"
unless userPool.empty?
     puts "On production cluster:\n"
     puts "Pool name: #{userPool} , RBD Name: #{argRBDName} , RBD Size: #{argRBDSize} " + "\n"
end # unless userPool.empty?



# Map RBD and create File Systems.
puts "Mapping RBDs in deployed and production Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|
     # Map RBD & create FS on deployed cluster
     result = tak.exec!("rbd map #{argRBDName} --pool #{argPoolName}")
     tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{argPoolName}/#{argRBDName}")
     if result[client][:status] == 0
        puts "Mapped RBD #{argRBDName} on deployed Ceph." + "\n"
     end


     myRBDName = ""
     # Map RBD & create FS on production cluster
     result = tak.exec!("rbd -c /root/prod/ceph.conf --id #{user} --pool #{userPool} map #{argRBDName} -k /etc/ceph/ceph.client.#{user}.keyring")
puts result
     if userRBD.empty? # Do it only the first time when the RBD is created.
        tak.exec!("mkfs.#{argFileSystem} -m0 /dev/rbd/#{userPool}/#{argRBDName}")
        myRBDName = argRBDName
     else              # This case is when RBD is already created earlier.
        myRBDName = userRBD
     end # if userRBD.empty?
     if result[client][:status] == 0
        puts "Mapped RBD #{myRBDName} on Managed Ceph." + "\n"
     end

     tak.loop()
end


# Mount RBDs as File Systems.
puts "Mounting RBDs as File Systems in deployed and production Ceph clusters ..."
Cute::TakTuk.start([client], :user => "root") do |tak|

     result = nil
     # mount RBD from deployed cluster
     result = tak.exec!("umount /dev/rbd/#{argPoolName}/#{argRBDName} /mnt/#{argMntDepl}")
puts result
     tak.exec!("rmdir /mnt/#{argMntDepl}")
     tak.exec!("mkdir /mnt/#{argMntDepl}")
     result = tak.exec!("mount /dev/rbd/#{argPoolName}/#{argRBDName} /mnt/#{argMntDepl}")
puts result
     if result[client][:status] == 0
        puts "Mounted RBD as File System on deployed Ceph." + "\n"
     end


     # mount RBD from production cluster
     if userRBD.empty? # Do it only the first time when the RBD is created.
     result = tak.exec!("umount /dev/rbd/#{userPool}/#{argRBDName} /mnt/#{argMntProd}")
puts result
     tak.exec!("rmdir /mnt/#{argMntProd}")
     tak.exec!("mkdir /mnt/#{argMntProd}")
puts "Ceph prod (userPool/argRBDName): #{userPool}/#{argRBDName}" 
     result = tak.exec!("mount /dev/rbd/#{userPool}/#{argRBDName} /mnt/#{argMntProd}")
puts result
     else              # This case is when RBD is already created earlier.
     result = tak.exec!("umount /dev/rbd/#{userPool}/#{userRBD} /mnt/#{argMntProd}")
puts result
     tak.exec!("rmdir /mnt/#{argMntProd}")
     tak.exec!("mkdir /mnt/#{argMntProd}")
puts "Ceph prod (userPool/userRBD): #{userPool}/#{userRBD}" 
     result = tak.exec!("mount /dev/rbd/#{userPool}/#{userRBD} /mnt/#{argMntProd}")
puts result
     end # if userRBD.empty?

     if result[client][:status] == 0
        puts "Mounted RBDs as File System on Managed Ceph." + "\n"
     end

     tak.loop()
end


