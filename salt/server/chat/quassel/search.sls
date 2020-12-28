# Quassel Search

# Require Quassel to be installed first
# Also require webserver for 'www-manage' user
include:
  - .core
  - server.web.webserver

{% set qsearch_html_dir = '/var/www/main/html' %}

# Make sure the parent directory exists
server.chat.quassel.search.parentdir:
  file.directory:
    - name: {{ qsearch_html_dir }}
    - makedirs: True

server.chat.quassel.search.repodepends:
  pkg.installed:
    - pkgs:
      # For Salt to download repo
      - python3-git

server.chat.quassel.search:
  file.directory:
    - name: {{ qsearch_html_dir }}/search
    - user: www-manage
    - require:
      - file: server.chat.quassel.search.parentdir
    - require:
      - user: www-data-manager
  # Allow modifications with the www-manage user to avoid running Git as root
  git.latest:
    - name: 'https://github.com/justjanne/quassel-rest-search.git'
    - target: {{ qsearch_html_dir }}/search
    - user: www-manage
    - rev: {{ salt['pillar.get']('server:chat:quassel:versions:search:revision', 'HEAD') }}
    - branch: {{ salt['pillar.get']('server:chat:quassel:versions:search:branch', 'master') }}
    - force_reset: True
    - require:
      - sls: 'server.chat.quassel.core'
      - user: www-data-manager
      # Need git
      - pkg: server.chat.quassel.search.repodepends

server.chat.quassel.search.config:
  file.managed:
    - name: {{ qsearch_html_dir }}/search/qrs_config.php
    - source: salt://files/server/chat/quassel/search/qrs_config.php
    - user: www-manage
    - group: www-data
    # Don't allow world-wide access to database details
    - mode: 640
    - template: jinja
    - require:
      - git: 'server.chat.quassel.search'

# Salt doesn't seem to have a way for cmd.script's "unless" clause to be a remote script, too
server.chat.quassel.search.database:
  file.managed:
    - name: /root/salt/quassel-search-setup.sh
    - source: salt://files/server/chat/quassel/search/quassel-search-setup.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
  cmd.run:
    # Configure the Quassel database to add search indices
    - name: /root/salt/quassel-search-setup.sh "{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}" enable
#    - source: salt://files/server/chat/quassel/search/quassel-search-setup.sh
    # Ignore if storage settings already configured
    - unless: /root/salt/quassel-search-setup.sh "{{ salt['pillar.get']('server:chat:quassel:database:name', 'quassel') }}" check
    - require:
      - sls: 'server.chat.quassel.core'
