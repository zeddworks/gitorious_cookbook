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

node['rvm']['default_ruby'] = "ree-1.8.7-2011.03"
include_recipe "rvm"
include_recipe "passenger_nginx"
include_recipe "mysql"
include_recipe "memcached"
include_recipe "activemq"
include_recipe "sphinx"
include_recipe "aspell"

gitorious = Chef::EncryptedDataBagItem.load("apps", "gitorious")
smtp = Chef::EncryptedDataBagItem.load("env", "smtp")

rvm_ruby      = node['rvm']['default_ruby']

bin_path      = "/usr/local/rvm/wrappers/#{rvm_ruby}"
g_ruby_bin    = "#{bin_path}/ruby"
g_rake_bin    = "#{bin_path}/rake"
g_bundle_bin  = "#{bin_path}/bundle"
g_gem_bin     = "#{bin_path}/gem"

rvm_wrapper "gitorious" do
  ruby_string rvm_ruby
  binaries    %w{ rake ruby gem bundle }
end

git_user = "git"
git_group = "git"

rails_env = "production"

user git_user do
  comment "git user"
  shell "/bin/bash"
  home "/home/git"
end

directory "/home/git/git-repos" do
  owner git_user
  group git_group
  recursive true
end

url = gitorious["url"]
path = "/srv/rails/#{url}"
current_path = "#{path}/current"

# Gitorious is vendored with Rails 2.3.5 which is not compatible with newer RubyGems
execute "gem --version | grep 1.5.2 || rvm rubygems 1.5.2"

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

package "apg"

gem_package "bundler"

passenger_nginx_vhost url

passenger_nginx_vhost url do
  ssl true
end

mysql_user gitorious["db_user"] do
  host gitorious["db_host"]
  password gitorious["db_password"]
end

mysql_db gitorious["db_name"] do
  owner gitorious["db_user"]
  host gitorious["db_host"]
end

directories = [
                "#{path}/shared/config","#{path}/shared/log",
                "#{path}/shared/system","#{path}/shared/pids",
                "#{path}/shared/config/environments"
              ]
directories.each do |dir|
  directory dir do
    owner git_user
    group git_group
    mode "0755"
    recursive true
  end
end

#cookbook_file "#{path}/shared/config/environments/production.rb" do
#  source "production.rb"
#  owner "git"
#  group "git"
#  mode "0400"
#end

template "#{path}/shared/config/database.yml" do
  source "database.yml.erb"
  owner git_user
  group git_group
  mode "0755"
  variables({
    :db_adapter => gitorious["db_adapter"],
    :db_name => gitorious["db_name"],
    :db_host => gitorious["db_host"],
    :db_user => gitorious["db_user"],
    :db_password => gitorious["db_password"]
  })
end

template "#{path}/shared/config/gitorious.yml" do
  source "gitorious.yml.erb"
  owner git_user
  group git_group
  mode "0755"
  variables({
    :url => gitorious["url"]
  })
end

deploy_revision "#{path}" do
  user git_user
  group git_group
  environment "RAILS_ENV" => rails_env
  repo "git://gitorious.org/gitorious/mainline.git"
  revision "v2.0.0" # or "HEAD" or "TAG_for_1.0" or (subversion) "1234"
  enable_submodules true
  before_migrate do
    cookbook_file "#{release_path}/Gemfile" do
      source "Gemfile"
      owner git_user
      group git_group
      mode "0755"
    end
    cookbook_file "#{release_path}/Gemfile.lock" do
      source "Gemfile.lock"
      owner git_user
      group git_group
      mode "0755"
    end
    cookbook_file "#{release_path}/Rakefile" do
      source "Rakefile"
      owner git_user
      group git_group
      mode "0755"
    end
    ruby_block "broker.yml" do
      block do
        FileUtils.cp "#{release_path}/config/broker.yml.example", "#{path}/shared/config/broker.yml"
      end
    end
    execute "bundle install --deployment --without test" do
      user git_user
      group git_group
      cwd release_path
    end
    execute "bundle package" do
      user git_user
      group git_group
      cwd release_path
    end
#    execute "bundle exec ext install git://github.com/azimux/ax_fix_long_psql_index_names.git" do
#      user git_user
#      group git_group
#      cwd release_path
#    end
  end
  symlink_before_migrate ({
                          "config/database.yml" => "config/database.yml",
                          "config/gitorious.yml" => "config/gitorious.yml",
                          "config/broker.yml" => "config/broker.yml"
                         })
  migrate true
  migration_command "bundle exec rake db:migrate"
  before_symlink do
    execute "bundle exec rake ultrasphinx:configure" do
      user git_user
      group git_group
      cwd release_path
      environment ({'RAILS_ENV' => rails_env})
    end
    execute "bundle exec rake ultrasphinx:index" do
      user git_user
      group git_group
      cwd release_path
      environment ({'RAILS_ENV' => rails_env})
    end
    execute "bundle exec rake ultrasphinx:spelling:build" do
      cwd release_path
      environment ({'RAILS_ENV' => rails_env})
    end
  end
  action :force_deploy # or :rollback
  restart_command "touch tmp/restart.txt"
end

template "/etc/init.d/git-ultrasphinx" do
  source      "git-ultrasphinx.erb"
  owner       "root"
  group       "root"
  mode        "0755"
  variables(
    :rails_env    => rails_env,
    :rake_bin     => g_rake_bin,
    :current_path => current_path
  )
end

execute "make-git-daemon-bundler-compatible" do
  command "sed -i \"1 a require File.dirname(__FILE__) + '/../config/boot'\" #{current_path}/script/git-daemon"
  not_if "grep \"require File.dirname(__FILE__) + '/../config/boot'\" #{current_path}/script/git-daemon"
end

execute "make-git-poller-bundler-compatible" do
  command "sed -i \"2 a require File.dirname(__FILE__) + '/../config/boot'\" #{current_path}/script/poller"
  not_if "grep \"require File.dirname(__FILE__) + '/../config/boot'\" #{current_path}/script/poller"
end

template "/etc/init.d/git-daemon" do
  source      "git-daemon.erb"
  owner       "root"
  group       "root"
  mode        "0755"
  variables(
    :rails_env    => rails_env,
    :g_ruby_bin   => g_ruby_bin,
    :current_path => current_path
  )
end
template "/etc/init.d/git-poller" do
  source      "git-poller.erb"
  owner       "root"
  group       "root"
  mode        "0755"
  variables(
    :rails_env    => rails_env,
    :g_ruby_bin   => g_ruby_bin,
    :current_path => current_path
  )
end
cron "gitorious_ultrasphinx_reindexing" do
  user        git_user
  command     <<-CRON.sub(/^ {4}/, '')
    cd #{current_path} && #{g_rake_bin} RAILS_ENV=#{rails_env} ultrasphinx:index
  CRON
end
service "git-ultrasphinx" do
  action      [ :enable, :start ]
  pattern     "searchd"
  supports    :restart => true, :reload => true, :status => false
end
service "git-daemon" do
  action      [ :enable, :start ]
  supports    :restart => true, :reload => false, :status => false
end
service "git-poller" do
  action      [ :enable, :start ]
  pattern     "poller"
  supports    :restart => true, :reload => true, :status => false
end
execute "create_gitorious_admin_user" do
  cwd         current_path
  user        git_user
  group       git_group
  command     <<-CMD.sub(/^ {4}/, '')
    cat <<_INPUT | RAILS_ENV=#{rails_env} #{g_ruby_bin} script/create_admin
    #{gitorious["admin_email"]}
    #{gitorious["admin_password"]}
    _INPUT
  CMD
  only_if     <<-ONLYIF
    cd #{current_path} && \
    RAILS_ENV=#{rails_env} #{g_ruby_bin} script/runner \
      'User.find_by_is_admin(true) and abort'
  ONLYIF
end
