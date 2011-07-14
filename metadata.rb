maintainer       "ZeddWorks"
maintainer_email "smcleod@zeddworks.com"
license          "Apache 2.0"
description      "Installs/Configures gitorious"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.0.1"

%w{ passenger_nginx postgresql memcached activemq }.each do |cb|
      depends cb
end

%w{ debian ubuntu centos redhat fedora }.each do |os|
      supports os
end
