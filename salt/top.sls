# Apply to all (since we only have one machine)
base:
  '*':
    # Activate swap first if enabled to avoid out-of-memory conditions
    - common.swapfile
    # Full Quassel install
    - server.chat.quassel.top
    # Optional status reporting
    - server.metrics.top
    # Certbot
    - server.web.certbot
    # Website
    - server.web.main
