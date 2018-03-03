# Quassel Search

# Require Quassel and webserver to be installed first
include:
  - quassel
  - webserver

quassel-search:
  file.directory:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/search
    - user: www-manage
  # Allow modifications with the www-manage user to avoid running Git as root
  git.latest:
    - name: 'https://github.com/justjanne/quassel-rest-search.git'
    - target: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/search
    - user: www-manage
    - rev: {{ salt['pillar.get']('versions:quassel:search:revision', 'HEAD') }}
    - branch: {{ salt['pillar.get']('versions:quassel:search:branch', 'master') }}
    - force_reset: True
    - require:
      - sls: 'quassel'
      - sls: 'webserver'

quassel-search.config:
  file.managed:
    - name: /var/www/html_{{ salt['pillar.get']('system:hostname', 'dev') }}/search/qrs_config.php
    - source: salt://files/quassel-search/qrs_config.php
    - user: www-manage
    - group: www-data
    # Don't allow world-wide access to database details
    - mode: 640
    - template: jinja
    - require:
      - git: 'quassel-search'

# Salt doesn't seem to have a way for cmd.script's "unless" clause to be a remote script, too
quassel-search.database:
  file.managed:
    - name: /root/salt/quassel-search-setup.sh
    - source: salt://files/quassel-search/quassel-search-setup.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
  cmd.run:
    # Configure the Quassel database to add search indices
    - name: /root/salt/quassel-search-setup.sh "{{ salt['pillar.get']('quassel:database:name', 'quassel') }}" enable
#    - source: salt://files/quassel-search/quassel-search-setup.sh
    # Ignore if storage settings already configured
    - unless: /root/salt/quassel-search-setup.sh "{{ salt['pillar.get']('quassel:database:name', 'quassel') }}" check
    - require:
      - sls: 'quassel'
