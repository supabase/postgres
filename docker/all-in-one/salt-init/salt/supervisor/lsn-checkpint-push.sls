---
gotrue_config:
  file.managed:
    - name: /etc/supervisor/base-services/lsn-checkpoint-push.conf
    - source: salt://supervisor/templates/lsn-checkpoint-push.conf.j2
    - makedirs: True
    - user: root
    - group: root
    - mode: 0644
    - dir_mode: 0755
    - template: jinja
    - backup: minion
    - defaults:
        lsn-checkpoint-push_autostart: "false"
{% if salt['environ.get']('PLATFORM_DEPLOYMENT') == 'true' %}
    - context:
        lsn-checkpoint-push_autostart: "true"
{% elif salt['environ.get']('PLATFORM_DEPLOYMENT') == 'false' %}
    - context:
        lsn-checkpoint-push_autostart: "false"
{% endif %}
