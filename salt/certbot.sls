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
# FIXME Install the PPA version for now; remove this once backported!
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
    - name: /etc/letsencrypt/renewal-hooks/deploy/certbot-setup-reload
    - source: salt://files/certbot/certbot-setup-reload
    - makedirs: True
    - template: jinja
    # Mark as executable
    - mode: 755
    # Hooks directory is created during first run, but this script should be
    # ready before first run.

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
    # Configure Certbot to acquire the certificates for the first time
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

# --- Migrations ---
# certbot 0.19
# Remove old configuration hook script
certbot.migrate.remove_old_hook_configure:
  file.line:
    - name: "/etc/letsencrypt/renewal/{{ salt['pillar.get']('system:hostname', 'dev') }}.conf"
    - content: "post_hook = /bin/run-parts /etc/letsencrypt/post-hook.d/"
    - mode: delete
    - require:
      - file: certbot.configure
      - cmd: certbot.configure

# Remove old renewal hook directory
certbot.migrate.remove_old_hooks:
  file.absent:
    - name: /etc/letsencrypt/post-hook.d

{% endif %}
