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
       chmod +x dss5k/ceph-deploy.rb
       ./dss5k/ceph-deploy.rb

##Detailed Usage
       ceph-deploy.rb [options]
where [options] are:

        -i, --ignore                   Ignore incorrect values
        -s, --site=sitename            Grid 5000 site for Ceph cluster (default: sophia)
        -r, --release=ceph-release     Ceph Release name (default: firefly)
        -c, --cephCluster=<s>          Ceph cluster name (default: ceph)
        -m, --multiOSD                 Multiple OSDs on each node (default: false)
        -n, --numNodes=number          Nodes in Ceph cluster (default: 5)
        -w, --walltime=xx:yy:zz        Wall time for reservation (default: 01:00:00)
        -v, --version                  Print version and exit
        -h, --help                     Show this message


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
Once the Ceph cluster + client are deployed and block devices mapped and mounted, it is possible to copy data (normal files as well as objects) between the deployed Ceph cluster and the production Ceph. This is required during the initial phase of preparing data before the run of experiments. On your Ceph client node, login as root@client-node. Then execute the following commands at shell CLI :
- Create an RBD pool on the production Ceph cluster,

The UI for the cluster is at : https://api.grid5000.fr/sid/storage/ceph/ui/
If required to create an account, follow instructions from Wiki : https://www.grid5000.fr/mediawiki/index.php/Ceph
Login as root@client-node. Then the following commands at shell CLI :


- Create a config file for the production Ceph with the following details. Store it in ~/prod/ directory on your frontend :

        [global]
          mon initial members = ceph0,ceph1,ceph2
          mon host = 172.16.111.30,172.16.111.31,172.16.111.32


- Get your keyring file for Ceph production and store it in local directory. The contents should look similar to the following:

        [client.userid]
          key = AQDgA8RUiPsIFBAAi6bzDP9s4MV0ZivQTy3FRA==


- create and map Block Devices in the production cluster,

        rbd create bar --size 4096 -c ~/prod/ceph.conf --id userid --pool userid_rbd
        rbd map bar -c ~/prod/ceph.conf --id userid --pool userid_rbd


- Format and install a File System on the block device (this may take some time),

        mkfs.ext4 -m0 /dev/rbd/userid_rbd/bar


- Mount the file system on your Ceph client node and use it.

        mkdir /mnt/ceph-prod
        mount /dev/rbd/userid_rbd/bar /mnt/ceph-prod


- At the end of the above operations, there will be 2 subdirectories under /mnt as follows :
        # cd /mnt
        # ls -al /mnt
        drwxr-xr-x  3 root root 4096 Oct 14 17:25 ceph-depl
        drwxr-xr-x  3 root root 4096 Oct 14 17:44 ceph-prod


- It is now possible to copy any file from one subdirectory (on deployed Ceph cluster) to the other subdirectory (on production Ceph cluster) and vice-versa :
        # cp /mnt/ceph-depl/filename /mnt/prod/


##In case of errors
If using the Rados Block Device (RBD) with a different / lower distribution than "jessie" problems may be encountered. In that case, use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

        ceph osd getcrushmap -o /tmp/crush
        crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
        ceph osd setcrushmap -i /tmp/crush.new




