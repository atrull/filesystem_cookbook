name             'filesystem'
maintainer       'Sous Chefs'
maintainer_email 'help@sous-chefs.org'
description      'Installs/Configures various filesystems'
license          'Apache-2.0'
version          '3.0.4'
source_url       'https://github.com/sous-chefs/filesystem'
issues_url       'https://github.com/sous-chefs/filesystem/issues'
chef_version     '>= 15.3'

%w(redhat centos xenserver ubuntu debian scientific amazon).each do |os|
  supports os
end

depends 'lvm', '>= 1.1'
