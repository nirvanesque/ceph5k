# Ceph5k
Ceph5K is a tool suite for deploying a Ceph cluster on reserved nodes; then subsequently, connecting to Ceph clients as well as operations on deployed Ceph cluster and managed Ceph clusters (e.g. creating pools, RBD, FS, and mounting them on clients). The deployed Ceph cluster has the following :
- single monitor,
- multiple OSDs,
- 1 or more clients accessing the cluster.

By default, the Ceph cluster itself is deployed using the "wheezy-x64-nfs" distribution of Linux while the Ceph clients use the "jessie-x64-nfs" deployment. Other Ceph-compatible distributions can also be used.

Detailed application and Use Cases of the Ceph5k toolsuite is discussed in the following Wiki page: https://www.grid5000.fr/mediawiki/index.php/Moving_Data_around_Grid'5000


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

### Deploying a Ceph cluster - cephDeploy
The deployment of a Ceph cluster is done from any frontend on Grid'5000. At the CLI on a frontend (any sub-folder also):
       
        gem install --user-install ruby-cute trollop
        rm -rf ceph5k
        git clone https://github.com/nirvanesque/ceph5k.git
        ./ceph5k/cephDeploy     # Creates and deploys the Ceph cluster

Note: To have an easy start, all default parameters that are necessary for a deployment are configured and stored in the installation subdirectory at :

        ./config/defaults.yml

It is possible to pass a different config file at the CLI using the following option:
        ./ceph5k/cephDeploy --def-conf your-conf.yml

or 

        ./ceph5k/cephDeploy -d your-conf.yml


To facilitate easy human reading and editing the config file is in YAML format. All parameters are declarative and by name. The file can be modified by a simple text editor to customise the Ceph deployment.

There are multiple options to use at the CLI. Please see the section, "Detailed Usage of Options" for details.
 
### Creating RBD, installing an FS on deployed Ceph cluster - cephClient
Given a deployed Ceph cluster that is up and running, one needs to create pools, RBDs in the cluster, and subsequently format a File System (FS) and then mount the FS. Using the Ceph5k tools, one can even create multiple Ceph clients each with its own RBD mounted as File System, which can be used in experimental setup (e.g. Big Data experiments with 'n' nodes, each of which is a Ceph client accessing data chunks in a data storage cluster). 

These tasks are automated on a Grid'5000 frontend using the following command:

        ./ceph5k/cephClient        # Creates RBD & FS on deployed Ceph and mounts it

At the end of successful execution of the script, you will have 1 or more Ceph clients accessing the deployed Ceph cluster, with pool and RBD mounted as file systems on your Ceph client(s), as follows:

        /mnt/ceph-depl/

Again, there are multiple options to use at the CLI. Please see the section, "Detailed Usage of Options" for details.
 
### Creating RBD and installing a File System on managed Ceph clusters
Given a managed Ceph cluster on Grid'5000 (rennes or nantes sites), one needs to create pools, RBDs in the cluster(s), subsequently, format a File System (FS) and then mount the FS. 

Note: To create an RBD on the managed Ceph cluster, it is required first to create your Ceph account and your Ceph pool using the Ceph web-client: https://api.grid5000.fr/sid/storage/ceph/ui/

At the CLI on a site frontend:

        ./ceph5k/cephClient.sh
        ./ceph5k/cephManaged       # Creates RBD & FS on deployed Ceph and mounts it

At the end of successful execution of the script, you will have a single Ceph client accessing the managed Ceph cluster, with pool and RBD mounted as file systems on your Ceph client, as follows:

        /mnt/ceph-prod/


Important:
- The single Ceph client that accesses both deployed and managed Ceph cluster is the first client in the list of client nodes.
- To have access from a Ceph client to both deployed and managed Ceph clusters, it is essential to follow the above sequence of steps, i.e. first use the tool cephClient on the deployed Ceph cluster, and ONLY then use the tool cephManaged on the managed Ceph cluster.

##Detailed Usage of Options

Note: Default values of all these options are provided in the YAML file mentioned above. If the options are specified at the command-line, they override the default values in the YAML file.

### Options for: cephDeploy - Deploying a Ceph cluster
The deployment of a Ceph cluster is done from any frontend on Grid'5000. Usually, this is done using the following command :

        ./ceph5k/cephDeploy [options]

where [options] are:

- Grid'5000-specific options :

Following are options related to reserving resources on Grid'5000:

        -d, --def-conf=string                 Alternative configuration file (default: ceph5k/config/defaults.yml)
        -j, --jobid=int                       Oarsub ID of the Grid'5000 job
        -o, --job-name=string                 Name of Grid'5000 job if resources already reserved (default: cephDeploy)
        -s, --site=string                     Grid'5000 site for cluster (default: rennes)
        -c, --cluster=string                  Grid'5000 cluster in site (default: paravance)
        -n, --num-nodes=integer               Nodes in Ceph cluster (default: 5)
        -w, --walltime=hour:min:sec           Wall time for deployment (default: 03:00:00)
        -e, --env=string                      Grid'5000 environment to be deployed (default: wheezy-x64-big)

- Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -r, --release=string             Ceph Release name (default: firefly)
        -p, --ceph-name=string           Ceph cluster name (default: ceph)
        -m, --multi-osd, --no-multi-osd  Multiple OSDs on each node (default: true)
        -f, --file-system=string         File System to be formatted on OSD disks (default: ext4)

- Other generic options :

        -v, --version                    Print version and exit
        -h, --help                       Show this message
        -i, --ignore                     Ignore incorrect values

### Options for: cephClient - Creating RBD and installing a File System on Ceph clusters
The cephClient tool offers the following options at the command-line:

        ./ceph5k/cephClient [options]

where [options] are:

- Grid'5000-specific options :

Following are options related to reserving resources on Grid'5000:

        -d, --def-conf=string            Alternative configuration file (default: ceph5k/config/defaults.yml)
        -j, --jobid=int                  Oarsub ID of the Grid'5000 client job
        -o, --job-name=string            Name of Grid'5000 job if resources already reserved (default: cephClient)
        -s, --site=string                Grid'5000 site for clients (default: rennes)
        -c, --cluster=string             Grid'5000 cluster in site (default: paravance)
        -u, --num-client=integer         Number of Ceph client(s) (default: 4)
        -w, --walltime=hour:min:sec      Wall time for deployment (default: 03:00:00)
        -n, --env-client=string          G5K environment for client (default: jessie-x64-big)

- Ceph-specific options :

Following are options related to Ceph cluster characteristics:

        -p, --pool-name=string           Pool name on Ceph cluster (userid_ added) (default: pool)
        -l, --pool-size                  Pool size on Ceph cluster
        -b, --rbd-name=string            RBD name for Ceph pool ("userid_" added) (default: image)
        -d, --rbd-size=int               RBD size on Ceph pool (default: 57600)
        -f, --file-system=string         File System to be formatted on created RBDs (default: ext4)
        -m, --mnt-depl=string            Mount point for RBD on deployed cluster (default: ceph-depl)
        -e, --job-client=string          Grid'5000 job name for Ceph clients (default: cephClient)
        -n, --env-client=string          G5K environment for client (default: jessie-x64-big)
        -u, --num-client=int             Nodes in Ceph Client cluster (default: 4)
        -t, --client-pool-name=string    Pool name on each Ceph client ("userid_" added) (default: cpool)
        -z, --client-pool-size=int       Pool size for each Ceph client (~ pool-size / num-clients) (default: 14400)
        -a, --client-rbd-name=string     RBD name on each Ceph client ("userid_" added) (default: cpool)
        --client-rbd-size=int            RBD size for each Ceph client (~ pool-size / num-clients) (default: 14400)

- Other generic options :

        -v, --version                    Print version and exit
        -h, --help                       Show this message
        -i, --ignore                     Ignore incorrect values


### Options for: cephManaged - Creating RBD and installing a File System on managed Ceph clusters
The cephManaged tool offers the following options at the command-line:

        ./ceph5k/cephManaged [options]

where [options] are:

- Grid'5000-specific options:

Following are options related to reserving resources on Grid'5000:

        -d, --def-conf=string            Alternative configuration file (default: ceph5k/config/defaults.yml)
        -j, --jobid=int                  Oarsub ID of the Grid'5000 client job
        -o, --job-name=string            Name of Grid'5000 job if resources already reserved (default: cephClient)
        -s, --site=string                Grid'5000 site for clients (default: rennes)
        -c, --cluster=string             Grid'5000 cluster in site (default: paravance)
        -u, --num-client=integer         Number of Ceph client(s) (default: 4)
        -w, --walltime=hour:min:sec      Wall time for deployment (default: 03:00:00)
        -n, --env-client=string          G5K environment for client (default: jessie-x64-big)

- RBD & Ceph-specific options:

Following are options related to Ceph cluster characteristics:

        -p, --pool-name=string           Pool name on Ceph cluster (userid_ added) (default: pool)
        -l, --pool-size                  Pool size on Ceph cluster
        -b, --rbd-name=string            RBD name for Ceph pool ("userid_" added) (default: image)
        -d, --rbd-size=int               RBD size on Ceph pool (default: 57600)
        -f, --file-system=string         File System to be formatted on created RBDs (default: ext4)
        -m, --mnt-depl=string            Mount point for RBD on deployed cluster (default: ceph-depl)
        -e, --job-client=string          Grid'5000 job name for Ceph clients (default: cephClient)
        -n, --env-client=string          G5K environment for client (default: jessie-x64-big)
        -n, --num-client=int             Nodes in Ceph Client cluster (default: 4)

- Other generic options:

        -v, --version                    Print version and exit
        -h, --help                       Show this message
        -i, --ignore                     Ignore incorrect values


## Advanced usages of Ceph5k tool suite
### Copying data from managed Ceph cluster to deployed Ceph cluster
Once the Ceph cluster + client are deployed and block devices mapped and mounted, it is possible to copy data as normal files between the deployed Ceph cluster and the production Ceph cluster. This is required during the initial phase of preparing data before the run of experiments. On your Ceph client node, login as root@client-node. 

        # cp /mnt/ceph-prod/<filename> /mnt/ceph-depl/

### Benchmarking your deployed Ceph cluster
It is possible to run some benchmarking tests to check the performance of your deployed Ceph and production Ceph clusters. There are trial datasets available on Grid'5000, on nancy and sophia frontends on /home/abasu/public/ceph-data/. For this purpose, copy the following datasets to your deployed Ceph cluster as follows: 

1. On your Ceph client node, login as root@client-node. 

        # cp nancy:/home/abasu/public/ceph-data/* /mnt/ceph-prod/


2. Try the following command to understand the performance of reading from Ceph production cluster and writing to Ceph deployed cluster. 

        # dd if=/mnt/ceph-prod/wiki-latest-pages.xml.bz2 of=/mnt/ceph-depl/output-file bs=4M oflag=direct

3. You can study the performance in detail by varying the blocksize parameter 'bs' in the above command. Generally, the performance (whatever it may be) stabilises around bs=3M and above. Below bs=512K the performance deteriorates fast.


### Improving performance through higher parallelism (more OSDs)
Another way of improving the performance is by increasing the number of OSDs in the Ceph cluster deployed. This can be done by re-deploying the Ceph cluster as follows. On a front-end, deploy the Ceph cluster with following option:

        ./ceph5k/cephDeploy --numNodes=12    # Deploy Ceph cluster with 10 OSDs

Then run the benchmarking steps as above.


### In case of errors
If using the Rados Block Device (RBD) with a different / lower distribution than "jessie" problems may be encountered. In that case, use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

        ceph osd getcrushmap -o /tmp/crush
        crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
        ceph osd setcrushmap -i /tmp/crush.new

### Using the Ruby PRy shell to follow commands
The scripts in the Ceph5k tool suite are written in Ruby using the Ruby-Cute framework. If interested in using the PRy shell interface, type at CLI:

        gem install --user-install pry
        cute

And then simply copy & paste the lines of any of the tool scripts (cephDeploy, cephClient, cephManaged) in the PRy shell.

