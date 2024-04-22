---
group_config:
  file.managed:
    - name: /etc/supervisor/services/group.conf
    - source: salt://supervisor/templates/group.conf.j2
    - makedirs: True
    - user: root
    - group: root
    - mode: 0660
    - dir_mode: 0770
    - template: jinja
    - backup: minion
    - defaults:
        enabled_proxy: kong
{% if salt['environ.get']('ENVOY_ENABLED') == 'true' %}
    - context:
        enabled_proxy: envoy
{% elif salt['environ.get']('ENVOY_ENABLED') == 'false' %}
    - context:
        enabled_proxy: kong
{% endif %}
