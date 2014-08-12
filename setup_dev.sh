#!/usr/bin/env bash

# $1 = user to run scripts as
# $2 = (optional) repository for congress YAML files

# stop setup script if any command fails
set -e

if [ "ubuntu" != $1 ]
then
    DEPENDENCIES="mysql-server curl imagemagick libmysql++-dev libpq-dev git libqt4-dev xvfb"
else
    sleep 30
    DEPENDENCIES="mysql-server"
fi

if [ ! -z $2 ]
then
	cd
	host="export CF_DB_HOST=$2"
	su -c "echo $host >> ~/.bash_profile" "$1"
	su -c "echo ""export CF_DB_PORT=3306"" >> ~/.bash_profile" "$1"
	source .bash_profile
fi

su -c "sudo apt-get update; sudo apt-get -y install $DEPENDENCIES" "$1"

cd /vagrant

# Doing this to make sure vagrant doesn't install RVM and Ruby as root; there's probably a cleaner way
if [ "ubuntu" != $1 ]
then
    su -c "curl -sSL https://get.rvm.io | bash -s stable; source /home/$1/.rvm/scripts/rvm; rvm install ruby-2.1.0" "$1"
fi

su -c "source /home/$1/.rvm/scripts/rvm; rvm use ruby-2.1.0;
gem install bundler -v '= 1.5.1'; gem install json -v '1.8.1';
rvm gemset create congress-forms; rvm alias create congress-forms ruby-2.1.0@congress-forms; 
bundle install --path /home/$1/.rvm/gems/ruby-2.1.0@congress-forms/gems/;" "$1"

echo "Setting up PhantomJS..."
cd /home/$1/
curl -Lo phantomjs.tar.bz2 https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-1.9.7-linux-x86_64.tar.bz2
tar -jxvf phantomjs.tar.bz2 > /dev/null

sudo ln -s /home/$1/phantomjs-1.9.7-linux-x86_64/bin/phantomjs /usr/bin/phantomjs
sudo chmod go-w /vagrant

echo -e "\n\nYou're all done!  Now type 'vagrant ssh', cd into /vagrant, and type 'bundle exec rackup' to run!"
