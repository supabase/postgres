---
/etc/supervisor/services:
  file.directory:
    - user: root
    - group: root
    - dir_mode: 0755
    - file_mode: 0644
    - makedirs: True
    - recurse:
      - user
      - group
      - mode

include:
  - supervisor/gotrue
  - supervisor/fail2ban
  - supervisor/envoykong
  - supervisor/group