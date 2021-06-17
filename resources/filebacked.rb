#
# Cookbook:: filesystem
# Resource:: filebacked
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

# We default to creating the file backed loopback.
default_action :create

# The name property is the file to be created.

property :device, String
property :size, String
property :sparse, [true, false], default: true
unified_mode true

action :create do
  file = @new_resource.name
  size = @new_resource.size
  sparse = @new_resource.sparse
  device = @new_resource.device

  # Idempotent behaviour:

  # Case 1) File found, Loopback found => return loopback.
  # Case 2) File found, Loopback missing => create loopback, return loopback.
  # Case 3) File missing, Loopback missing => create file and loopback, return loopback.

  create_loopback = "losetup #{device} #{file}"

  get_loopback_cmd = "losetup -a | grep #{file} | grep #{device}"

  loopback = shell_out(get_loopback_cmd).stdout.gsub(/: \[.*/, '').strip

  if ::File.exist?(file) && device == loopback
    # Case 1)
    # File and Loopback found - nothing to do.

  elsif ::File.exist?(file) && device != loopback
    # Case 2)
    # File but no loopback - so we make a loopback

    # how is ls file returning 0 different from ::File.exist?(file)
    # if "ls #{file} >/dev/null"
    converge_by("Creating #{device} for #{file}") do
      shell_out!(create_loopback)
    end
    # end

  elsif !size.nil?
    # Case 3)
    # If we have a size, we can create the file..

    # We make sure a directory exists for the file to live in.
    directory ::File.dirname(file) do
      recursive true
    end

    # We pick the file creation method
    file_creation_cmd = if sparse
                          # We default to speedy file creation.
                          "dd bs=1M count=0 seek=#{size} of=\"#{file}\""
                        else
                          # If not sparse we use zeros - this takes much longer.
                          "dd bs=1M count=#{size} if=/dev/zero of=\"#{file}\""
                        end

    # We create the file
    # File should not exist at this point
    # If the file was created, we make a loopback device for the file and return the loopback result.
    converge_by("Creating #{file} and device #{device}") do
      shell_out!(file_creation_cmd)
      shell_out!(create_loopback)
    end

  end
end
