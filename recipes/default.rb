#
# Cookbook Name:: gitorious
# Recipe:: default
#
# Copyright 2011, ZeddWorks
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "passenger_nginx"
include_recipe "postgresql"
include_recipe "memcached"

gitorious = Chef::EncryptedDataBagItem.load("apps", "gitorious")
smtp = Chef::EncryptedDataBagItem.load("apps", "smtp")

gitorious_url = gitorious["gitorious_url"]
gitorious_path = "/srv/rails/#{gitorious_url}"

package "imagemagick-dev" do
  package_name value_for_platform(
    ["ubuntu", "debian"] => { "default" => "libmagickwand-dev" },
    ["redhat"] => { "default" => "ImageMagick-devel" }
  )
end

package "libxml2-dev" do
  package_name value_for_platform(
    ["ubuntu", "debian"] => { "default" => "libxml2-dev" },
    ["redhat"] => { "default" => "libxml2-devel" }
  )
end

package "libxslt-dev" do
  package_name value_for_platform(
    ["ubuntu", "debian"] => { "default" => "libxslt1-dev" },
    ["redhat"] => { "default" => "libxslt-devel" }
  )
end

gem_package "bundler"

passenger_nginx_vhost gitorious_url

postgresql_user "gitorious"do
  password "gitorious"
end

postgresql_db "gitorious_production" do
  owner "gitorious"
end

directories = [
                "#{gitorious_path}/shared/config","#{gitorious_path}/shared/log",
                "#{gitorious_path}/shared/system","#{gitorious_path}/shared/pids",
                "#{gitorious_path}/shared/config/environments"
              ]
directories.each do |dir|
  directory dir do
    owner "nginx"
    group "nginx"
    mode "0755"
    recursive true
  end
end

cookbook_file "#{gitorious_path}/shared/config/environments/production.rb" do
  source "production.rb"
  owner "nginx"
  group "nginx"
  mode "0400"
end

template "#{gitorious_path}/shared/config/database.yml" do
  source "database.yml.erb"
  owner "nginx"
  group "nginx"
  mode "0400"
  variables({
    :db_adapter => gitorious["db_adapter"],
    :db_name => gitorious["db_name"],
    :db_host => gitorious["db_host"],
    :db_user => gitorious["db_user"],
    :db_password => gitorious["db_password"]
  })
end

deploy_revision "#{gitorious_path}" do
  repo "git://gitorious.org/gitorious/mainline.git"
  revision "v2.0.0" # or "HEAD" or "TAG_for_1.0" or (subversion) "1234"
  user "nginx"
  enable_submodules true
  before_migrate do
    cookbook_file "#{release_path}/Gemfile" do
      source "Gemfile"
      owner "nginx"
      group "nginx"
      mode "0400"
    end
    cookbook_file "#{release_path}/Gemfile.lock" do
      source "Gemfile.lock"
      owner "nginx"
      group "nginx"
      mode "0400"
    end
    execute "bundle install --deployment" do
      user "nginx"
      group "nginx"
      cwd release_path
    end
    execute "bundle package" do
      user "nginx"
      group "nginx"
      cwd release_path
    end
  end
  migrate true
  migration_command "bundle exec rake db:migrate"
  symlink_before_migrate ({
                          "config/database.yml" => "config/database.yml",
                          "config/environments/production.rb" => "config/environments/production.rb"
                         })
  environment "RAILS_ENV" => "production"
  action :deploy # or :rollback
  restart_command "touch tmp/restart.txt"
end
