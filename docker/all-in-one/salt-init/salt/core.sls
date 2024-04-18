# load custom data in:
# include:
#   - /tmp/data.yaml

## Examples

# modeprobe_directory:
#   file.directory:
#     - name: /etc/modprobe.d
#     - user: root
#     - group: root
#     - dir_mode: 0755
#     - file_mode: 0644
#     - recurse:
#       - user
#       - group
#       - mode
#
# disable_usb:
#   file.managed:
#     - name: /etc/modprobe.d/blacklist-usbstorage
#     - contents: |
#         # Blacklist USB Storage
#         blacklist usb-storage
#     - require:
#       - file: modeprobe_directory
