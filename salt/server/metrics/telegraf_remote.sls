# Telegraf remote statistics reporting

{% if salt['pillar.get']('server:metrics:telegraf:enabled', False) == True %}
# See https://docs.influxdata.com/telegraf/v1.8/introduction/installation/
include:
  - .influxdb_repo

# Install Telegraf
telegraf_remote.pkg:
  pkg.installed:
    - pkgs:
      - telegraf
    - require:
      - sls: server.metrics.influxdb_repo

telegraf_remote.config.disable_default_output:
  file.line:
    - name: /etc/telegraf/telegraf.conf
    - mode: replace
    - content: '# [[outputs.influxdb]]'
    - match: '.{0,2}\[\[outputs\.influxdb\]\]'
    - require:
      - pkg: telegraf_remote.pkg

telegraf_remote.config.agent:
  file.managed:
    - name: /etc/telegraf/telegraf.d/agent.conf
    - source: salt://files/server/metrics/telegraf/conf/agent.conf
    - group: telegraf
    - mode: 640
    - template: jinja
    - require:
      - pkg: telegraf_remote.pkg

telegraf_remote.config.outputs.http:
  file.managed:
    - name: /etc/telegraf/telegraf.d/output-http.conf
    - source: salt://files/server/metrics/telegraf/conf/output-http.conf
    - group: telegraf
    - mode: 640
    - template: jinja
    - require:
      - pkg: telegraf_remote.pkg

telegraf_remote.config.inputs.ping:
{% if salt['pillar.get']('server:metrics:telegraf:inputs:ping:enabled', False) == True %}
  file.managed:
    - name: /etc/telegraf/telegraf.d/input-ping.conf
    - source: salt://files/server/metrics/telegraf/conf/input-ping.conf
    - group: telegraf
    - mode: 640
    - template: jinja
    - require:
      - pkg: telegraf_remote.pkg
{% else %}
  file.absent:
    - name: /etc/telegraf/telegraf.d/input-ping.conf
{% endif %}

telegraf_remote.config.inputs.http_response:
{% if salt['pillar.get']('server:metrics:telegraf:inputs:http_response:enabled', False) == True %}
  file.managed:
    - name: /etc/telegraf/telegraf.d/input-http-response.conf
    - source: salt://files/server/metrics/telegraf/conf/input-http-response.conf
    - group: telegraf
    - mode: 640
    - template: jinja
    - require:
      - pkg: telegraf_remote.pkg
{% else %}
  file.absent:
    - name: /etc/telegraf/telegraf.d/input-http-response.conf
{% endif %}

telegraf_remote.config.inputs.net:
  file.managed:
    - name: /etc/telegraf/telegraf.d/input-net.conf
    - source: salt://files/server/metrics/telegraf/conf/input-net.conf
    - group: telegraf
    - mode: 640
    - template: jinja
    - require:
      - pkg: telegraf_remote.pkg

telegraf_remote.config.inputs.system_overview:
  file.managed:
    - name: /etc/telegraf/telegraf.d/input-system-overview.conf
    - source: salt://files/server/metrics/telegraf/conf/input-system-overview.conf
    - group: telegraf
    - mode: 640
    - template: jinja
    - require:
      - pkg: telegraf_remote.pkg

telegraf_remote.sources.sysstat:
  pkg.installed:
    - pkgs:
      - sysstat
    # Shouldn't need immediately installed
  file.line:
    - name: /etc/default/sysstat
    - mode: replace
    - content: ENABLED="true"
    - match: ENABLED="(true|false)"
    - require:
      - pkg: telegraf_remote.sources.sysstat
  service.running:
    - name: sysstat
    - enable: True
    - require:
      - pkg: telegraf_remote.sources.sysstat
    - watch:
      - file: telegraf_remote.sources.sysstat

# Work around Telegraf package starting on installation, resulting in the systemd service failing
telegraf.reset_failed_service:
  cmd.run:
    - name: systemctl reset-failed telegraf
    - onlyif: systemctl is-failed --quiet telegraf
    - onchanges:
      - pkg: telegraf_remote.pkg
      - file: telegraf_remote.config.disable_default_output
      - file: telegraf_remote.config.agent
      - file: telegraf_remote.config.outputs.http
      - file: telegraf_remote.config.inputs.ping
      - file: telegraf_remote.config.inputs.http_response
      - file: telegraf_remote.config.inputs.net
      - file: telegraf_remote.config.inputs.system_overview

telegraf_remote:
  service.running:
    - name: telegraf
    - enable: True
    # Make sure configuration is in place first, and restart if any of it changes
    - require:
      - pkg: telegraf_remote.pkg
    - watch:
      - file: telegraf_remote.config.disable_default_output
      - file: telegraf_remote.config.agent
      - file: telegraf_remote.config.outputs.http
      - file: telegraf_remote.config.inputs.ping
      - file: telegraf_remote.config.inputs.http_response
      - file: telegraf_remote.config.inputs.net
      - file: telegraf_remote.config.inputs.system_overview

{% else %}
# Disable the Telegraf service if it is running
telegraf_remote:
  service.dead:
    - name: telegraf
    - enable: False

{% endif %}
