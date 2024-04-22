---
delegated_entry.sh:
  file.managed:
    - name: /usr/local/bin/delegated-entry.sh
    - source: salt://delegated-entry/templates/delegated-entry.sh.j2
    - user: root
    - group: root
    - mode: 0755
    - template: jinja
    - backup: minion