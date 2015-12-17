# Ceph5k
New version of dfs5k being developed - Ceph (Lustre, Gluster - coming soon)
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
        password: **********
        version: sid
        EOF

## Installation & Execution
The installation consists of the following steps:
- Deploying a Ceph cluster (monitor node, client node, OSD nodes)
- Creating Rados Block Devices (RBD) and installing a File System :

        on the deployed Ceph cluster,
        on the production Ceph cluster.

### Deploying a Ceph cluster
At the CLI on a frontend:
       
        export http_proxy=http://proxy:3128 && export https_proxy=https://proxy:3128
        gem install --user-install ruby-cute trollop
        export PATH=$PATH:$(ruby -e 'puts "#{Gem.user_dir}/bin"')
        rm -rf dss5k
        git clone https://github.com/nirvanesque/dss5k.git
        chmod +x dss5k/*.rb
        cp ~/.ssh/id_rsa ~/public/
        ./dss5k/cephDeploy.rb     # Creates and deploys the Ceph cluster

Note: All default parameters that are necessary for a deployment are stored in the installation subdirectory at:

        ./config/defaults.yml

This is a YAML file for human reading. All parameters are declarative and by name. It can be modified by text editor to customise the Ceph deployment.
 
### Creating RBD and installing a File System
Note: To create an RBD on the Ceph production cluster, it is required first to create your Ceph account and your Ceph pool using the Ceph frontend. 

At the CLI on a frontend:

        chmod +x dss5k/*.sh
        unset http_proxy && unset https_proxy
        ./dss5k/cephClient.sh
        export http_proxy=http://proxy:3128 && export https_proxy=https://proxy:3128
        ./dss5k/cephRBD.rb        # Creates RBD and FS on deployed and production Ceph

At end of successful execution of the script, you will have 2 Ceph clusters - a deployed cluster and a production cluster - mounted as file systems on your Ceph client, as follows:
        /mnt/ceph-depl/
        /mnt/ceph-prod/

##Detailed Usage of Options

Note: Default values of all these options are provided in the YAML file mentioned above. If the options are specified at the command-line, they override the default values in the YAML file.

### Options for: Deploying a Ceph cluster
       cephDeploy.rb [options]
where [options] are:

        -s, --site=<s>           Grid'5000 site for Ceph cluster (default: sophia)
        -g, --g5kCluster=<s>     Grid'5000 cluster in specified site (default: suno)
        -r, --release=<s>        Ceph Release name (default: firefly)
        -e, --env=<s>            G5K environment to be deployed (default: wheezy-x64-nfs)
        -j, --jobName=<s>        Name of Grid'5000 job (default: cephDeploy)
        -c, --cephCluster=<s>    Ceph cluster name (default: ceph)
        -n, --numNodes=<i>       Nodes in Ceph cluster (default: 6)
        -w, --walltime=<s>       Wall time for Ceph cluster deployed (default: 01:00:00)
        -m, --multiOSD           Multiple OSDs on each node
        -f, --fileSystem=<s>     File System to format on OSDs (default: ext4)

Other generic options:

        -v, --version            Print version and exit
        -h, --help               Show this message
        -i, --ignore             Ignore incorrect values

If interested in using the PRy shell interface, type at CLI

        gem install --user-install pry
        cute

And then simply copy & paste the lines of cephDeploy.rb in the PRy shell.

### Options for: Creating RBD and installing a File System
       cephRBD.rb [options]
where [options] are:

        -p, --poolName=<s>       Name of pool to create on Ceph clusters (default: pool)
        -o, --poolSize=<i>       Size of pool to create on Ceph clusters (default: 57600)
        -b, --rbdName=<s>        Name of rbd to create inside Ceph pool (default: image)
        -d, --rbdSize=<i>        Size of rbd to create inside Ceph pool (default: 57600)
        -f, --fileSystem=<s>     File System to format on created RBDs (default: ext4)
        -t, --mntDepl=<s>        Mount point for RBD on deployed cluster (default: ceph-depl)
        -P, --mntProd=<s>        Mount point for RBD on production cluster (default: ceph-prod)
        -v, --version            Print version and exit
        -h, --help               Show this message

Other generic options:

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

        ./dss5k/cephDeploy.rb --numNodes=12    # Deploy Ceph cluster with 10 OSDs

Then run the benchmarking steps as above.


## In case of errors
If using the Rados Block Device (RBD) with a different / lower distribution than "jessie" problems may be encountered. In that case, use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

        ceph osd getcrushmap -o /tmp/crush
        crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
        ceph osd setcrushmap -i /tmp/crush.new




