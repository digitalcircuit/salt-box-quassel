# Swap file for system

# Mostly from https://serverfault.com/questions/628531/how-to-enable-swap-with-salt-stack

system_swap:
{% if salt['pillar.get']('system:tuning:swap:enabled', False) == True %}
  # Enable swap
  pkg.installed:
    - name: coreutils
  cmd.run:
    # Create '/swap.img', defaulting to 2048 MB
    - name: |
        [ -f /swap.img ] || dd if=/dev/zero of=/swap.img bs=1M count={{ salt['pillar.get']('system:tuning:swap:size', '2048') }}
        chmod 0600 /swap.img
        mkswap /swap.img
        swapon -a
    - unless:
       - swapon --show=name | grep -q "NAME"
    #   - file /swap.img 2>&1 | grep -q "Linux/i386 swap"
  mount.swap:
    - name: /swap.img
    - persist: true
{% else %}
  ## Disable swap - no longer supported
  #mount.swapoff:
  #  - name: /swap.img
  # Remove swap.. somehow?
{% endif %}
