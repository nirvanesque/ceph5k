# dss5k
New version of dfs5k being developed - Ceph (Lustre, Gluster - coming soon)
ceph-deploy.rb is a script for deploying a Ceph DFS on reserved nodes.


At the CLI in a frontend :
export http_proxy=http_proxy=http://proxy:3128 && export https_proxy=https://proxy:3128

gem install --user-install ruby-cute trollop

export PATH=$PATH:$(ruby -e 'puts "#{Gem.user_dir}/bin"')

rm -rf dss5k

git clone https://github.com/nirvanesque/dss5k.git

chmod +x dss5k/ceph-deploy.rb

./dss5k/ceph-deploy.rb

Detailed Usage:
       ceph-deploy.rb [options]
where [options] are:
  -i, --ignore          Ignore incorrect values
  -s, --site=<s>        Grid 5000 site for deploying Ceph cluster (default: sophia)
  -r, --release=<s>     Ceph Release name (default: firefly)
  -c, --cluster=<s>     Ceph cluster name (default: ceph)
  -n, --numNodes=<i>    Nodes in Ceph cluster (default: 5)
  -w, --walltime=<s>    Wall time for Ceph cluster deployed (default: 01:00:00)
  -v, --version         Print version and exit
  -h, --help            Show this message


If interested in using the PRy shell interface, type at CLI
cute
And then simply copy & paste the lines of ceph-deploy.rb in the PRy shell.

