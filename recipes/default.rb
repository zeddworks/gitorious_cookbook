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

url = gitorious["url"]
path = "/srv/rails/#{url}"
current_path = "#{path}/current"

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

git_user = gitorious["user"]
git_group = gitorious["group"]

rails_env = "production"

user git_user do
  comment "git user"
  shell "/bin/bash"
  home "/home/git"
end

directory "/home/git" do
  owner git_user
  group git_group
end

directory "/home/git/git-repos" do
  owner git_user
  group git_group
end

directory "/home/git/tarballs-cache" do
  owner git_user
  group git_group
end

directory "/home/git/tarballs-work" do
  owner git_user
  group git_group
end

directory "/home/git/.ssh" do
  owner git_user
  group git_group
  mode "0700"
end

file "/home/git/.ssh/authorized_keys" do
  owner git_user
  group git_group
  mode "0644"
end

file "/home/git/.bashrc" do
  content "export PATH=$PATH:/srv/rails/#{url}/current/script"
  owner git_user
  group git_group
end

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

passenger_nginx_vhost url do
  internal_locations [["/tarballs-cache","/home/git"]]
end

passenger_nginx_vhost url do
  internal_locations [["/tarballs-cache","/home/git"]]
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

template "#{path}/shared/config/environment.rb" do
  source "environment.rb.erb"
  owner git_user
  group git_group
  mode "0755"
  variables({
    :time_zone => gitorious["time_zone"]
  })
end

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
    :url => url,
    :git_user => git_user,
    :admin_email => gitorious["admin_email"]
  })
end

deploy_revision "#{path}" do
  user git_user
  group git_group
  environment "RAILS_ENV" => rails_env
  repo "git://gitorious.org/gitorious/mainline.git"
  #revision "v2.0.0" # or "HEAD" or "TAG_for_1.0" or (subversion) "1234"
  revision "HEAD"
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
                          "config/environment.rb" => "config/environment.rb",
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
  before_restart do
    cookbook_file "#{release_path}/nginx_sendfile_gitorious.patch" do
      source "nginx_sendfile_gitorious.patch"
      owner git_user
      group git_group
      mode "0755"
    end
    execute "patch -p1 -i nginx_sendfile_gitorious.patch" do
      user git_user
      group git_group
      cwd release_path
    end
  end
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
  command "sed -i \"/require 'rubygems'/a require '#{current_path}/config/boot.rb'\" #{current_path}/script/git-daemon"
  not_if "grep \"require '#{current_path}/config/boot.rb'\" #{current_path}/script/git-daemon"
end

execute "make-poller-bundler-compatible" do
  command "sed -i \"/require 'rubygems'/a require '#{current_path}/config/boot.rb'\" #{current_path}/script/poller"
  not_if "grep \"require '#{current_path}/config/boot.rb'\" #{current_path}/script/poller"
end

execute "make-gitorious-config-bundler-compatible" do
  command "sed -i '/require \"rubygems\"/a require \"bundler/setup\"' #{current_path}/script/gitorious-config"
  not_if "grep 'require \"bundler/setup\"' #{current_path}/script/gitorious-config"
end

execute "activemq-to-use-stomp" do
  command "sed -i 's|name=\"openwire\" uri=\"tcp://0.0.0.0:61616\"|name=\"stomp\" uri=\"stomp://0.0.0.0:61613\"|' /opt/apache-activemq-5.5.0/conf/activemq.xml"
  not_if "grep 'name=\"stomp\" uri=\"stomp://0.0.0.0:61613\"' /opt/apache-activemq-5.5.0/conf/activemq.xml"
  notifies :restart, 'service[activemq]'
end

execute "set-grit-timeout-to-60" do
  command "sed -i -e '24s/self.git_timeout  = 10/self.git_timeout  = 60/' -e '27s/10.seconds/60.seconds/' #{current_path}/vendor/grit/lib/grit/git.rb"
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
