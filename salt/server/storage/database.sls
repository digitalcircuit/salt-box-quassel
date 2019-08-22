# PostgreSQL and database setup

storage.database:
  pkg.installed:
    # Postgres
    - pkgs:
      - postgresql
  service.running:
    - name: postgresql
    # No need to do a full restart
    - reload: True
    - watch:
      - file: storage.database.tune.include
      - file: storage.database.tune.config

# HACK: Get the PostgreSQL configuration directory in advance so compilation doesn't fail.
# salt['postgres.version']() -> 9.5.5, extra .5 is not wanted
# There's probably a better way to do this.
{%- set PG_CONF_DIR = ["/etc/postgresql/", salt['cmd.shell']('apt-cache show postgresql | grep "Depends:" | cut --delimiter="-" --field=2 | head -n 1')]|join %}
# Sometimes 'apt-cache show' returns multiple versions; use 'head -n 1' to only get the
# first line.
# Before, the following was used:
# quassel.database.tune.ID:
# {% for PG_CONF_DIR in salt['file.find']('/etc/postgresql/', type='d', mindepth=1, maxdepth=1) %}
#   file.ACTION...
# {% endfor %}

storage.database.tune.include:
  file.append:
    - name: "{{ PG_CONF_DIR }}/main/postgresql.conf"
    - text:
      - "# Salt: include a common configuration directory to simplify management"
      - "include_dir = 'conf.d'"
storage.database.tune.config:
  file.managed:
    - name: "{{ PG_CONF_DIR }}/main/conf.d/tune.conf"
    - source: salt://files/server/storage/postgresql/postgres-tune.conf
    - template: jinja
    - makedirs: True
