---
envoy_config:
  file.managed:
    - name: /etc/supervisor/services/envoy.conf
    - source: salt://supervisor/templates/envoy.conf.j2
    - makedirs: True
    - user: root
    - group: root
    - mode: 0644
    - dir_mode: 0755
    - template: jinja
    - backup: minion
    - defaults:
        envoy_autostart: "false"
{% if salt['environ.get']('ENVOY_ENABLED') == 'true' %}
    - context:
        envoy_autostart: "true"
{% elif salt['environ.get']('ENVOY_ENABLED') == 'false' %}
    - context:
        envoy_autostart: "false"
{% endif %}

kong_config:
  file.managed:
    - name: /etc/supervisor/services/kong.conf
    - source: salt://supervisor/templates/kong.conf.j2
    - makedirs: True
    - user: root
    - group: root
    - mode: 0644
    - dir_mode: 0755
    - template: jinja
    - backup: minion
    - defaults:
        kong_autostart: "true"
{% if salt['environ.get']('ENVOY_ENABLED') == 'true' %}
    - context:
        kong_autostart: "false"
{% elif salt['environ.get']('ENVOY_ENABLED') == 'false' %}
    - context:
        kong_autostart: "true"
{% endif %}
