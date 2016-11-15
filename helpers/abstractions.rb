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
require "net/http"
require "uri"
require "fileutils"


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
     opt :jobid, "Oarsub ID of the job", :default => 0
     opt :'job-name', "Name of Grid'5000 job if already created", :type =>    String, :default => defaults["job-name"]
     opt :site, "Grid 5000 site for deploying Ceph cluster", :type => String, :default => defaults["site"]
     opt :cluster, "Grid 5000 cluster in specified site", :type => String, :default => defaults["cluster"]
     opt :env, "G5K environment to be deployed", :type => String, :default => defaults["env"]
     opt :'num-nodes', "Nodes in Ceph cluster", :default => defaults["num-nodes"]
     opt :walltime, "Wall time for Ceph cluster deployed", :type => String, :default => defaults["walltime"]

     opt :release, "Ceph Release name", :type => String, :default => defaults["release"]
     opt :'cluster-name', "Ceph cluster name", :type => String, :default => defaults["cluster-name"]
     opt :'multi-osd', "Multiple OSDs on each node", :default => defaults["multi-osd"]
     opt :'file-system', "File System to be formatted on OSDs", :type => String, :default => defaults["file-system"]
     opt :'conf-file', "Configuration file to be used for deployment", :type => String, :default => currentConfigFile

   end

end # readOptions()


