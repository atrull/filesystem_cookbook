name             'filesystem'
maintainer       'Sous Chefs'
maintainer_email 'help@sous-chefs.org'
description      'Installs/Configures various filesystems'
license          'Apache-2.0'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.12.2'
source_url       'https://github.com/sous-chefs/filesystem'
issues_url       'https://github.com/sous-chefs/filesystem/issues'
chef_version     '>= 12.0' if respond_to?(:chef_version)

%w(redhat centos xenserver ubuntu debian scientific amazon).each do |os|
  supports os
end

depends 'lvm', '>= 1.1'
