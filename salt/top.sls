# Apply to all (since we only have one machine)
base:
  '*':
    # Activate swap first if enabled to avoid out-of-memory conditions
    - common/swapfile
    - certbot
    - quassel
    - quassel-search
    - quassel-web
    - webserver
