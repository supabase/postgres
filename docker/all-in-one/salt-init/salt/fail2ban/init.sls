---
fail2ban_config:
  file.managed:
    - name: /etc/supervisor/services/fail2ban.conf
    - source: salt://fail2ban/templates/fail2ban.conf.j2
    - makedirs: True
    - user: root
    - group: root
    - mode: 0644
    - dir_mode: 0755
    - template: jinja
    - backup: minion
    - defaults:
        fail2ban_autostart: "true"
{% if salt['environ.get']('FAIL2BAN_DISABLED') == 'true' %}
    - context:
        fail2ban_autostart: "false"
{% elif salt['environ.get']('FAIL2BAN_DISABLED') == 'false' %}
    - context:
        fail2ban_autostart: "true"
{% endif %}
