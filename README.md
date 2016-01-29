# Ceph5k
Ceph5K is a scripts suite for deploying a Ceph DFS on reserved nodes. It deploys a Ceph cluster using the following :
- 1 or more monitors, 
- 1 or more clients (depending on which script is chosen),
- multiple OSDs.

By default, the Ceph cluster itself is deployed using the "wheezy-x64-nfs" distribution of Linux while the Ceph clients use the "jessie-x64-nfs" deployment.

## Preliminaries (for installing Ruby-CUTE)
To simplify the use of Ruby-Cute modules for node reservation and deployment, it is better to create a file with the following information. This is one-time effort. 

At the CLI on a frontend:

        cat > ~/.grid5000_api.yml << EOF
        uri: https://api.grid5000.fr/
        username: user
        version: stable
        EOF

## Installation & Execution
The installation consists of the following steps:
- Deploying a Ceph cluster (monitor node, client node, OSD nodes)
- Creating Rados Block Devices (RBD) and installing a File System :

        on the deployed Ceph cluster,
        on the production Ceph cluster.

### Deploying a Ceph cluster
The deployment of a Ceph cluster is done from any frontend on Grid'5000. At the CLI on a frontend :
       
        gem install --user-install ruby-cute trollop
        rm -rf ceph5k
        git clone https://github.com/nirvanesque/ceph5k.git
        ./ceph5k/cephDeploy.rb     # Creates and deploys the Ceph cluster

Note: To have an easy start, all default parameters that are necessary for a deployment are configured and stored in the installation subdirectory at :

        ./config/defaults.yml

To facilitate easy human reading and editing : This is a YAML file. All parameters are declarative and by name. The file can be modified by text editor to customise the Ceph deployment.
 
### Creating RBD and installing a File System
Given a Ceph cluster (deployed cluster or production cluster), one needs to create pools, RBDs in the cluster(s), subsequently, format a File System (FS) and then mount the FS. 

Note: To create an RBD on the Ceph production cluster, it is required first to create your Ceph account and your Ceph pool using the Ceph frontend. 

At the CLI on a frontend:

        ./ceph5k/cephClient.rb        # Creates RBD & FS on deployed Ceph cluster
        ./ceph5k/cephClient.sh
        ./ceph5k/cephManaged.rb       # Creates RBD & FS on managed Ceph cluster

At the end of successful execution of the scripts, you will have 2 Ceph clusters - a deployed cluster and a managed cluster - mounted as file systems on your Ceph client, as follows:
        /mnt/ceph-depl/
        /mnt/ceph-prod/

Important: To have access from a Ceph client to both deployed and managed Ceph storages, it is essential to follow the above sequence of steps, i.e. first operate on deployed Ceph cluster and then on the managed Ceph cluster.

##Detailed Usage of Options

Note: Default values of all these options are provided in the YAML file mentioned above. If the options are specified at the command-line, they override the default values in the YAML file.

### Options for: Deploying a Ceph cluster
The deployment of a Ceph cluster is done from any frontend on Grid'5000. Usually, this is done using the following command :

        ./ceph5k/cephDeploy.rb [options]

where [options] are:

Grid'5000-specific options :

Following are options related to reserving resources on Grid'5000:

        -d, --def-conf=string                 Default configuration file (default: dssk/config/defaults.yml)
        -j, --jobid=int                       Oarsub ID of the Grid'5000 job
        -o, --job-name=string                 Name of Grid'5000 job if resources already reserved (default: cephDeploy)
        -s, --site=string                     Grid'5000 site for cluster (default: rennes)
        -c, --cluster=string                  Grid'5000 cluster in site (default: paravance)
        -n, --num-nodes=integer               Nodes in Ceph cluster (default: 6)
        -w, --walltime=hour:min:sec           Wall time for deployment (default: 03:00:00)
        -e, --env=string                      Grid'5000 environment to be deployed (default: wheezy-x64-nfs)

Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -r, --release=<s>                  Ceph Release name (default: firefly)
        -p, --ceph-name=<s>                Ceph cluster name (default: ceph)
        -m, --multi-osd, --no-multi-osd    Multiple OSDs on each node (default: true)
        -f, --file-system=<s>              File System to be formatted on OSD disks (default: ext4)

Other generic options :

        -v, --version                      Print version and exit
        -h, --help                         Show this message
        -i, --ignore                       Ignore incorrect values

If interested in using the PRy shell interface, type at CLI

        gem install --user-install pry
        cute

And then simply copy & paste the lines of cephDeploy.rb in the PRy shell.

### Options for: Creating RBD and installing a File System on Ceph clusters
Given a Ceph cluster (deployed cluster or production cluster), one needs to create pools, RBDs in the cluster(s), subsequently, format a File System (FS) and then mount the FS. These tasks are automated on a Grid'5000 frontend using the following command:

        ./ceph5k/rbdDeployed.rb [options]
        ./ceph5k/rbdManaged.rb  [options]

where [options] are:

RBD & Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -d, --def-conf=string                  Default configuration file (default: dssk/config/defaults.yml)
        -p, --pool-name=string                 Name of pool to create on Ceph clusters (default: pool)
        -o, --pool-size=int                    Size of pool in MB, to create on Ceph clusters (default: 57600)
        -b, --rbd-name=string                  Name of RBD to create inside Ceph pool (default: image)
        -d, --rbd-size=int                     Size of RBD in MB, to create inside Ceph pool (default: 57600)
        -f, --file-system=string               File System to format on created RBDs (default: ext4)
        -t, --mnt-depl=string                  Mount point for RBD on deployed cluster (default: ceph-depl)
        -P, --mnt-prod=string                  Mount point for RBD on production cluster (default: ceph-prod)

Other generic options :

        -v, --version            Print version and exit
        -h, --help               Show this message
        -i, --ignore             Ignore incorrect values


### Options for: Creating multiple Ceph clients (RBD + FS) on deployed cluster
Given a Ceph cluster (deployed cluster or production cluster), one needs to create pools, RBDs in the cluster(s), subsequently, format a File System (FS) and then mount the FS. Once can even create multiple Ceph clients each with its own RBD mounted as File System, which can be further used in experimental setup (e.g. Big Data experiments with 'n' nodes, each of which is a Ceph client accessing data chunks in a data storage cluster. These tasks are automated on a Grid'5000 frontend using the following command:

        ./ceph5k/cephClient.rb [options]

where [options] are:

Grid'5000-specific options :

Following are options related to reserving resources on Grid'5000:

        --def-conf=string                      Default configuration file (default: dssk/config/defaults.yml)
        -j, --jobid=int                        Oarsub ID of the client job (default: 0)
        -s, --site=string                      Grid 5000 site for deploying Ceph cluster (default: rennes)
        -c, --cluster=string                   Grid 5000 cluster in specified site (default: paravance)
        -o, --job-name=string                  Grid'5000 job name for deployed Ceph cluster (default: cephDeploy)
        -w, --walltime=hour:min:sec            Wall time for deployment (default: 03:00:00)
        -e, --job-client=string                Grid'5000 job name for Ceph clients (default: cephClient)
        -n, --env-client=string                G5K environment for client (default: jessie-x64-big)
        -u, --num-client=int                   Nodes in Ceph Client cluster (default: 10)

RBD & Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -p, --pool-name=string                 Name of pool to create on Ceph clusters (default: pool)
        -o, --pool-size=int                    Size of pool in MB, to create on Ceph clusters (default: 57600)
        -b, --rbd-name=string                  Name of RBD to create inside Ceph pool (default: image)
        -d, --rbd-size=int                     Size of RBD in MB, to create inside Ceph pool (default: 57600)
        -f, --file-system=string               File System to format on created RBDs (default: ext4)
        -t, --mnt-depl=string                  Mount point for RBD on deployed cluster (default: ceph-depl)
        -P, --mnt-prod=string                  Mount point for RBD on production cluster (default: ceph-prod)
        -r, --release=string                   Ceph Release name (default: firefly)
        -p, --pool-name=string                 Pool name on Ceph cluster (userid_ added) (default: pool)
        -l, --pool-size=int                    Pool size on Ceph cluster
        -b, --rbd-name=string                  RBD name for Ceph pool (userid_ added) (default: image)
        --rbd-size=int                         RBD size on Ceph pool (default: 57600)
        -f, --file-system=string               File System to be formatted on created RBDs (default: ext4)
        -m, --mnt-depl=string                  Mount point for RBD on deployed cluster (default: ceph-depl)
        -t, --client-pool-name=string          Pool name on each Ceph client (userid_ is added) (default: cpool)
        -z, --client-pool-size=int             Pool size for each Ceph client (~ pool-size / num-clients) (default: 5760)
        -a, --client-rbd-name=string           RBD name on each Ceph client (userid_ added) (default: cpool)
        --client-rbd-size=int                  RBD size for each Ceph client (~ pool-size / num-clients) (default: 5760)

Other generic options :

        -v, --version            Print version and exit
        -h, --help               Show this message
        -i, --ignore             Ignore incorrect values


## Copying data from production Ceph cluster to deployed Ceph cluster
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

        ./ceph5k/cephDeploy.rb --numNodes=12    # Deploy Ceph cluster with 10 OSDs

Then run the benchmarking steps as above.


## In case of errors
If using the Rados Block Device (RBD) with a different / lower distribution than "jessie" problems may be encountered. In that case, use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

        ceph osd getcrushmap -o /tmp/crush
        crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
        ceph osd setcrushmap -i /tmp/crush.new




