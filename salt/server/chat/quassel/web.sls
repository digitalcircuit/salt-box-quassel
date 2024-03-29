# Quassel Web, which requires NodeJS

{% set qweb_user = salt['pillar.get']('server:chat:quassel:web:username', 'quassel-web') %}
{% set qweb_home_dir = '/srv' | path_join(qweb_user) %}
{% set qweb_work_dir = qweb_home_dir | path_join('quassel_web_root') %}
{% set qweb_repo_parent_dir = qweb_work_dir | path_join('qweb') %}
{% set qweb_repo_dir = qweb_repo_parent_dir | path_join('quassel-webserver') %}

{% set qweb_home_dir_legacy = '/home' | path_join(qweb_user) %}

# Require Quassel and NodeJS to be installed first
include:
  - .core
  - common.nodejs

# Stop the service if running and changes will be made
server.chat.quassel.web.user-basic.stop-for-changes:
  service.dead:
    - name: quassel-web
    - prereq:
      # Stop service before making changes
      - user: server.chat.quassel.web.user-basic

# Set up the user
server.chat.quassel.web.user-basic:
  user.present:
    - name: {{ qweb_user }}
    - fullname: 'Quassel Web server user'
    - system: True
    - createhome: False # Handled below
    - home: {{ qweb_home_dir }}
  file.directory:
    - name: {{ qweb_home_dir }}
    - user: root
    - group: {{ qweb_user }}
    # Don't allow world-wide access to details, including configuration
    # Not required, but neither is global access, either - Salt manages this
    # Also, enforce read-only mode
    - mode: 550
    - makedirs: True

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

# Stop the Quassel Web service if already running.. only if changes will be
# made.  It'll be started back up by the later service check.
server.chat.quassel.web.setup.stop-for-deploy:
  service.dead:
    - name: quassel-web
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
      # Ubuntu 20.04+ - originally used Python 2, now Python 3 works
      - python3
      - build-essential
      # For Salt to download repo
      - python3-git
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
      # Need git
      - pkg: server.chat.quassel.web.dependencies

server.chat.quassel.web.repo.build.npm:
  cmd.run:
    # Run a clean install - https://docs.npmjs.com/cli/v9/commands/npm-ci
    - name: npm clean-install --production
    # Alternative: npm install --production --no-package-lock && npm prune --production --no-package-lock
    # Run install, not updating the package-lock.json file, then prune afterwards
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
    - name: {{ qweb_home_dir }}/quassel_web_root/qweb/quassel-webserver/settings-user.cjs
    - source: salt://files/server/chat/quassel/web/settings-user.cjs
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
    - name: quassel-web
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

# --- Migrations ---
# 2019-11-11: Home directory changed to '/srv' rather than '/home'
# Delete data from the old user
server.chat.quassel.web.migrations.move-user-home:
  file.absent:
    - name: {{ qweb_home_dir_legacy }}

# 2023-11-7: Quassel Web changes from "settings-user.js" to "settings-user.cjs"
server.chat.quassel.web.migrations.delete-old-config:
  file.absent:
    - name: {{ qweb_home_dir }}/quassel_web_root/qweb/quassel-webserver/settings-user.js
