# Quassel Core, including PostgreSQL and database setup

include:
  - server.storage.database
{% if salt['pillar.get']('common:backup:system:enable', False) == True %}
  # For backup module
  - common.backup.system
{% endif %}

server.chat.quassel.core.database:
  pkg.installed:
    # Dependencies for Postgres
    - pkgs:
      - libqt5sql5-psql
  postgres_user.present:
    - encrypted: scram-sha-256
    - name: '{{ salt['pillar.get']('server:chat:quassel:database:username', 'quassel') }}'
    - password: '{{ salt['pillar.get']('server:chat:quassel:database:password') }}'
    - require:
      - service: storage.database
  postgres_database.present:
    - encoding: UTF8
    - name: '{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}'
    # Same as name given in user above
    - owner: '{{ salt['pillar.get']('server:chat:quassel:database:username', 'quassel') }}'
    - require:
      - service: storage.database

# Set up core connection information
server.chat.quassel.core.service.config.defaults:
  file.managed:
    - name: /etc/default/quasselcore
    - source: salt://files/server/chat/quassel/core/quasselcore-defaults
    - template: jinja

# Manage the systemd state
server.chat.quassel.core.service.config.exec:
  file.managed:
    - name: /etc/systemd/system/quasselcore.service.d/quasselcore-exec-config.conf
    - source: salt://files/server/chat/quassel/core/quasselcore-exec-config.conf
    - makedirs: True
    - template: jinja

# Install Quassel PPA
server.chat.quassel.core.repo:
  pkgrepo.managed:
{% if salt['pillar.get']('server:chat:quassel:versions:core:beta', False) == True %}
    # Beta requested
    - name: deb [signed-by=/etc/apt/keyrings/mamarley-quassel-keyring.gpg arch=amd64] https://ppa.launchpadcontent.net/mamarley/quassel-beta/ubuntu {{ grains['lsb_distrib_codename'] }} main
    #- ppa: mamarley/quassel-beta
    - comments:
        - 'Quassel beta PPA for Ubuntu'
    - aptkey: False
{% else %}
    # Stable requested
    #- ppa: mamarley/quassel
    - name: deb [signed-by=/etc/apt/keyrings/mamarley-quassel-keyring.gpg arch=amd64] https://ppa.launchpadcontent.net/mamarley/quassel/ubuntu {{ grains['lsb_distrib_codename'] }} main
    - comments:
        - 'Quassel stable PPA for Ubuntu'
    - aptkey: False
{% endif %}
    - file: /etc/apt/sources.list.d/mamarley-ubuntu-quassel.list
    # GPG is susceptible to network errors when fetching keys
    #- keyid: A0D47AB4E99FF9F9C0EA949A26F4EF8440618B66
    #- keyserver: keyserver.ubuntu.com
    - key_url: https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xa0d47ab4e99ff9f9c0ea949a26f4ef8440618b66
  pkg.uptodate:
    # Only update if changes are made
    - onchanges:
      - pkgrepo: server.chat.quassel.core.repo
    - require_in:
      - pkg: server.chat.quassel.core

# Install Quassel itself
server.chat.quassel.core:
  pkg.installed:
# PPA version
    - pkgs:
      - quassel-core
    # Make sure PPA is set up first
    - require:
      - pkgrepo: server.chat.quassel.core.repo
# Git version
#    - sources:
#      - quassel-core: salt://files/server/chat/quassel/core/quassel-core_git-tested_amd64.deb
{% if salt['pillar.get']('certbot:enable', False) == True %}
    # Make sure packages/users are present before first cert deploy
    - require_in:
      - cmd: certbot.configure
{% endif %}
  service.running:
    - name: quasselcore
    # No need to do a full restart for certs, but needed for configuration
    # changes.  Just always restart, for simplicity.
    - reload: False
    - require:
      # Require database to be set up
      - postgres_user: server.chat.quassel.core.database
      - postgres_database: server.chat.quassel.core.database
    - watch:
      # Reload when these files are added
      - file: server.chat.quassel.core.config.dummy_certs.fullcert
      - file: server.chat.quassel.core.config.dummy_certs.privkey
      # Reload when configuration is changed
      - file: server.chat.quassel.core.service.config.exec
      - file: server.chat.quassel.core.service.config.defaults
      # Reload when package changes
      - pkg: server.chat.quassel.core

# Set up deploy hook to reload on changes
{% if salt['pillar.get']('certbot:enable', False) == True %}
server.chat.quassel.core.config.certbot:
  file.managed:
    - name: /root/salt/certbot/cert/cert-primary/renewal-hooks-deploy/quassel-reload
    - source: salt://files/server/chat/quassel/core/quassel-reload
    - makedirs: True
    # Mark as executable
    - mode: 755
    - watch_in:
      - cmd: certbot.configure
{% endif %}

# Store configuration information for setting up Quassel
server.chat.quassel.core.configure.vars:
  file.managed:
    - name: /root/salt/quassel/quassel-setup-vars.sh
    - source: salt://files/server/chat/quassel/core/quassel-setup-vars.sh
    - makedirs: True
    - template: jinja

# Get Quassel users set up
# Salt doesn't seem to have a way for cmd.script's "unless" clause to be a remote script, too
server.chat.quassel.core.configure:
  file.managed:
    - name: /root/salt/quassel/quassel-setup.sh
    - source: salt://files/server/chat/quassel/core/quassel-setup.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
  cmd.run:
    # Configure the Quassel core to use the Postgres database
    - name: /root/salt/quassel/quassel-setup.sh configure_from_file "/root/salt/quassel/quassel-setup-vars.sh"
      # configure "{{ salt['pillar.get']('server:chat:quassel:database:username', 'quassel') }}" "{{ salt['pillar.get']('server:chat:quassel:database:password') }}" "localhost" "5432" "{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}" "{{ salt['pillar.get']('server:chat:quassel:core:admin:username') }}" "{{ salt['pillar.get']('server:chat:quassel:core:admin:password') }}"
      # {PSQL user name} {PSQL user password} {PSQL hostname} {PSQL port} {PSQL database name} {Quassel admin user name} {Quassel admin user password}
#    - source: salt://files/server/chat/quassel/core/quassel-setup.sh
    # Ignore if storage settings already configured
    - unless: /root/salt/quassel/quassel-setup.sh check "{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}"
    - require:
      # Require database to be set up
      - postgres_user: server.chat.quassel.core.database
      - postgres_database: server.chat.quassel.core.database
    - watch:
      # Recheck when configuration changes
      - file: server.chat.quassel.core.configure.vars

# ---
# Ensure there's some form of SSL certificate in place
# This will get replaced when certbot is set up
# Disable replacing existing files, don't overwrite a potentially-valid cert
# Run after Quassel is installed and config directories are created
server.chat.quassel.core.config.dummy_certs.fullcert:
  file.managed:
    - name: /var/lib/quassel/le-fullchain.pem
    - source: salt://files/server/certbot/dummy_certs/cert.pem
    - replace: False
    - require:
      - pkg: server.chat.quassel.core
server.chat.quassel.core.config.dummy_certs.privkey:
  file.managed:
    - name: /var/lib/quassel/le-privkey.pem
    - source: salt://files/server/certbot/dummy_certs/privkey.pem
    - replace: False
    - require:
      - pkg: server.chat.quassel.core
# ---

# Backup module
# ####
{% if salt['pillar.get']('common:backup:system:enable', False) == True %}
# Set archive directory
{% set archive_configdir = salt['pillar.get']('common:backup:system:storage:datadir', '/root/salt/backup/system') %}
{% set archive_moduledir = archive_configdir | path_join('scripts.d') %}
server.chat.quassel.core.backupmgr:
  file.managed:
    - name: {{ archive_moduledir }}/quassel-backup
    - source: salt://files/server/chat/quassel/core/quassel-backup
    - makedirs: True
    # Specify database name
    - template: jinja
    - context:
        quassel_db_name: "{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}"
    # Mark as executable
    - mode: 755
    - require:
      - service: server.chat.quassel.core
    - watch_in:
      - cmd: common.backup.system.configure
{% endif %}
# ####

# Apply lockdown policies
{% if salt['pillar.get']('server:chat:quassel:lockdown:strict-networks:enabled', False) == True %}
# ####
# Network lockdown enabled, setup
server.chat.quassel.core.netlockdown.program.vars:
  # Programs
  file.managed:
    - name: /root/salt/quassel/network-user-lockdown-vars.sh
    - source: salt://files/server/chat/quassel/core/network-user-lockdown-vars.sh
    - makedirs: True
    # Apply pillar configuration
    - template: jinja
server.chat.quassel.core.netlockdown.program.script:
  file.managed:
    - name: /root/salt/quassel/network-user-lockdown-configure.sh
    - source: salt://files/server/chat/quassel/core/network-user-lockdown-configure.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
server.chat.quassel.core.netlockdown.service.unit:
  # Unit for startup
  file.managed:
    - name: /etc/systemd/system/network-user-lockdown.service
    - source: salt://files/server/chat/quassel/core/network-user-lockdown.service
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.netlockdown.service.unit
server.chat.quassel.core.netlockdown.service.running:
  # Enable startup
  service.running:
    - name: network-user-lockdown
    - enable: True
    - require:
      - cmd: server.chat.quassel.core.netlockdown.service.unit
    - watch:
      - file: server.chat.quassel.core.netlockdown.program.vars
      - file: server.chat.quassel.core.netlockdown.program.script
      - file: server.chat.quassel.core.netlockdown.service.unit
server.chat.quassel.core.netlockdown.refresh.service.unit:
  # Unit for startup
  file.managed:
    - name: /etc/systemd/system/network-user-lockdown-refresh.service
    - source: salt://files/server/chat/quassel/core/network-user-lockdown-refresh.service
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.netlockdown.refresh.service.unit
server.chat.quassel.core.netlockdown.refresh.service.running:
  # Enable startup
  service.enabled:
    - name: network-user-lockdown-refresh
    - require:
      - cmd: server.chat.quassel.core.netlockdown.refresh.service.unit
      - service: server.chat.quassel.core.netlockdown.service.running
    - watch:
      - file: server.chat.quassel.core.netlockdown.refresh.service.unit
server.chat.quassel.core.netlockdown.refresh.timer.unit:
  # Unit for periodic refresh
  file.managed:
    - name: /etc/systemd/system/network-user-lockdown-refresh.timer
    - source: salt://files/server/chat/quassel/core/network-user-lockdown-refresh.timer
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.netlockdown.refresh.timer.unit
server.chat.quassel.core.netlockdown.refresh.timer.running:
  # Enable periodic refresh
  service.running:
    - name: network-user-lockdown-refresh.timer
    - enable: True
    - require:
      - cmd: server.chat.quassel.core.netlockdown.refresh.timer.unit
    - watch:
      - file: server.chat.quassel.core.netlockdown.refresh.timer.unit
{% else %}
# ####
# Network lockdown disabled, clean up
# This *should* disable the rules
server.chat.quassel.core.netlockdown.cleanup.service:
  service.dead:
    - name: network-user-lockdown
    - enable: False
server.chat.quassel.core.netlockdown.cleanup.refresh.timer:
  service.dead:
    - name: network-user-lockdown-refresh.timer
    - enable: False
server.chat.quassel.core.netlockdown.cleanup.refresh.service.running:
  # Disable startup
  service.disabled:
    - name: network-user-lockdown-refresh
{% endif %}

# --- Migrations ---
# Using more inclusive, meaningful phrasing for restricted IRC network access.
server.chat.quassel.core.migrate-phrasing.netlockdown.cleanup.service:
  service.dead:
    - name: network-user-whitelist
    - enable: False
server.chat.quassel.core.migrate-phrasing.netlockdown.cleanup.refresh.timer:
  service.dead:
    - name: network-user-whitelist-refresh.timer
    - enable: False
server.chat.quassel.core.migrate-phrasing.netlockdown.cleanup.refresh.service.running:
  # Disable startup
  service.disabled:
    - name: network-user-whitelist-refresh
server.chat.quassel.core.migrate-phrasing.netlockdown.program.vars:
  # Programs
  file.absent:
    - name: /root/salt/quassel/network-user-whitelist-vars.sh
server.chat.quassel.core.migrate-phrasing.netlockdown.program.script:
  file.absent:
    - name: /root/salt/quassel/network-user-whitelist-configure.sh
server.chat.quassel.core.migrate-phrasing.netlockdown.service.unit:
  # Unit for startup
  file.absent:
    - name: /etc/systemd/system/network-user-whitelist.service
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.migrate-phrasing.netlockdown.service.unit
server.chat.quassel.core.migrate-phrasing.netlockdown.refresh.service.unit:
  # Unit for startup
  file.absent:
    - name: /etc/systemd/system/network-user-whitelist-refresh.service
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.migrate-phrasing.netlockdown.refresh.service.unit
server.chat.quassel.core.migrate-phrasing.netlockdown.refresh.timer.unit:
  # Unit for periodic refresh
  file.absent:
    - name: /etc/systemd/system/network-user-whitelist-refresh.timer
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.migrate-phrasing.netlockdown.refresh.timer.unit

# Renaming files to better indicate purpose
# Remove old Let's Encrypt service override script
server.chat.quassel.core.service.specify_certs:
  file.absent:
    - name: /etc/systemd/system/quasselcore.service.d/letsencrypt-server-certificates.conf
