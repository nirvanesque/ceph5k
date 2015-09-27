# dss5k
New version of dfs5k - Ceph (Lustre, Gluster)


At the CLI in a frontend :
export http_proxy=http_proxy=http://proxy:3128 && export https_proxy=https://proxy:3128
gem install --user-install ruby-cute
export PATH=$PATH:$(ruby -e 'puts "#{Gem.user_dir}/bin"')
git clone https://github.com/nirvanesque/dss5k.git
chmod +x dss5k/ceph-deploy.rb
./dss5k/ceph-deploy-rb

If interested in using the PRy shell interface, type at CLI
cute

And then simply copy & paste the lines of ceph-deploy.rb in the PRy shell.

