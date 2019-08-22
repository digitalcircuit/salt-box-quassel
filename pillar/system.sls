# System details
system:
  # Hostname visible to the world, used in SSL certs and branding
  hostname: public.domain.here.example.com
  # Performance tuning
  tuning:
    # Virtual memory
    swap:
      # Use a swapfile?  Disable if already set up or not needed
      - enabled: true
      # Size of swapfile
      - size: 2048
