# InfluxDB repo

# See https://docs.influxdata.com/influxdb/v1.6/introduction/installation

# Install InfluxDB repo
influxdb_repo:
  pkgrepo.managed:
    - humanname: InfluxDB stable repository
    - name: deb [signed-by=/etc/apt/keyrings/influxdb-keyring.gpg arch=amd64] https://repos.influxdata.com/{{ grains['lsb_distrib_id']|lower }} {{ grains['lsb_distrib_codename'] }} stable
    - comments: InfluxDB stable repository
    - file: /etc/apt/sources.list.d/influxdb.list
    - key_url: https://repos.influxdata.com/influxdata-archive_compat.key
    - aptkey: False
  pkg.uptodate:
    # Only update if changes are made
    - onchanges:
      - pkgrepo: influxdb_repo
