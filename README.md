# dss5k
New version of dfs5k being developed - Ceph (Lustre, Gluster - coming soon)
ceph-deploy.rb is a script for deploying a Ceph DFS on reserved nodes. It deploys a Ceph cluster using the following :
- 1 or more monitors, 
- 1 or more clients (depending on which script is chosen),
- multiple OSDs.

The Ceph cluster itself is deployed using the "wheezy-x64-nfs" distribution of Linux while the Ceph clients use the "jessie-x64-nfs" deployment.

## Installation & Execution
At the CLI in a frontend:

       
        export http_proxy=http://proxy:3128 && export https_proxy=https://proxy:3128
        gem install --user-install ruby-cute trollop
        export PATH=$PATH:$(ruby -e 'puts "#{Gem.user_dir}/bin"')
        rm -rf dss5k
        git clone https://github.com/nirvanesque/dss5k.git
        chmod +x dss5k/*.rb
        chmod +x dss5k/*.sh
        ./dss5k/cephClient.sh
        ./dss5k/cephDeploy.rb     # Creates & deploys the Ceph cluster

At end of successful execution of the script, you will have 2 Ceph clusters - a deployed cluster and a production cluster - mounted as file systems on your Ceph client, as follows:
        /mnt/ceph-depl/
        /mnt/ceph-prod/

To try them out you can type a benchmarking command as follows:
        dd if=/dev/zero bs=1M | dd of=/mnt/ceph-prod/temp bs=1M

##Detailed Usage
       ceph-deploy.rb [options]
where [options] are:

        -i, --ignore             Ignore incorrect values
        -s, --site=<s>           Grid'5000 site for Ceph cluster (default: sophia)
        -g, --g5kCluster=<s>     Grid'5000 cluster in specified site (default: suno)
        -r, --release=<s>        Ceph Release name (default: firefly)
        -e, --env=<s>            G5K environment to be deployed (default: wheezy-x64-nfs)
        -j, --jobName=<s>        Name of Grid'5000 job (default: cephDeploy)
        -c, --cephCluster=<s>    Ceph cluster name (default: ceph)
        -n, --numNodes=<i>       Nodes in Ceph cluster (default: 6)
        -w, --walltime=<s>       Wall time for Ceph cluster deployed (default: 01:00:00)
        -m, --multiOSD           Multiple OSDs on each node
        -p, --poolName=<s>       Name of pool to create on Ceph clusters (default: pool)
        -o, --poolSize=<i>       Size of pool to create on Ceph clusters (default: 57600)
        -b, --rbdName=<s>        Name of rbd to create inside Ceph pool (default: image)
        -d, --rbdSize=<i>        Size of rbd to create inside Ceph pool (default: 57600)
        -f, --fileSystem=<s>     File System to be format on created RBDs (default: ext4)
        -t, --mntDepl=<s>        Mount point for RBD on deployed cluster (default: ceph-depl)
        -P, --mntProd=<s>        Mount point for RBD on production cluster (default: ceph-prod)
        -v, --version            Print version and exit
        -h, --help               Show this message

If interested in using the PRy shell interface, type at CLI

        gem install --user-install pry
        cute

And then simply copy & paste the lines of ceph-deploy.rb in the PRy shell.

##Configuring and mounting a Rados Block Device
Once the Ceph cluster + client is deployed, you can create and use Block Devices. On your Ceph client node, login as root@client-node. Then execute the following commands at shell CLI :

- create and map Block Devices,

        modprobe rbd
        rbd create foo --size 4096 -k /path/to/ceph.client.admin.keyring
        rbd map foo --name client.admin -k /path/to/ceph.client.admin.keyring

- Format and install a File System on the block device (this may take some time),

        mkfs.ext4 -m0 /dev/rbd/rbd/foo

- Mount the file system on your Ceph client node and use it.

        mkdir /mnt/ceph-depl
        mount /dev/rbd/rbd/foo /mnt/ceph-depl
        cd /mnt/ceph-block-device


##Copying data from production Ceph cluster to deployed Ceph cluster
Once the Ceph cluster + client are deployed and block devices mapped and mounted, it is possible to copy data as normal files between the deployed Ceph cluster and the production Ceph cluster. This is required during the initial phase of preparing data before the run of experiments. On your Ceph client node, login as root@client-node. 

        # cp /mnt/ceph-prod/filename /mnt/ceph-depl/


##In case of errors
If using the Rados Block Device (RBD) with a different / lower distribution than "jessie" problems may be encountered. In that case, use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

        ceph osd getcrushmap -o /tmp/crush
        crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
        ceph osd setcrushmap -i /tmp/crush.new




