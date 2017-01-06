# Certbot for Let's Encrypt certificates

{% if salt['pillar.get']('certbot:enable', False) == True %}
# Require quassel and webserver to be installed first
include:
  - quassel
  - webserver

# Ensure Let's Encrypt challenges directory exists
certbot.config.challenges:
  file.directory:
    - name: /var/lib/letsencrypt
    # Don't allow global access to the challenges
    - user: root
    - group: www-data
    - mode: 750

# Install Certbot itself
# FIXME Install the PPA version for now; remove this once 0.9.3 is backported!
certbot.ppa:
  pkgrepo.managed:
    - ppa: certbot/certbot
  pkg.uptodate:
    # Only update if changes are made
    - onchanges:
      - pkgrepo: certbot.ppa

certbot:
  pkg.installed:
    - pkgs:
      - certbot
    - refresh: True # Only needed when using PPA
    - require:
      - pkgrepo: certbot.ppa

# Set up renewal hooks
# Do before installation so any running services will be reloaded
certbot.renewal:
  file.managed:
    - name: /etc/letsencrypt/post-hook.d/certbot-setup-reload
    - source: salt://files/certbot/certbot-setup-reload
    - template: jinja
    # Mark as executable
    - mode: 755
    # Hooks directory is created during installation
    - require:
      - pkg: certbot

# Get Let's Encrypt configured and set up
# Salt doesn't seem to have a way for cmd.script's "unless" clause to be a remote script, too
certbot.configure:
  file.managed:
    - name: /root/salt/certbot/certbot-setup.sh
    - source: salt://files/certbot/certbot-setup.sh
    - makedirs: True
    # Mark as executable
    - mode: 755
  cmd.run:
    # Configure the Quassel core to use the Postgres database
    - name: /root/salt/certbot/certbot-setup.sh configure "{{ salt['pillar.get']('system:hostname', 'dev') }}" "{{ salt['pillar.get']('certbot:testing', 'false') }}" "{{ salt['pillar.get']('certbot:account:email') }}"
      # {system hostname} {testing mode - true/false} {account recovery email}
#    - source: salt://files/certbot/certbot-setup.sh
    # Ignore if certbot already configured
    - unless: /root/salt/certbot/certbot-setup.sh check "{{ salt['pillar.get']('system:hostname', 'dev') }}"
    - require:
      - sls: 'quassel'
      - sls: 'webserver'
      - pkg: certbot
      - file: certbot.renewal

{% endif %}
