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

##Additional information
Once the Ceph cluster + client is deployed, you can create and use Block Devices. On your Ceph client node, do the following :
- create and map Block Devices,

        modprobe rbd
        rbd create foo --size 4096 -k /path/to/ceph.client.admin.keyring
        rbd map foo --name client.admin -k /path/to/ceph.client.admin.keyring

- Format and install a File System on the block device (this may take some time),

        mkfs.ext4 -m0 /dev/rbd/rbd/foo

- Mount the file system on your Ceph client node and use it.

        mkdir /mnt/ceph-block-device
        mount /dev/rbd/rbd/foo /mnt/ceph-block-device
        cd /mnt/ceph-block-device


##In case of errors
If using the Rados Block Device (RBD), use the following commands first to avoid errors while mounting RBDs (this happens in the case of release firefly). 

Login as root@monitor-node. Then the following commands at shell CLI :

       ceph osd getcrushmap -o /tmp/crush
       crushtool -i /tmp/crush --set-chooseleaf_vary_r 0 -o /tmp/crush.new
       ceph osd setcrushmap -i /tmp/crush.new




