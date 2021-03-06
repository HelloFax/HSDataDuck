#!/usr/bin/env bash

VERSION=$1

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

sudo apt-get install ruby-rspec-core ruby ruby-dev libmysqlclient-dev libpq-dev -y
sudo gem install bundler
sudo bundle install

# rspec will be looking for this
mkdir -p log
touch log/dataduck.log

sudo bundle exec rspec

cat log/dataduck.log

sudo gem build dataduck.gemspec

sudo chmod 666 dataduck-${VERSION}.gem