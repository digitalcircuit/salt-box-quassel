# Quassel Web, which requires NodeJS

# Require Quassel and webserver to be installed first
include:
  - quassel
  - webserver
  - common/nodejs

# Set up the user
quassel-web.user-basic:
  user.present:
    - name: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - fullname: 'Quassel Web server user'
    - system: True
    - createhome: False # Handled below
  file.directory:
    - name: /home/quassel-web/
    - user: root
    - group: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    # Don't allow world-wide access to details, including configuration
    # Not required, but neither is global access, either - Salt manages this
    # Also, enforce read-only mode
    - mode: 550

quassel-web.user-rw:
  file.directory:
    - user: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - group: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    # Node, NPM, and Quassel Web needs to modify some folders
    - mode: 750
    # Specify all of the needed read-write directories
    - names:
      - /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/quassel_web_root
      - /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/.npm
      - /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/.node-gyp
      # Git configuration
      - /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/.config
#      # TODO - are the following needed?
#      - /home/quassel-web/.local/share"
#       > Why does Nano require a different directory?  :(
#      - /home/quassel-web/.nano"
#      - /home/quassel-web/.cache"

quassel-web.setup.script:
  file.managed:
    # Basic configuration
    - name: /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/quassel_web_root/var-root-dir.sh
    - source: salt://files/quassel-web/home/var-root-dir.sh
    - user: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - group: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}

# Stop the Quassel Web service if already running.. only if changes will be
# made.  It'll be started back up by the later service check.
quassel-web.setup.stop-for-deploy:
  service.dead:
    - name: quassel-web.service
    # Only stop if changes are going to be made
    - prereq:
      - cmd: quassel-web.setup.deploy
      - file: quassel-web.setup.configure

quassel-web.setup.deploy:
  pkg.installed:
    # Dependencies for NodeJS package building (e.g. BufferUtil)
    # See https://github.com/magne4000/quassel-webserver/commit/79776c7a5db163273217fb87a76c8c27bfec9a45
    - pkgs:
      - python
      - build-essential
  file.recurse:
    # Runtime scripts
    - name: /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/quassel_web_root/scripts
    - source: salt://files/quassel-web/home/scripts
    - user: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - group: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - clean: True
    # Set execute permissions
    - file_mode: 755
  cmd.run:
    # Run initial setup/update
    - name: /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/quassel_web_root/scripts/setup-quassel-web.sh update {{ salt['pillar.get']('versions:quassel:web-git', 'master') }}
    # But only if there's actually an update available
    - onlyif: /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/quassel_web_root/scripts/setup-quassel-web.sh check {{ salt['pillar.get']('versions:quassel:web-git', 'master') }}
    # Don't run as root
    - runas: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}

quassel-web.setup.configure:
  file.managed:
    # Quassel Web configuration
    - name: /home/{{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}/quassel_web_root/qweb/quassel-webserver/settings-user.js
    - source: salt://files/quassel-web/settings-user.js
    - user: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - group: {{ salt['pillar.get']('quassel:web:username', 'quassel-web') }}
    - template: jinja
    - require:
      # Don't try to set this up until after the repository's downloaded
      - cmd: 'quassel-web.setup.deploy'

# Set up the systemd service
quassel-web.service:
  file.managed:
    - name: /etc/systemd/system/quassel-web.service
    - source: salt://files/quassel-web/quassel-web.service
    - template: jinja
  service.running:
    - name: quassel-web.service
    - enable: True
    - watch:
      # Restart service on changes, wait for service to deployed before start
      - file: 'quassel-web.service'
    - require:
      - sls: 'quassel'
      - sls: 'webserver'
      - sls: 'common/nodejs'
