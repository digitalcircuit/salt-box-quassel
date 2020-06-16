# Configuration variables for network lockdown

# Declared as arrays
# Example:
#   ARRAY=( [0]="first element" [1]="second element" [3]="fourth element" )
#
# See https://www.tldp.org/LDP/abs/html/arrays.html

# Restricted user
NET_LOCKDOWN_LIMITED_USER="{{ salt['pillar.get']('server:chat:quassel:core:username', 'quasselcore') }}"

# Allowed hosts
{# Convert from a Jinja array to Bash array, with controlled whitespace #}
NET_LOCKDOWN_ALLOWED_HOSTS=({% for host in salt['pillar.get']('server:chat:quassel:lockdown:strict-networks:hosts', '') %}
	"{{ host }}"{% endfor %}
)

# Allowed ports
NET_LOCKDOWN_ALLOWED_PORTS=({% for port in salt['pillar.get']('server:chat:quassel:lockdown:strict-networks:ports', '') %}
	"{{ port }}"{% endfor %}
)
