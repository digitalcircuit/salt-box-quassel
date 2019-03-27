# Swap file for system

# Mostly from https://serverfault.com/questions/628531/how-to-enable-swap-with-salt-stack

system_swap:
{% if salt['pillar.get']('system:tuning:swap:enabled', False) == True %}
  # Enable swap
  pkg.installed:
    - name: coreutils
  cmd.run:
    # Create '/swapfile', defaulting to 2048 MB
    - name: |
        [ -f /swapfile ] || dd if=/dev/zero of=/swapfile bs=1M count={{ salt['pillar.get']('system:tuning:swap:size', '2048') }}
        chmod 0600 /swapfile
        mkswap /swapfile
        swapon -a
    - unless:
      - file /swapfile 2>&1 | grep -q "Linux/i386 swap"
  mount.swap:
    - name: /swapfile
    - persist: true
{% else %}
  ## Disable swap - no longer supported
  #mount.swapoff:
  #  - name: /swapfile
  # Remove swap.. somehow?
{% endif %}
