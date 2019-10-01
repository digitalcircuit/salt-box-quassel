# Certificate details for Let's Encrypt
certbot:
  # Replace dummy certificates with certificates from Let's Encrypt?
  #
  # NOTE - enabling certbot implies you agree to the Let's Encrypt
  # Terms of Service (subscriber agreement).  Please read it first.
  # https://letsencrypt.org/repository/#let-s-encrypt-subscriber-agreement
  enable: True
  # Use staging/test server to avoid rate-limit issues?
  testing: False
  # Account details
  account:
    # Email address for recovery
    email: real-email-address@example.com
