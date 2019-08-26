# Remote details
server:
  # Hostnames
  hostnames:
    # Domains by certificate chain
    # Main domain
    cert-primary:
      # Hostname visible to the world, used in SSL certs and branding
      root: public.domain.here.example.com
      # Additional domains may be added like this
      # friendly-name: subdomain.example.com
      # friendly-name-2: other.domain.invalid
    # Additional certificate chains may be added like this
    #cert-additional:
    #  root: example.invalid
