# Configuration variables for network whitelisting

# Declared as arrays
# Example:
#   ARRAY=( [0]="first element" [1]="second element" [3]="fourth element" )
#
# See https://www.tldp.org/LDP/abs/html/arrays.html

# Restricted user
NET_WHITELIST_LIMITED_USER="{{ salt['pillar.get']('quassel:core:username', 'quasselcore') }}"

# Allowed hosts
{# Convert from a Jinja array to Bash array, with controlled whitespace #}
NET_WHITELIST_ALLOWED_HOSTS=({% for host in salt['pillar.get']('quassel:lockdown:strict-networks:hosts', '') %}
	"{{ host }}"{% endfor %}
)

# Allowed ports
NET_WHITELIST_ALLOWED_PORTS=({% for port in salt['pillar.get']('quassel:lockdown:strict-networks:ports', '') %}
	"{{ port }}"{% endfor %}
)
