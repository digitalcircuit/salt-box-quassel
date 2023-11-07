module.exports = {
    default: {  // Those can be overridden in the browser
        host: 'localhost',  // quasselcore host
        port: {{ salt['pillar.get']('server:chat:quassel:core:port', '4242') }},  // quasselcore port
        initialBacklogLimit: 20,  // Amount of backlogs to fetch per buffer on connection
        backlogLimit: 100,  // Amount of backlogs to fetch per buffer after first retrieval
        {%- set brokenver_openssl = '1.1.1f' -%}
        {%- set localver_openssl = salt['pkg.list_repo_pkgs']('openssl')['openssl'] |first() -%}
        {% if grains.os_family == 'Debian' and salt['pkg.version_cmp'](localver_openssl, brokenver_openssl) >= 0 %}
        {# See https://stackoverflow.com/questions/41479482/how-do-i-allow-a-salt-stack-formula-to-run-on-only-certain-operating-system-vers -#}
        securecore: false,  // Connect to the core using SSL
        // Disable this by default for Debian with openssl >= {{ brokenver_openssl }} until SSL issue is resolved
        // See https://github.com/magne4000/quassel-webserver/issues/285
        // As the core connection is via 'localhost', the potential impact is reduced
        {% else %}
        securecore: true,  // Connect to the core using SSL
        {% endif -%}
        theme: 'default',  // Default UI theme
        perchathistory: true,  // Separate history per buffer
        displayfullhostmask: false,  // Display full hostmask instead of just nicks in messages
        emptybufferonswitch: 900,  // Trim buffer when switching to another buffer. Can be `false` or a positive integer
        highlightmode: 3  // Highlight mode: 1: None, 2: Current nick, 3: All nicks from identity
    },
    webserver: {
        socket: '{{ salt["pillar.get"]("server:chat:quassel:web:socket_dir", "/var/run/quassel-web") }}/quassel-web.sock',  // Tells the webserver to listen for connections on a local socket. This should be a path. Can be overridden by '--socket' argument
        listen: null,  // Address on which to listen for connection, defaults to listening on all available IPs. Can be overridden by '--listen' argument
        port: null,  // Port on which to listen for connection, defaults to 64080 for http mode, 64443 for https. Can be overridden by '--port' argument
        mode: null  // can be 'http' or 'https', defaults to 'https'. Can be overridden by '--mode' argument
    },
    themes: ['default', 'darksolarized'],  // Available themes
    forcedefault: true,  // Will force default host and port to be used if true, and will hide the corresponding fields in the UI.
    prefixpath: '/chat'  // Configure this if you use a reverse proxy
};
