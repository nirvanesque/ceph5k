#!/usr/bin/env ruby
# Copyright (c) 2015-17 Anirvan BASU, INRIA Rennes - Bretagne Atlantique
#
# Licensed under the CeCCIL-B license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.cecill.info/licences/Licence_CeCILL-B_V1-en.html
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
require 'net/http'
require 'uri'
require 'fileutils'
require 'logger'


def readOptions(scriptDir, currentConfigFile, scriptName)
   # Make the temporary files directory (if not created already)
   tempDir = scriptDir + "/.generated"

   unless File.exist?(currentConfigFile)
     configFile = scriptDir + "/config/defaults.yml.example" # example config file
     FileUtils.cp(configFile, currentConfigFile)
   end # unless File.exist?

   # Populate the hash with default parameters from YAML file.
   defaults = begin
     YAML.load(File.open(currentConfigFile))
   rescue ArgumentError => e
     puts "Could not parse YAML: #{e.message}"
   end

   # Version for script
   versionFile = scriptDir + "/version.yml"
   versionNo = begin
     YAML.load(File.open(versionFile))
   rescue ArgumentError => e
     puts "Could not parse YAML: #{e.message}"
   end

   # banner for script
   opts = Trollop::options do
     version "ceph5k #{versionNo} (c) 2015-16 Anirvan BASU, INRIA RBA"
     case scriptName
        when "cephDeploy"
           banner <<-EOS
  cephDeploy is a script for deploying a Ceph cluster on reserved nodes.

  Usage: 
         cephDeploy [options]
  where [options] are:
         EOS

        when "cephClient"
           banner <<-EOS
  cephClient is a script for creating clients to access a deployed Ceph cluster.

  Usage: 
         cephClient [options]
  where [options] are:
         EOS

        when "cephManaged"
           banner <<-EOS
  cephManaged is a script for creating clients to access a Managed Ceph cluster.

  Usage: 
         cephManaged [options]
  where [options] are:
         EOS

        else
           banner <<-EOS
         ceph5k is a toolsuite for deploying Ceph clusters and clients.
         EOS

     end # case scriptName

  opt :ignore, "Ignore incorrect values"
  opt :jobid, "Oarsub ID of the client job", :default => 0
  opt :walltime, "Wall time for reservation", :type => String, :default => defaults["walltime"]

     case scriptName

        when "cephDeploy" # options specific for script cephDeploy
     opt :'job-name', "Name of Grid'5000 job if already created", :type =>    String, :default => defaults["job-name"]
     opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
     opt :cluster, "Grid 5000 cluster in specified site", :type => String, :default => defaults["cluster"]
     opt :env, "G5K environment to be deployed", :type => String, :default => defaults["env"]
     opt :'num-nodes', "Nodes in Ceph cluster", :default => defaults["num-nodes"]

     opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
     opt :'cluster-name', "Ceph cluster name", :type => String, :default => defaults["cluster-name"]
     opt :'multi-osd', "Multiple OSDs on each node", :default => defaults["multi-osd"]
     opt :'file-system', "File System to be formatted on OSDs", :type => String, :default => defaults["file-system"]


        when "cephClient" # options specific for script cephClient
  opt :'job-name', "Grid'5000 job name for dedicated Ceph cluster", :type => String, :default => defaults["job-name"]
  opt :site, "Grid 5000 site where dedicated Ceph cluster is deployed", :type => String, :default => defaults["site"]

  opt :'job-client', "Grid'5000 job name for Ceph clients", :type => String, :default => defaults["job-client"]
  opt :'client-site', "Grid'5000 site for deploying Ceph clients", :type => String, :default => defaults["client-site"]
  opt :'client-cluster', "Grid'5000 cluster for deploying Ceph clients", :type => String, :default => defaults["client-cluster"]
  opt :'num-client', "Number of Ceph client(s)", :default => defaults["num-client"]
  opt :'env-client', "Grid'5000 environment for client", :type => String, :default => defaults["env-client"]
  opt :'file', "File with list of predeployed clients, similar as in kadeploy3", :type => String, :default => ""
  opt :'only-deploy', "Only deploy linux but don't configure Ceph client", :default => defaults["only-deploy"]

  opt :'pool-name', "Pool name on Ceph cluster (userid_ prepended)", :type => String, :default => defaults["client-pool-name"]
  opt :'rbd-name', "RBD name on Ceph pool (userid_ prepended)", :type => String, :default => defaults["client-rbd-name"]
  opt :'rbd-size', "RBD size on Ceph pool", :default => defaults["client-rbd-size"]
  opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
  opt :'file-system', "File System to be formatted on created RBDs", :type => String, :default => defaults["file-system"]
  opt :'mnt-depl', "Mount point for RBD on deployed cluster", :type => String, :default => defaults["mnt-depl"]


        when "cephManaged" # options specific for script cephManaged
  opt :'job-client', "Grid'5000 job name for Ceph clients", :type => String, :default => defaults["job-client"]
  opt :'file', "File with clients list, same option as in kadeploy3", :type => String, :default => ""
  opt :'client-site', "Grid 5000 site for deploying Ceph clients", :type => String, :default => defaults["client-site"]
  opt :'client-cluster', "Grid 5000 cluster for clients", :type => String, :default => defaults["client-cluster"]
  opt :'env-client', "G5K environment for client", :type => String, :default => defaults["env-client"]

  opt :'managed-cluster', "site for managed Ceph cluster: 'rennes' or 'nantes'", :type => String, :default => defaults["managed-cluster"]
  opt :'multi-client', "Multiple clients to access Ceph Managed cluster", :default => defaults["multi-client"]
  opt :'num-client', "Nodes in Ceph Client cluster", :default => defaults["num-client"]
  opt :'no-deployed', "Not using any deployed Ceph cluster", :default => defaults["no-deployed"]

  opt :'pool-name', "Pool name on Ceph cluster (userid_ prepended)", :type => String, :default => defaults["client-pool-name"]
  opt :'rbd-name', "RBD name for Ceph pool (userid_ prepended)", :type => String, :default => defaults["client-rbd-name"]
  opt :'rbd-size', "RBD size on Ceph pool", :default => defaults["client-rbd-size"]
  opt :'file-system', "File System to be formatted on created RBDs", :type => String, :default => defaults["file-system"]
  opt :'rbd-list-file', "YAML file with RBD list. No. of RBDs must be same as no. of clients", :type => String, :default => nil
  opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
  opt :'mnt-prod', "Mount point for RBD on managed cluster", :type => String, :default => defaults["mnt-prod"]


     end # case scriptName

     opt :'conf-file', "Configuration file to be used for deployment", :type => String, :default => currentConfigFile

   end

end # readOptions()



# Class for abstracting simultaneous log writes to both logFile and stdout
class MultiIO
  def initialize(*targets)
     @targets = targets
  end

  def write(*args)
    @targets.each {|t| t.write(*args)}
  end

  def close
    @targets.each(&:close)
  end
end


def logCreate(logDir, scriptName)
# Creates a logFile at logDir/scriptName.log
   logFile = File.open("#{logDir}/#{scriptName}.log", "a+")
   logger = Logger.new MultiIO.new(STDOUT, logFile)

   logger.formatter = proc do |severity, datetime, progname, msg|
     "#{datetime}, #{datetime}: #{scriptName} - #{msg}\n"
   end # logger.formatter = proc do 

   return logger

end # logCreate()



