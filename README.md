Quassel-in-a-box
===============

**This is a work in progress**

This takes a stock Ubuntu 16.04 system, and with Salt, turns it into an IRC setup with desktop, mobile, and web clients, search, a home page, and includes Let's Encrypt certificates for encrypted connections.

*This is not endorsed by the official [Quassel IRC project][web-quassel], [Quassel Webserver][web-quassel-web], or [Quassel Rest Search][web-quassel-rest-search]*

## Deployment

* Customize the files in ```pillar``` to suit your environment
* Apply the salt state via ```salt-call```

*More to be added in the future*

## Usage

*To be added in the future*

## Credits

* [Quassel IRC][web-quassel] for the IRC client and server core
* [Quassel Webserver][web-quassel-web] for web chat
* [Quassel Rest Search][web-quassel-rest-search] for web search
* *Some credits in the individual files, too*
* *If you're missing, let me know, and I'll fix it as soon as I can!*

[web-quassel]: https://github.com/quassel/quassel
[web-quassel-rest-search]: https://github.com/justjanne/quassel-rest-search/
[web-quassel-web]: https://github.com/magne4000/quassel-webserver
