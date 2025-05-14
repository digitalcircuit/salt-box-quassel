# Version information for unstable releases

# Git refers to branch names or commit hashes
# You should test updates in a development environment first.
server:
  chat:
    quassel:
      versions:
        # Quassel IRC software versions
        # Quassel itself
        core:
          beta: False
        # Quassel Rest Search - https://github.com/justjanne/quassel-rest-search/
        # Git commit ID/tag (HEAD is latest) and branch
        search:
          revision: HEAD
          branch: 3.0
        # Quassel Webserver - https://github.com/magne4000/quassel-webserver/
        # Git commit ID/tag (HEAD is latest) and branch
        web:
          revision: HEAD
          branch: master

# NodeJS versions
# Separate from above to maintain compatibility with the saltstack formula
node:
  ppa:
    repository_url: https://deb.nodesource.com/node_20.x
