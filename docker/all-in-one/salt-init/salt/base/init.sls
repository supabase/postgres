---
{% if salt['environ.get']('PLATFORM_DEPLOYMENT') == 'true' %}
  {% if salt['environ.get']('SWAP_DISABLED') != 'true' %}

# enable swap
create_swapfile:
  cmd.run:
    - name: |
        fallocate -l 1G /mnt/swapfile
        mkswap /mnt/swapfile
    - unless: test -s /mnt/swapfile

swapfile_permissions:
  file.managed:
    - name: /mnt/swapfile
    - user: root
    - group: root
    - mode: 0600
    - replace: False
    - require_in:
      - cmd: create_swapfile

mount_swap:
  mount.swap:
    - name: /mnt/swapfile

  {% endif %}
{% endif %}
