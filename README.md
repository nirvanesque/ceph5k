# Ceph5k
Ceph5K is a tool suite for deploying a Ceph cluster on reserved nodes; then subsequently, connecting to Ceph clients as well as operations on deployed Ceph cluster and managed Ceph clusters (e.g. creating pools, RBD, FS, and mounting them on clients). Using the Ceph5k tools, one can even create multiple Ceph clients each with its own RBD mounted as File System, which can be used in experimental setup (e.g. Big Data experiments with 'n' nodes, each of which is a Ceph client accessing data chunks in a data storage cluster).

Detailed application and Use Cases of the Ceph5k toolsuite is discussed in the following Wiki page: https://www.grid5000.fr/mediawiki/index.php/Moving_Data_around_Grid'5000


## Preliminaries (for installing Ruby-CUTE)
To simplify the use of Ruby-Cute modules for node reservation and deployment, it is better to create a file with the following information. This is a one-time effort. Please replace 'user' with your Grid'5000 userid.

At the CLI on a frontend:

        cat > ~/.grid5000_api.yml << EOF
        uri: https://api.grid5000.fr/
        username: user
        version: stable
        EOF

Get the required gems and download from the repository as follows:

        gem install --user-install trollop
        gem install --user-install ruby-cute
        rm -rf ceph5k
        git clone https://github.com/nirvanesque/ceph5k.git

## Deploying a dedicated Ceph cluster - cephDeploy
This script is for deploying a dedicated Ceph cluster. If you are not deploying a dedicated Ceph cluster, you can skip this section and the following and go directly to the section on Managed Ceph clusters. The deployed Ceph cluster has the following :
- single monitor
- multiple OSDs
The deployment of a Ceph cluster is done from any frontend on Grid'5000. At the CLI on a frontend:
       
        ./ceph5k/cephDeploy --site nancy --cluster grimoire    # Creates and deploys a dedicated Ceph cluster

Note: To have an easy start using Ceph5k, all default parameters necessary for any deployment are configured and stored in the installation subdirectory at :

        ./ceph5k/.generated/config/defaults.yml

To facilitate easy human reading and editing the config file is in YAML format. All parameters are declarative and by name. The file can be modified by a simple text editor to customise the Ceph deployment.

For a detailed list of options at the CLI, please see the section, "Detailed Usage of Options".
 
## Creating RBD +  FS on dedicated Ceph cluster - cephClient
This script is for accessing the dedicated Ceph cluster deployed in the previous section. Given a dedicated Ceph cluster that is currently deployed, one needs to create pools, RBDs in the cluster, and subsequently format a File System (FS) and then mount the FS on each Ceph client. If you are not deploying a dedicated Ceph cluster, you can skip this section and go directly to the section on Managed Ceph clusters. 

These tasks are automated on a Grid'5000 frontend using the following command:

        ./ceph5k/cephManaged --site nancy --num-client 4 \
        --client-site nancy--client-cluster graphite

At the end of successful execution of the above script, you will have 4 Ceph clients on nodes in the 'graphite' cluster in nancy site, accessing the deployed Ceph cluster, with pool and RBD mounted as file systems as follows:

        /mnt/ceph-depl/

For a detailed list of options at the CLI, please see the section, "Detailed Usage of Options".
 
## Creating RBD + FS on managed Ceph clusters - cephManaged
This script is for accessing the managed Ceph clusters. In Grid'5000, object-based persistent storage is provided in the form of managed Ceph clusters in rennes and nantes sites. To use them, a user needs to create pools and RBDs in the cluster(s) ; subsequently, format a File System (FS) and then mount the FS on one or more Ceph clients. 

Note: For using the managed Ceph clusters, it is first required to create your Ceph account and your Ceph pool using the Ceph web-client: https://api.grid5000.fr/sid/storage/ceph/ui/

Subsequently, at the CLI on a frontend:

        # Get managed Ceph keyrings for user from site rennes
        ./ceph5k/cephClient.sh rennes
         
        # Prepare 4 Ceph clients, create RBD on managed Ceph as per names in YAML file
        # Mount an RBD on each Ceph client
        ./ceph5k/cephManaged --site nancy --cluster graphite \
        --multi-client true --num-client 4 --managed-cluster rennes \
        --rbd-list-file ./ceph5k/config/rbd-list.yml.example             

After successful execution of the script, you will have 4 Ceph clients on nodes in the 'graphite' cluster in nancy site, accessing the managed Ceph cluster at rennes, with pool and RBD mounted as file systems as follows:

        /mnt/ceph-prod/


# Advanced usages of Ceph5k tool suite
The following sections give advanced usages of the Ceph5k tool suite and corrections for errors, supplementary tools for Big Data use cases, etc.

## Copying data from managed Ceph cluster to deployed Ceph cluster
Once the Ceph cluster + client are deployed and block devices mapped and mounted, it is possible to copy data as normal files between the deployed Ceph cluster and the production Ceph cluster. This is required during the initial phase of preparing data before the run of experiments. On your Ceph client node, login as root@client-node. 

        # cp /mnt/ceph-prod/<filename> /mnt/ceph-depl/

## Benchmarking your deployed Ceph cluster
It is possible to run some benchmarking tests to check the performance of your deployed Ceph and production Ceph clusters. There are trial datasets available on Grid'5000, on nancy and sophia frontends on /home/abasu/public/ceph-data/. For this purpose, copy the following datasets to your deployed Ceph cluster as follows: 

1. On your Ceph client node, login as root@client-node. 

        # cp nancy:/home/abasu/public/ceph-data/* /mnt/ceph-prod/


2. Try the following command to understand the performance of reading from Ceph production cluster and writing to Ceph deployed cluster. 

        # dd if=/mnt/ceph-prod/wiki-latest-pages.xml.bz2 of=/mnt/ceph-depl/output-file bs=4M oflag=direct

3. You can study the performance in detail by varying the blocksize parameter 'bs' in the above command. Generally, the performance (whatever it may be) stabilises around bs=3M and above. Below bs=512K the performance deteriorates fast.


## Improving performance through higher parallelism (more OSDs)
Another way of improving the performance is by increasing the number of OSDs in the Ceph cluster deployed. This can be done by re-deploying the Ceph cluster as follows. On a front-end, deploy the Ceph cluster with following option:

        ./ceph5k/cephDeploy --numNodes=11    # Deploy Ceph cluster with 10 nodes for OSDs

Then run the benchmarking steps as above.


## In case of errors
If using the Rados Block Device (RBD) with a different / lower distribution than "jessie" problems may be encountered. In that case, use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

        ceph osd getcrushmap -o /tmp/crush
        crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
        ceph osd setcrushmap -i /tmp/crush.new

## Using the Ruby PRy shell to follow commands
The scripts in the Ceph5k tool suite are written in Ruby using the Ruby-Cute framework. If interested in using the PRy shell interface, type at CLI:

        gem install --user-install pry
        cute

And then simply copy & paste the lines of any of the tool scripts (cephDeploy, cephClient, cephManaged) in the PRy shell.

Note: Logs of all script actions can be found in the following folder on your frontend:

        ./ceph5k/.generated/ceph5k.log

All log statements are timestamped as well as annotated with the script which generated the log.


# Big Data automation - Apache Hadoop, Spark, Flink
In the Ceph5k toolsuite, supplementary scripts are provided to use the deployed and managed Ceph clusters and client nodes in Big Data experiments. Currently, the Apache Hadoop, Spark and Flink frameworks can be installed and configured on the Ceph client nodes, in Master-Slaves cluster configuration. For Hadoop, the Ceph backend can be on a deployed Ceph cluster or managed Ceph cluster. For Spark and Flink, this assumes that the deployed Ceph cluster is up and running (cephDeploy executed) AND the Ceph clients are installed to access the deployed Ceph cluster (cephClient executed). 


## Apache Hadoop
Then the script cephHadoop can be executed at any frontend by typing at CLI:

        ./ceph5k/cephHadoop --client-site nancy --hadoop start --hadoop-cluster deployed

The above script installs the full Hadoop 2.x framework (HDFS, YARN & MapReduce) on 'nancy' site with the first client as Master node and the remaining clients as Slaves/Workers. 

Hadoop can also be deployed directly on a managed Ceph cluster by typing at CLI:

        ./ceph5k/cephHadoop --client-site nancy --hadoop start --hadoop-cluster managed

Note: The script assumes that there exist already Ceph 'clients' that access the deployed or managed Ceph cluster. If not, the script will give an error message and exit.

Subsequently, you can launch your Big Data jobs (e.g. WordCount, PageRank, ... ) from the Master node. Please see the Wiki page for further details: https://www.grid5000.fr/mediawiki/index.php/Moving_Data_between_Hadoop_installations_on_Ceph

- Hadoop-specific options:

Following are options related to Hadoop deployment:

        -h, --hadoop=string              start, stop, restart Hadoop cluster (default: start)
        --hadoop-cluster=string          Hadoop on Ceph cluster: deployed OR managed (default: deployed)


## Apache Spark
Then the script cephSpark can be executed at any frontend by typing at CLI:

        ./ceph5k/cephSpark               # Install and run the Spark framework

The above script installs the Apache Spark framework with the first client as Master node and the remaining clients as Slaves/Workers. Subsequently, you can launch your Big Data jobs (e.g. WordCount, PageRank, ... ) from the Master node. Please see the Wiki page for further details: https://www.grid5000.fr/mediawiki/index.php/Moving_Data_around_Grid'5000


## Apache Flink
Then the script cephFlink can be executed at any frontend by typing at CLI:

        ./ceph5k/cephFlink               # Install and run the Flink framework

The above script installs the Apache Flink framework with the first client as Master node and the remaining clients as Slaves/Workers. Subsequently, you can launch your Big Data jobs (e.g. WordCount, PageRank, ... ) from the Master node. Please see the Wiki page for further details: https://www.grid5000.fr/mediawiki/index.php/Moving_Data_around_Grid'5000


# Detailed Usage of Options

Default values of all these options are provided in the YAML file mentioned above. If the options are specified at the command-line, they override the default values in the YAML file. For all scripts in Ceph5k, it is possible to pass at the command-line a different config file using the '--def-conf' option:

        --def-conf=string            Alternative configuration file (default: ceph5k/config/defaults.yml)

- Other generic options that are found in all scripts are:

        -v, --version                    Print version and exit
        -h, --help                       Show this message
        -i, --ignore                     Ignore incorrect values


## Options for: cephDeploy - Deploying a dedicated Ceph cluster
The deployment of a Ceph cluster is done from any frontend on Grid'5000. Usually, this is done using the following command :

        ./ceph5k/cephDeploy [options]

where [options] are:

- Grid'5000-specific options :

Following are options for reserving specific resources on Grid'5000:

        -j, --jobid=int                  Oarsub ID of the Grid'5000 job
        -o, --job-name=string            Name of Grid'5000 job if resources already reserved (default: cephDeploy)
        -s, --site=string                Grid'5000 site for cluster (default: rennes)
        -c, --cluster=string             Grid'5000 cluster in site (default: parasilo)
        -n, --num-nodes=integer          Total nodes in Ceph cluster (default: 5)
        -w, --walltime=hour:min:sec      Wall time for deployment (default: 03:00:00)
        -e, --env=string                 Grid'5000 environment to be deployed (default: wheezy-x64-nfs)

- Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -r, --release=string             Ceph Release name (default: firefly)
        -l, --cluster-name=string        Ceph cluster name (default: ceph)
        -m, --multi-osd, --no-multi-osd  Multiple OSDs on each node (default: true)
        -f, --file-system=string         File System to be formatted on OSD disks (default: ext4)


## Options for: cephClient - Creating RBD + File System on Ceph clusters
The cephClient tool offers the following options at the command-line:

        ./ceph5k/cephClient [options]

where [options] are:

- Grid'5000-specific options :

Following are options related to reserving specific resources on Grid'5000:

        -j, --jobid=int                  Oarsub ID of the Grid'5000 client job
        -s, --site=string                Grid'5000 site where dedicated Ceph cluster is deployed
        -o, --job-name=string            Grid'5000 job name for dedicated Ceph cluster (default: cephDeploy)
        -b, --job-client=string          Grid'5000 job name for Ceph clients (default: cephClient)
        -c, --client-site=string         Grid'5000 site for deploying Ceph clients
        -l, --client-cluster=string      Grid'5000 cluster for deploying Ceph clients
        -e, --env-client=string          Grid'5000 environment for Ceph clients (default: jessie-x64-big)
        -n, --num-client=integer         Number of Ceph client(s) (default: 4)
        -w, --walltime=hour:min:sec      Wall time for Ceph clients reservation (default: 03:00:00)
        -y, --only-deploy                Only deploy linux but don't configure Ceph client
        -f, --file=string                File with list of predeployed clients, similar as in kadeploy3

- Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -a, --release=string             Ceph Release name (default: firefly)
        -p, --pool-name=string           Pool name on Ceph cluster ("userid_" prepended) (default: pool)
        -r, --rbd-name=string            RBD name on Ceph pool ("userid_" prepended) (default: image)
        -d, --rbd-size=int               RBD size on Ceph pool (default: 57600)
        -t, --file-system=string         File System to be formatted on created RBDs (default: ext4)
        -m, --mnt-depl=string            Mount point for RBD on dedicated cluster (default: ceph-depl)


## Options for: cephManaged - Creating RBD + File System on managed Ceph clusters
The cephManaged tool offers the following options at the command-line:

        ./ceph5k/cephManaged [options]

where [options] are:

- Grid'5000-specific options:

Following are options related to reserving resources on Grid'5000:

        -j, --jobid=int                  Oarsub ID of the Grid'5000 client job
        -o, --job-client=string          Grid'5000 job name for Ceph clients (default: cephClient)
        -c, --client-site=string         Grid 5000 site for deploying Ceph clients
        -l, --client-cluster=string      Grid 5000 cluster for clients
        -n, --num-client=integer         Number of Ceph client(s) (default: 4)
        -w, --walltime=hour:min:sec      Wall time for deployment (default: 03:00:00)
        -e, --env-client=string          G5K environment for client (default: jessie-x64-big)
        -f, --file=string                File with list of predeployed clients, similar as in kadeploy3

- RBD & Ceph-specific options:

Following are options related to Ceph cluster characteristics:

        -m, --managed-cluster=string     site for managed Ceph cluster: 'rennes' or 'nantes' (default: rennes)
        -u, --multi-client=bool          Multiple clients to access Ceph Managed cluster (default: true)
        -d, --no-deployed=bool           Not using any dedicated Ceph cluster (default: false = not using dedicated cluster)
        -p, --pool-name=string           Pool name on Ceph cluster ("userid_" prepended) (default: pool)
        -r, --rbd-name=string            RBD name for Ceph pool ("userid_" prepended) (default: image)
        -b, --rbd-size=int               RBD size on Ceph pool (default: 57600)
        -s, --file-system=string         File System to be formatted on created RBDs (default: xfs)
        -t, --rbd-list-file=string       YAML file name with RBD list. No. of RBDs must be same as no. of clients
        -a, --release=string             Ceph Release name (default: firefly)
        --mnt-prod=string                Mount point for RBD on managed cluster (default: ceph-prod)


## Options for: cephHadoop - Deploying a Hadoop cluster on managed or dedicated Ceph cluster
The cephHadoop tool offers the following options at the command-line:

        ./ceph5k/cephHadoop [options]

where [options] are:

- Grid'5000-specific options :

Following are options related to resources on Grid'5000:

        -j, --jobid=int                  Oarsub ID of the Hadoop nodes (Ceph clients) reservation
        -o, --job-client=string          Grid'5000 job name for Hadoop nodes (Ceph clients)
        -s, --client-site=string         Grid'5000 site where Hadoop nodes (Ceph clients) are deployed

- Hadoop-specific options :

Following are options related to Hadoop cluster characteristics:

        -m, --mnt-depl=string            Mount point for RBD on dedicated cluster (default: ceph-depl)
        -n, --mnt-prod=string            Mount point for RBD on managed cluster (default: ceph-prod)
        -h, --hadoop=string              start, stop, restart Hadoop cluster (default: start)
        -a, --hadoop-cluster=string      Hadoop on Ceph cluster: deployed OR managed (default: deployed)
        -d, --hadoop-link                URL link to download Hadoop binary


## Options for: cephSpark - Deploying a Spark cluster on dedicated Ceph cluster
The cephSpark tool offers the following options at the command-line:

        ./ceph5k/cephSpark [options]

where [options] are:

- Grid'5000-specific options :

Following are options related to resources on Grid'5000:

        -j, --jobid=int                  Oarsub ID of the Spark nodes (Ceph clients) reservation
        -o, --job-client=string          Grid'5000 job name for Spark nodes (Ceph clients)
        -s, --site=string                Grid'5000 site where Spark nodes (Ceph clients) are deployed

- Spark-specific options :

Following are options related to Spark cluster characteristics:

        -m, --mnt-depl=string            Mount point for RBD on dedicated cluster (default: ceph-depl)
        -p, --spark-link                 URL link to download Spark binary


## Options for: cephFlink - Deploying a Flink cluster on dedicated Ceph cluster
The cephFlink tool offers the following options at the command-line:

        ./ceph5k/cephFlink [options]

where [options] are:

- Grid'5000-specific options :

Following are options related to resources on Grid'5000:

        -j, --jobid=int                  Oarsub ID of the Flink nodes (Ceph clients) reservation
        -o, --job-client=string          Grid'5000 job name for Flink nodes (Ceph clients)
        -s, --site=string                Grid'5000 site where Flink nodes (Ceph clients) are deployed

- Flink-specific options :

Following are options related to Flink cluster characteristics:

        -m, --mnt-depl=string            Mount point for RBD on dedicated cluster (default: ceph-depl)
        -f, --flink-link                 URL link to download Flink binary


# Licence Information
Copyright (c) 2015-16 Anirvan BASU, INRIA - Rennes Bretagne Atlantique

Licensed under the CeCCIL-B license (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at:   http://www.cecill.info/licences/Licence_CeCILL-B_V1-en.html

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
