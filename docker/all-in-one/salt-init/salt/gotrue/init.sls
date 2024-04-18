---
gotrue_config:
  file.managed:
    - name: /etc/supervisor/services/gotrue.conf
    - source: salt://gotrue/templates/gotrue.conf.j2
    - makedirs: True
    - user: root
    - group: root
    - mode: 0644
    - dir_mode: 0755
    - template: jinja
    - backup: minion
    - defaults:
        gotrue_autostart: "true"
{% if salt['environ.get']('GOTRUE_DISABLED') == 'true' %}
    - context:
        gotrue_autostart: "false"
{% elif salt['environ.get']('GOTRUE_DISABLED') == 'false' %}
    - context:
        gotrue_autostart: "true"
{% endif %}
