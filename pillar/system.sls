# System details
system:
  # Hostname visible to the world, used in SSL certs and branding
  hostname: public.domain.here.example.com
  # Performance tuning
  tuning:
    # PostgreSQL settings
    postgres:
      # Maximum number of clients at once
      # Quassel core uses 1 connection per client, while Quassel Rest Search
      # uses 1 connection for each search/chat request.
      - max_connections: 100
      # Get values from http://pgtune.leopard.in.ua/
      - shared_buffers: 512MB
      - effective_cache_size: 1536MB
      - work_mem: 2621kB
      - maintenance_work_mem: 128MB
    # Virtual memory
    swap:
      # Use a swapfile?  Disable if already set up or not needed
      - enabled: true
      # Size of swapfile
      - size: 2048
