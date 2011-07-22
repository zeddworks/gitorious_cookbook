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

node['rvm']['rvmrc'] = {
  'rvm_gemset_create_on_use_flag' => 1,
  'rvm_trust_rvmrcs_flag'         => 1,
}

node['rvm']['default_ruby'] = "ree-1.8.7-2011.03"

include_recipe "rvm"
include_recipe "passenger_nginx"
include_recipe "mysql"
include_recipe "memcached"
include_recipe "activemq"
include_recipe "sphinx"
include_recipe "aspell"

gitorious = Chef::EncryptedDataBagItem.load("apps", "gitorious")
smtp = Chef::EncryptedDataBagItem.load("apps", "smtp")

url = gitorious["url"]
path = "/srv/rails/#{url}"

ruby_string = "#{node['rvm']['default_ruby']}@gitorious"

rvm_gemset ruby_string

rvm_gem "bundler" do
  ruby_string ruby_string
end

rvm_gem "rails" do
  ruby_string ruby_string
#  version "2.3.5"
end

rvm_gem "raspell" do
  ruby_string ruby_string
end

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


passenger_nginx_vhost url

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
    owner "nginx"
    group "nginx"
    mode "0755"
    recursive true
  end
end

#cookbook_file "#{path}/shared/config/environments/production.rb" do
#  source "production.rb"
#  owner "nginx"
#  group "nginx"
#  mode "0400"
#end

cookbook_file "#{path}/shared/config/setup_load_paths.rb" do
  source "setup_load_paths.rb"
  owner "nginx"
  group "nginx"
  mode "0400"
end

template "#{path}/shared/config/database.yml" do
  source "database.yml.erb"
  owner "nginx"
  group "nginx"
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
  owner "nginx"
  group "nginx"
  mode "0755"
  variables({
    :url => gitorious["url"]
  })
end

deploy_revision "#{path}" do
  user "nginx"
  environment "RAILS_ENV" => "production"
  repo "git://gitorious.org/gitorious/mainline.git"
  revision "HEAD" # or "HEAD" or "TAG_for_1.0" or (subversion) "1234"
  enable_submodules true
  before_migrate do
    cookbook_file "#{release_path}/Rakefile" do
      source "Rakefile"
      owner "nginx"
      group "nginx"
      mode "0755"
    end
    ruby_block "broker.yml" do
      block do
        FileUtils.cp "#{release_path}/config/broker.yml.example", "#{path}/shared/config/broker.yml"
      end
    end
    rvm_shell "bundle_install" do
      ruby_string ruby_string
      cwd release_path
      code %{bundle install --without development test}
    end
    rvm_shell "bundle_package" do
      ruby_string ruby_string
      cwd release_path
      code %{bundle package}
    end
    file "#{release_path}/.rvmrc" do
      group "nginx"
      owner "nginx"
      mode "0755"
      content "rvm #{ruby_string}"
    end
#    rvm_shell "trust_rvmrc" do
#      ruby_string ruby_string
#      user "nginx"
#      code %{rvm rvmrc trust #{release_path}}
#    end
#    rvm_shell "trust_rvmrc" do
#      ruby_string ruby_string
#      user "root"
#      code %{rvm rvmrc trust #{release_path}}
#    end
  end
  symlink_before_migrate ({
                          "config/database.yml" => "config/database.yml",
                          "config/gitorious.yml" => "config/gitorious.yml",
                          "config/broker.yml" => "config/broker.yml",
                          "config/setup_load_paths.rb" => "config/setup_load_paths.rb"
                         })
  migrate false
  before_symlink do
    rvm_shell "migrate_rails_database" do
      ruby_string ruby_string
      cwd release_path
      code %{rake db:migrate}
      environment ({'RAILS_ENV' => 'production'})
    end
    rvm_shell "ultrasphinx_bootstrap" do
      ruby_string ruby_string
      cwd release_path
      code %{rake ultrasphinx:bootstrap}
      environment ({'RAILS_ENV' => 'production'})
    end
    rvm_shell "ultrasphinx_spelling" do
      ruby_string ruby_string
      cwd release_path
      code %{rake ultrasphinx:spelling:build}
      environment ({'RAILS_ENV' => 'production'})
    end
  end
  action :force_deploy # or :rollback
  restart_command "touch tmp/restart.txt"
end
