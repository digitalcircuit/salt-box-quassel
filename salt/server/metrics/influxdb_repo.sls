# InfluxDB repo

# See https://docs.influxdata.com/influxdb/v1.6/introduction/installation

{% if grains['cpuarch'] == 'aarch64' -%}
{% set debian_repo_arch = 'arm64' %}
{%- else -%}
{% set debian_repo_arch = 'amd64' %}
{%- endif %}

# Install InfluxDB repo
influxdb_repo:
  pkgrepo.managed:
    - humanname: InfluxDB stable repository
    - name: deb [signed-by=/etc/apt/keyrings/influxdb-keyring.gpg arch={{ debian_repo_arch }}] https://repos.influxdata.com/{{ grains['lsb_distrib_id']|lower }} stable main
    # No more codename
    #- name: deb [signed-by=/etc/apt/keyrings/influxdb-keyring.gpg arch={{ debian_repo_arch }}] https://repos.influxdata.com/{{ grains['lsb_distrib_id']|lower }} {{ grains['lsb_distrib_codename'] }} stable
    - comments: InfluxDB stable repository
    - file: /etc/apt/sources.list.d/influxdb.list
    - key_url: https://repos.influxdata.com/influxdata-archive_compat.key
    - aptkey: False
  pkg.uptodate:
    # Only update if changes are made
    - onchanges:
      - pkgrepo: influxdb_repo
