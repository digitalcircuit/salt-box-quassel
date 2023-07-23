# User-visible branding and display
server:
  chat:
    quassel:
      branding:
        # Title of service
        title: "Quassel Hosted"
        # Big, bold page name text
        name: "Hosted Quassel Chat"
        # Welcome message
        header: "Welcome to Quassel IRC"
        # Quassel IRC branding
        client:
          # Name of IRC service
          - name: "Quassel"
          # Suggestions
          - prompt: "Use the desktop/mobile version when possible; it's faster and has more features"
          # Show unstable versions of Quassel desktop/mobile?
          - show_beta: False
          # Show core connection details for Quassel desktop/mobile?
          - show_core_connection: True
        # Error pages
        errors:
          # On error pages, show a contact note?
          - show_contact: True
          # Details on getting in touch
          - contact_prompt: "send me a message"
