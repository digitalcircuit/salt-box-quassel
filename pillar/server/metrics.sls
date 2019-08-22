# Metrics
server:
  metrics:
    # Telegraf remote reporting configuration
    telegraf:
      enabled: False
      inputs:
        ping:
          enabled: False
          interval: 15s
          hosts:
            - "public.domain.here.example.com"
            - "other_destination.invalid"
        http_response:
          enabled: False
          interval: 15s
          addresses:
            - "https://public.domain.here.example.com"
            - "https://other_destination.invalid"
      endpoint:
        # How often to save data
        # Higher values have more risk of running over the buffer during outages
        interval: 30s
        # This should be HTTPS!
        url: https://remote_stats_url.invalid/metrics
        user: telegraf_remote_user
        pass: ChangeMe!
