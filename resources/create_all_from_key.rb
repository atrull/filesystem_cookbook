#
# Cookbook:: filesystem
# Resource:: create_all_from_key
#
# Copyright:: 2013-2017, Alex Trull
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# We default to creating all filesystems found in the key
unified_mode true

action :create do
  # Our key is the new resource name or if not we go with filesystems
  # The key is a node attribute name
  key = @new_resource.name || 'filesystems'

  # We get our filesystems from the key in node data
  filesystems_to_be_created = node[key] || {}

  # For reach filesystem we want to make, we enter the main creation loop of calling the default filesystem provider.
  filesystems_to_be_created.each_key do |label|
    fs = filesystems_to_be_created[label]

    # We pass all possible options to the custom resource that creates, enables and mounts filesystems.
    filesystem label do
      label fs['label'] if fs['label']
      device fs['device'] if fs['device']
      vg fs['vg'] if fs['vg']
      file fs['file'] if fs['file']
      uuid fs['uuid'] if fs['uuid']
      fstype fs['fstype'] if fs['fstype']
      mkfs_options fs['mkfs_options'] if fs['mkfs_options']
      recipe fs['recipe'] if fs['recipe']
      package fs['package'] if fs['package']
      sparse fs['sparse'] if fs['sparse']
      size fs['size'] if fs['size']
      stripes fs['stripes'] if fs['stripes']
      mirrors fs['mirrors'] if fs['mirrors']
      mount fs['mount'] if fs['mount']
      options fs['options'] if fs['options']
      user fs['user'] if fs['user']
      group fs['group'] if fs['group']
      mode fs['mode'] if fs['mode']
      pass fs['pass'] if fs['pass']
      dump fs['dump'] if fs['dump']
      force fs['force'] if fs['force']
      # We may not want to do the default action
      if fs['mount'] && fs['nomount']
        # We are not mounting the fs, but we do enable its fstab entry.
        action [:create, :enable]
      elsif fs['mount'] && fs['noenable']
        # We we not enable the fs in fstab, but we do mount it.
        action [:create, :mount]
      elsif fs['nomkfs']
        # We don't create - we just mount and enable - like the mount resource would do.
        action [:enable, :mount]
      elsif fs['mount']
        # Default expected behiavour - create, enable and mount
        action [:create, :enable, :mount]
      else
        # Non-default expected behavior if no mountpoint is given : we only create the filesystem, nothing else.
        action [:create]
      end
    end
  end
end
