# NodeJS stable

# Mostly from https://github.com/saltstack-formulas/node-formula/blob/master/node/pkg.sls
# Consider directly depending on that if more flexibility needed

{% if grains['cpuarch'] == 'aarch64' -%}
{% set debian_repo_arch = 'arm64' %}
{%- else -%}
{% set debian_repo_arch = 'amd64' %}
{%- endif %}

nodejs.repo:
  pkgrepo.managed:
    - humanname: NodeSource Node.js Repository
    - name: deb [signed-by=/etc/apt/keyrings/nodesource-keyring.gpg arch={{ debian_repo_arch }}] {{ salt['pillar.get']('node:ppa:repository_url', 'https://deb.nodesource.com/node_20.x') }} nodistro main
    # As of 20.x, no more codename
    #- name: deb [signed-by=/etc/apt/keyrings/nodesource-keyring.gpg arch={{ debian_repo_arch }}] {{ salt['pillar.get']('node:ppa:repository_url', 'https://deb.nodesource.com/node_20.x') }} {{ grains['oscodename'] }} main
    #- dist: {{ grains['oscodename'] }}
    - file: /etc/apt/sources.list.d/nodesource.list
    - key_url: https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key
    - aptkey: False
    - require_in:
      pkg: nodejs

nodejs:
  pkg.installed:
    - name: nodejs
