# InfluxDB repo

# See https://docs.influxdata.com/influxdb/v1.6/introduction/installation

# Install InfluxDB repo
influxdb_repo:
  pkgrepo.managed:
    - humanname: InfluxDB stable repository
    - name: deb https://repos.influxdata.com/{{ grains['lsb_distrib_id']|lower }} {{ grains['lsb_distrib_codename'] }} stable
    - comments: InfluxDB stable repository
    - key_url: https://repos.influxdata.com/influxdb.key
  pkg.uptodate:
    # Only update if changes are made
    - onchanges:
      - pkgrepo: influxdb_repo
