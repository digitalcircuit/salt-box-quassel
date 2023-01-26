# NodeJS stable

# Mostly from https://github.com/saltstack-formulas/node-formula/blob/master/node/pkg.sls
# Consider directly depending on that if more flexibility needed

nodejs.repo:
  pkgrepo.managed:
    - humanname: NodeSource Node.js Repository
    - name: deb [signed-by=/etc/apt/keyrings/nodesource-keyring.gpg arch=amd64] {{ salt['pillar.get']('node:ppa:repository_url', 'https://deb.nodesource.com/node_16.x') }} {{ grains['oscodename'] }} main
    - dist: {{ grains['oscodename'] }}
    - file: /etc/apt/sources.list.d/nodesource.list
    - key_url: https://deb.nodesource.com/gpgkey/nodesource.gpg.key
    - aptkey: False
    - require_in:
      pkg: nodejs

nodejs:
  pkg.installed:
    - name: nodejs
