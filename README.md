# dss5k
New version of dfs5k being developed - Ceph (Lustre, Gluster)


At the CLI in a frontend :
export http_proxy=http_proxy=http://proxy:3128 && export https_proxy=https://proxy:3128

gem install --user-install ruby-cute trollop

export PATH=$PATH:$(ruby -e 'puts "#{Gem.user_dir}/bin"')

rm -rf dss5k

git clone https://github.com/nirvanesque/dss5k.git

chmod +x dss5k/ceph-deploy.rb

./dss5k/ceph-deploy.rb

If interested in using the PRy shell interface, type at CLI
cute

And then simply copy & paste the lines of ceph-deploy.rb in the PRy shell.

