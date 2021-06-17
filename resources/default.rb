#
# Cookbook:: filesystem
# Resource:: default
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

# Our filesystem provider creates filesystems and can also mount/enable them.
default_action :create

# The name property is the label of the filesystem.
property  :label, String

# We have several kinds of device we might be using
property  :device, String
property  :vg, String
property  :file, String
property  :uuid, String

# Creation Options
property  :fstype, String, default: 'ext3'
property  :mkfs_options, String, default: ''
property  :package, String
property  :recipe, String
property  :device_defer, [true, false], default: false

# LVM and filebacked
property  :sparse, [true, false], default: true
property  :size, String
property  :stripes, Integer
property  :mirrors, Integer

# Mounting Options
property  :mount, String
property  :options, String, default: 'defaults'
# Mount directory options
property  :user, String
property  :group, String
property  :mode, String
# Fstab parts
property  :pass, Integer, default: 0, equal_to: [0, 1, 2]
property  :dump, Integer, default: 0, equal_to: [0, 1, 2]

# We may try and force things with mkfs, danger...
property  :force, [true, false], default: false
# An additional thing to ignore existing filesystems - this will actively lose you data on unmounted filesystems if set.
property  :ignore_existing, [true, false], default: false

unified_mode true

action_class do
  include FilesystemMod

  def wait_for_device
    count = 0
    until ::File.exist?(device)
      count += 1
      sleep 0.3
      Chef::Log.debug "waiting for #{device} to exist, try # #{count}"
      if count >= 1000
        # TODO: make this a parameter
        raise Timeout::Error, 'Timeout waiting for device'
      end
    end
  end

  def device
    @device ||= if @new_resource.file
                  @new_resource.device
                elsif @new_resource.vg
                  "/dev/mapper/#{@new_resource.vg}-#{label}"
                elsif @new_resource.uuid
                  "/dev/disk/by-uuid/#{@new_resource.uuid}"
                elsif @new_resource.device
                  @new_resource.device
                else
                  "/dev/mapper/#{label}"
                end
  end

  def label
    @label = @new_resource.label || @new_resource.name
  end

  # create the mount point directory
  # mount points should not have files in them and have no
  # reason to be user writable
  def mount_point(mount_location)
    directory "Mount point for #{mount_location}" do
      path mount_location
      recursive true
      owner 'root'
      group 'root'
      mode '755'
      not_if { Pathname.new(mount_location).mountpoint? }
    end
  end
end

action :create do
  fstype = @new_resource.fstype
  mkfs_options = @new_resource.mkfs_options
  ignore_existing = @new_resource.ignore_existing
  vg = @new_resource.vg
  file = @new_resource.file
  sparse = @new_resource.sparse
  size = @new_resource.size
  stripes = @new_resource.stripes || nil
  mirrors = @new_resource.mirrors ? @new_resource.stripes : nil
  package = @new_resource.package
  force = @new_resource.force

  # In two cases we may need to idempotently create the storage before creating the filesystem on it: LVM and file-backed.
  if (vg || file) && !size.nil?

    # LVM
    # We use the lvm provider directly.
    lvm_logical_volume label do
      action :create
      group vg
      size size
      stripes unless stripes.nil?
      mirrors unless mirrors.nil?
      not_if do
        vg.nil?
      end
    end

    # File-backed
    # We use the local filebackend provider, to which we feed some variables including the loopback device we want.
    backed_device = device
    filesystem_filebacked file do
      action :create
      device backed_device
      size size
      sparse sparse
      not_if do
        file.nil?
      end
    end
  elsif new_resource.device_defer && !::File.exist?(device) && !FilesystemMod::NET_FS_TYPES.include?(fstype)
    return
  end

  wait_for_device unless ::File.exist?(device) || netfs?(fstype)

  # We only try and create a filesystem if the device exists and is unmounted
  unless mounted?(device)

    # Install the filesystem's default package and recipes as configured in default attributes.
    fs_tools = node['filesystem_tools'].fetch(fstype, nil)

    if fs_tools && fs_tools.fetch('package', false)
      packages = fs_tools['package'].split(',')
      packages.each { |default_package| package default_package.to_s }
    end
    if package
      packages = @new_resource.package.split(',')
      packages.each { |keyed_package| package keyed_package.to_s }
    end

    Chef::Log.info "filesystem #{label} creating #{fstype} on #{device}"

    # Install the filesystem's default package and recipes as configured in default attributes.
    mkfs_force_options = node['filesystem_tools'].fetch(fstype, nil)
    # One day Chef will support calling dynamic include_recipe from custom resources but until then - see https://tickets.opscode.com/browse/CHEF-611
    # (fs_tools['recipe'].split(',') || []).each {|default_recipe| include_recipe #{default_recipe}"}
    if mkfs_force_options && mkfs_force_options.fetch('forceopt', false)
      # if force is true, we set the force option. If it isn't set it remains empty.
      force_option = force ? mkfs_force_options['forceopt'] : ''
    end

    # Check to see if the existing file system is mountable
    generic_check_cmd = "mkdir -p /tmp/filesystemchecks/#{label}; mount #{device} /tmp/filesystemchecks/#{label} && umount /tmp/filesystemchecks/#{label}"
    generic_check = shell_out(generic_check_cmd)

    # We form our mkfs command
    mkfs_cmd = "mkfs -t #{fstype} #{force_option} #{mkfs_options} -L #{label} #{device}"

    if force
      # force rebuilt requires both force and ignore_existing to be set
      return if generic_check.exitstatus == 0 && !ignore_existing
    else
      # Don't remake the file system if it already exists
      return if generic_check.exitstatus == 0
      # Remake only if the right mkfs exists
      return if !shell_out("which mkfs.#{fstype}").exitstatus == 0
    end
    # We create the filesystem, but only if the device does not already contain a mountable filesystem, and we have the tools.
    converge_by("Mkfs type #{fstype} #{label} #{device}") do
      shell_out!(mkfs_cmd)
    end

  end
end

# If we're enabling, we create the fstab entry.
action :enable do
  mount = @new_resource.mount
  fstype = @new_resource.fstype
  pass = @new_resource.pass
  dump = @new_resource.dump
  options = @new_resource.options
  file = @new_resource.file

  if mount

    mount_point(mount)

    # Substitute the device with the file when in loopback mode.
    # This should allow the mount to come back up on reboot.
    device_or_file = device
    if file && device.start_with?('/dev/loop')
      device_or_file = file
      options = [options, "loop=#{device}"].compact.join(',')
    end

    return if new_resource.device_defer && !::File.exist?(device) && !FilesystemMod::NET_FS_TYPES.include?(fstype)

    # Update fstab using the chef mount resource
    mount mount do
      action :enable
      device device_or_file
      pass pass
      dump dump
      fstype fstype
      options options
    end

  end
end

# If we're mounting, we mount.
action :mount do
  mount = @new_resource.mount
  fstype = @new_resource.fstype
  user = @new_resource.user
  group = @new_resource.group
  options = @new_resource.options

  if mount

    mount_point(mount)

    return if new_resource.device_defer && !::File.exist?(device) && !FilesystemMod::NET_FS_TYPES.include?(fstype)

    # Mount using the chef resource
    mnt_device = device
    mount mount do
      device mnt_device
      fstype fstype
      options options
      action :mount
      # Pathname.new(mount).mountpoint? would be a better check but might
      # cause different behavior
      not_if "mount | grep #{device}\" \" | grep #{mount}\" \""
    end

    # set directory attributes within the mounted file system
    # assume root has access to the mounted file system
    # do not change directory settings for NETWORK mounted file systems
    # NFS4 file systems in particular should not allow root access
    unless FilesystemMod::NET_FS_TYPES.include?(fstype)
      directory mount do
        path mount
        recursive true
        owner user
        group group
        mode mode
        only_if { Pathname.new(mount).mountpoint? }
      end
    end
  end
end

action :freeze do
  mount = @new_resource.mount
  raise 'mount not specified' if mount.nil?

  unless filesystem_frozen?(mount)
    converge_by("Freeze #{mount}") do
      shell_out!("fsfreeze --freeze #{mount}")
    end
  end
end

action :unfreeze do
  mount = @new_resource.mount
  raise 'mount not specified' if mount.nil?

  if filesystem_frozen?(mount)
    converge_by("Unfreeze #{mount}") do
      shell_out!("fsfreeze --unfreeze #{mount}")
    end
  end
end
