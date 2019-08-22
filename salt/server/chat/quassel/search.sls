# Quassel Search

# Require Quassel to be installed first
include:
  - .core

# Joining strings with "~"
# See https://stackoverflow.com/questions/2061439/string-concatenation-in-jinja/
{% set qsearch_html_dir = '/var/www/html_' ~ salt['pillar.get']('system:hostname', 'dev') %}

# Make sure the parent directory exists
server.chat.quassel.search.parentdir:
  file.directory:
    - name: {{ qsearch_html_dir }}
    - makedirs: True

server.chat.quassel.search:
  file.directory:
    - name: {{ qsearch_html_dir }}/search
    - user: www-manage
    - require:
      - file: server.chat.quassel.search.parentdir
  # Allow modifications with the www-manage user to avoid running Git as root
  git.latest:
    - name: 'https://github.com/justjanne/quassel-rest-search.git'
    - target: {{ qsearch_html_dir }}/search
    - user: www-manage
    - rev: {{ salt['pillar.get']('versions:quassel:search:revision', 'HEAD') }}
    - branch: {{ salt['pillar.get']('versions:quassel:search:branch', 'master') }}
    - force_reset: True
    - require:
      - sls: 'server.chat.quassel.core'

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
