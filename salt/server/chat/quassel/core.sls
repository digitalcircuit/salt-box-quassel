# Quassel Core, including PostgreSQL and database setup

include:
  - server.storage.database

server.chat.quassel.core.database:
  pkg.installed:
    # Dependencies for Postgres
    - pkgs:
      - libqt5sql5-psql
  postgres_user.present:
    - encrypted: True
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

# Clean up stable/beta version
server.chat.quassel.core.repo.channel_cleanup:
  pkgrepo.absent:
{% if salt['pillar.get']('versions:quassel:core:beta', False) == True %}
    # Beta requested, disable the non-beta PPA
    - ppa: mamarley/quassel
{% else %}
    # Stable requested, disable the beta PPA
    - ppa: mamarley/quassel-beta
{% endif %}

# Install Quassel itself
server.chat.quassel.core:
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
    # Make sure PPA is set up first
    - require:
      - pkgrepo: server.chat.quassel.core
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

# Apply lockdown policies
{% if salt['pillar.get']('server:chat:quassel:lockdown:strict-networks:enabled', False) == True %}
# ####
# Network lockdown enabled, setup
server.chat.quassel.core.netlockdown.program.vars:
  # Programs
  file.managed:
    - name: /root/salt/quassel/network-user-whitelist-vars.sh
    - source: salt://files/server/chat/quassel/core/network-user-whitelist-vars.sh
    - makedirs: True
    # Apply pillar configuration
    - template: jinja
server.chat.quassel.core.netlockdown.program.script:
  file.managed:
    - name: /root/salt/quassel/network-user-whitelist-configure.sh
    - source: salt://files/server/chat/quassel/core/network-user-whitelist-configure.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
server.chat.quassel.core.netlockdown.service.unit:
  # Unit for startup
  file.managed:
    - name: /etc/systemd/system/network-user-whitelist.service
    - source: salt://files/server/chat/quassel/core/network-user-whitelist.service
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.netlockdown.service.unit
server.chat.quassel.core.netlockdown.service.running:
  # Enable startup
  service.running:
    - name: network-user-whitelist
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
    - name: /etc/systemd/system/network-user-whitelist-refresh.service
    - source: salt://files/server/chat/quassel/core/network-user-whitelist-refresh.service
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.netlockdown.refresh.service.unit
server.chat.quassel.core.netlockdown.refresh.service.running:
  # Enable startup
  service.enabled:
    - name: network-user-whitelist-refresh
    - require:
      - cmd: server.chat.quassel.core.netlockdown.refresh.service.unit
      - service: server.chat.quassel.core.netlockdown.service.running
    - watch:
      - file: server.chat.quassel.core.netlockdown.refresh.service.unit
server.chat.quassel.core.netlockdown.refresh.timer.unit:
  # Unit for periodic refresh
  file.managed:
    - name: /etc/systemd/system/network-user-whitelist-refresh.timer
    - source: salt://files/server/chat/quassel/core/network-user-whitelist-refresh.timer
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.core.netlockdown.refresh.timer.unit
server.chat.quassel.core.netlockdown.refresh.timer.running:
  # Enable periodic refresh
  service.running:
    - name: network-user-whitelist-refresh.timer
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
    - name: network-user-whitelist
    - enable: False
server.chat.quassel.core.netlockdown.cleanup.refresh.timer:
  service.dead:
    - name: network-user-whitelist-refresh.timer
    - enable: False
server.chat.quassel.core.netlockdown.refresh.service.running:
  # Disable startup
  service.disabled:
    - name: network-user-whitelist-refresh
{% endif %}

# --- Migrations ---
# Renaming files to better indicate purpose
# Remove old Let's Encrypt service override script
server.chat.quassel.core.service.specify_certs:
  file.absent:
    - name: /etc/systemd/system/quasselcore.service.d/letsencrypt-server-certificates.conf
