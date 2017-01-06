# Version information for unstable releases

# Git refers to branch names or commit hashes
# You should test updates in a development environment first.
versions:
  # Quassel IRC software versions
  quassel:
    # Quassel Rest Search - https://github.com/justjanne/quassel-rest-search/
    search-git: 2.0
    # Quassel Webserver - https://github.com/magne4000/quassel-webserver/
    web-git: master

# NodeJS versions
# Separate from above to maintain compatibility with the saltstack formula
node:
  ppa:
    repository_url: https://deb.nodesource.com/node_7.x
