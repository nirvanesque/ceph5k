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
cephRBD.rb is a script for creating RBD and FS on deployed Ceph and production Ceph.

Usage:
       cephRBD.rb [options]
where [options] are:
EOS

  opt :ignore, "Ignore incorrect values"
  opt :jobName, "Name of Grid'5000 job if already created", :type => String, :default => defaults["jobName"]
  opt :poolName, "Name of pool to create on Ceph clusters", :type => String, :default => defaults["poolName"]
  opt :poolSize, "Size of pool to create on Ceph clusters", :default => defaults["poolSize"]
  opt :rbdName, "Name of rbd to create inside Ceph pool", :type => String, :default => defaults["rbdName"]
  opt :rbdSize, "Size of rbd to create inside Ceph pool", :default => defaults["rbdSize"]
  opt :fileSystem, "File System to be formatted on created RBDs", :type => String, :default => defaults["fileSystem"]
  opt :mntDepl, "Mount point for RBD on deployed cluster", :type => String, :default => defaults["mntDepl"]
  opt :mntProd, "Mount point for RBD on production cluster", :type => String, :default => defaults["mntProd"]
end

# Move CLI arguments into variables. Later change to class attributes.
argJobName = opts[:jobName] # Grid'5000 ndoes reservation job. 
argPoolName = "#{user}_" + opts[:poolName] # Name of pool to create on clusters.
argPoolSize = opts[:poolSize] # Size of pool to create on clusters.
argRBDName = "#{user}_" + opts[:rbdName] # Name of pool to create on clusters.
argRBDSize = opts[:rbdSize] # Size of pool to create on clusters.
argFileSystem = opts[:fileSystem] # File System to be formatted on created RBDs.
argMntDepl = opts[:mntDepl] # Mount point for RBD on deployed cluster.
argMntProd = opts[:mntProd] # Mount point for RBD on production cluster.

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
dataDir = "/tmp"
radosGW = monitor # as of now the machine is the same for monitor & rados GW
monAllNodes = [monitor] # List of all monitors. As of now, only single monitor.


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

