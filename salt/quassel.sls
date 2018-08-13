# Quassel Core, including PostgreSQL and database setup

quassel.database:
  pkg.installed:
    # Dependencies for Postgres
    - pkgs:
      - libqt5sql5-psql
      - postgresql
  service.running:
    - name: postgresql
    # No need to do a full restart
    - reload: True
    - watch:
      - file: quassel.database.tune.include
      - file: quassel.database.tune.config
  postgres_user.present:
    - encrypted: True
    - name: '{{ salt['pillar.get']('quassel:database:username', 'quassel') }}'
    - password: '{{ salt['pillar.get']('quassel:database:password') }}'
  postgres_database.present:
    - encoding: UTF8
    - name: '{{ salt['pillar.get']('quassel:database:name', 'quassel') }}'
    # Same as name given in user above
    - owner: '{{ salt['pillar.get']('quassel:database:username', 'quassel') }}'

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

quassel.database.tune.include:
  file.append:
    - name: "{{ PG_CONF_DIR }}/main/postgresql.conf"
    - text:
      - "# Salt: include a common configuration directory to simplify management"
      - "include_dir = 'conf.d'"
quassel.database.tune.config:
  file.managed:
    - name: "{{ PG_CONF_DIR }}/main/conf.d/tune.conf"
    - source: salt://files/quassel/postgres-tune.conf
    - template: jinja
    - makedirs: True

# Manage the systemd state
quassel.service.specify_certs:
  file.managed:
    - name: /etc/systemd/system/quasselcore.service.d/letsencrypt-server-certificates.conf
    - source: salt://files/quassel/letsencrypt-server-certificates.conf
    - makedirs: True

# Set up the port/logging/etc
quassel.service.config:
  file.managed:
    - name: /etc/default/quasselcore
    - source: salt://files/quassel/quasselcore-defaults
    - template: jinja

# Clean up stable/beta version
quassel.repo.channel_cleanup:
  pkgrepo.absent:
{% if salt['pillar.get']('versions:quassel:core:beta', False) == True %}
    # Beta requested, disable the non-beta PPA
    - ppa: mamarley/quassel
{% else %}
    # Stable requested, disable the beta PPA
    - ppa: mamarley/quassel-beta
{% endif %}

# Install Quassel itself
quassel:
  pkgrepo.managed:
{% if salt['pillar.get']('versions:quassel:core:beta', False) == True %}
    # Beta requested
    - ppa: mamarley/quassel-beta
    - comments:
        - 'Quassel beta PPA for Ubuntu'
{% else %}
    # Stable requested
    - ppa: mamarley/quassel
    - comments:
        - 'Quassel stable PPA for Ubuntu'
{% endif %}
  pkg.installed:
# PPA version
    - pkgs:
      - quassel-core
    - refresh: True
# Git version
#    - sources:
#      - quassel-core: salt://files/quassel/quassel-core_git-tested_amd64.deb
  service.running:
    - name: quasselcore
    # No need to do a full restart
    - reload: True
    - watch:
      # Reload when these files are added
      - file: quassel.config.dummy_certs.fullcert
      - file: quassel.config.dummy_certs.privkey
      # Reload when configuration is changed
      - file: quassel.service.specify_certs

# Get Quassel users set up
# Salt doesn't seem to have a way for cmd.script's "unless" clause to be a remote script, too
quassel.configure:
  file.managed:
    - name: /root/salt/quassel/quassel-setup.sh
    - source: salt://files/quassel/quassel-setup.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
  cmd.run:
    # Configure the Quassel core to use the Postgres database
    - name: /root/salt/quassel/quassel-setup.sh configure "{{ salt['pillar.get']('quassel:database:username', 'quassel') }}" "{{ salt['pillar.get']('quassel:database:password') }}" "localhost" "5432" "{{ salt['pillar.get']('quassel:database:name', 'quassel') }}" "{{ salt['pillar.get']('quassel:core:admin:username') }}" "{{ salt['pillar.get']('quassel:core:admin:password') }}"
      # {PSQL user name} {PSQL user password} {PSQL hostname} {PSQL port} {PSQL database name} {Quassel admin user name} {Quassel admin user password}
#    - source: salt://files/quassel/quassel-setup.sh
    # Ignore if storage settings already configured
    - unless: /root/salt/quassel/quassel-setup.sh check

# ---
# Ensure there's some form of SSL certificate in place
# This will get replaced when certbot is set up
# Disable replacing existing files, don't overwrite a potentially-valid cert
# Run after Quassel is installed and config directories are created
quassel.config.dummy_certs.fullcert:
  file.managed:
    - name: /var/lib/quassel/le-fullchain.pem
    - source: salt://files/certbot/dummy_certs/cert.pem
    - replace: False
quassel.config.dummy_certs.privkey:
  file.managed:
    - name: /var/lib/quassel/le-privkey.pem
    - source: salt://files/certbot/dummy_certs/privkey.pem
    - replace: False
# ---
