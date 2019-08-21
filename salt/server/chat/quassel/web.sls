# Quassel Web, which requires NodeJS

{% set qweb_user = salt['pillar.get']('server:chat:quassel:web:username', 'quassel-web') %}
{% set qweb_home_dir = '/home' | path_join(qweb_user) %}
{% set qweb_work_dir = qweb_home_dir | path_join('quassel_web_root') %}
{% set qweb_repo_parent_dir = qweb_work_dir | path_join('qweb') %}
{% set qweb_repo_dir = qweb_repo_parent_dir | path_join('quassel-webserver') %}

# Require Quassel and NodeJS to be installed first
include:
  - .core
  - common.nodejs

# Set up the user
quassel-web.user-basic:
  user.present:
    - name: {{ qweb_user }}
    - fullname: 'Quassel Web server user'
    - system: True
    - createhome: False # Handled below
  file.directory:
    - name: {{ qweb_home_dir }}
    - user: root
    - group: {{ qweb_user }}
    # Don't allow world-wide access to details, including configuration
    # Not required, but neither is global access, either - Salt manages this
    # Also, enforce read-only mode
    - mode: 550

server.chat.quassel.web.user-rw:
  file.directory:
    - user: {{ qweb_user }}
    - group: {{ qweb_user }}
    # Node, NPM, and Quassel Web needs to modify some folders
    - mode: 750
    # Specify all of the needed read-write directories
    - names:
      - {{ qweb_home_dir }}/quassel_web_root
      - {{ qweb_home_dir }}/.npm
      - {{ qweb_home_dir }}/.node-gyp
      # Git configuration
      - {{ qweb_home_dir }}/.config
#      # TODO - are the following needed?
#      - /home/quassel-web/.local/share"
#       > Why does Nano require a different directory?  :(
#      - /home/quassel-web/.nano"
#      - /home/quassel-web/.cache"

# Stop the Quassel Web service if already running.. only if changes will be
# made.  It'll be started back up by the later service check.
server.chat.quassel.web.setup.stop-for-deploy:
  service.dead:
    - name: quassel-web.service
    # Only stop if changes are going to be made
    - prereq:
      # Stop service before making changes
      - git: server.chat.quassel.web.repo

# Install Quassel Web build dependencies
server.chat.quassel.web.dependencies:
  pkg.installed:
    - pkgs:
      # Dependencies for NodeJS package building (e.g. BufferUtil)
      # See https://github.com/magne4000/quassel-webserver/commit/79776c7a5db163273217fb87a76c8c27bfec9a45
      - python
      - build-essential
    - require:
      # Require NodeJS
      - sls: 'common.nodejs'

# Set up Quassel Web's repository
server.chat.quassel.web.repo:
  file.directory:
    - name: {{ qweb_repo_parent_dir }}
    - user: {{ qweb_user }}
    - group: {{ qweb_user }}
    - makedirs: True
    - require:
      # Require install for user to be available
      - file: server.chat.quassel.web.user-rw
  git.latest:
    - name: 'https://github.com/magne4000/quassel-webserver.git'
    - target: {{ qweb_repo_dir }}
    - user: {{ qweb_user }}
    - rev: {{ salt['pillar.get']('server:chat:quassel:versions:web:revision', 'HEAD') }}
    - branch: {{ salt['pillar.get']('server:chat:quassel:versions:web:branch', 'master') }}
    - force_clone: True
    - force_checkout: True
    - force_reset: True
    - require:
      # Need parent folder created
      - file: server.chat.quassel.web.repo

server.chat.quassel.web.repo.build.npm:
  cmd.run:
    # Run install if new, upgrade if existing
    - name: npm install --production && npm prune
    - cwd: {{ qweb_repo_dir }}
    - runas: {{ qweb_user }}
    # Recompile on changes
    - onchanges:
      - git: server.chat.quassel.web.repo
    - require:
      - pkg: server.chat.quassel.web.dependencies

server.chat.quassel.web.config:
  file.managed:
    # Basic configuration
    - name: {{ qweb_home_dir }}/quassel_web_root/qweb/quassel-webserver/settings-user.js
    - source: salt://files/server/chat/quassel/web/settings-user.js
    - user: {{ qweb_user }}
    - group: {{ qweb_user }}
    - template: jinja
    # Set up after repo
    - require:
      - git: server.chat.quassel.web.repo

# Set up the systemd service
server.chat.quassel.web.service.unit:
  file.managed:
    - name: /etc/systemd/system/quassel-web.service
    - source: salt://files/server/chat/quassel/web/quassel-web.service
    - template: jinja
  cmd.run:
    - name: systemctl --system daemon-reload
    - onchanges:
      - file: server.chat.quassel.web.service.unit
    - require_in:
      - service: server.chat.quassel.web.service

server.chat.quassel.web.service:
  service.running:
    - name: quassel-web.service
    - enable: True
    - watch:
      # Restart service on changes, wait for service to be deployed before start
      - file: server.chat.quassel.web.service.unit
      # Restart on configuration changes
      - file: server.chat.quassel.web.config
    - require:
      # Ensure deployed first
      - file: server.chat.quassel.web.config
      - cmd: server.chat.quassel.web.repo.build.npm
