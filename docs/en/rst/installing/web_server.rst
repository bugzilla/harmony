.. _web_server:

Web Server
##########

Bugzilla runs as a web app, but for production use, you will want 
to proxy it through a web server.

.. toctree::
   :maxdepth: 1

   apache
   apache-windows
   caddy
   iis
   nginx

.. _reverse_proxy_settings:

Settings for a proxied Bugzilla
===============================

When a web server proxies to Bugzilla, set these two variables in
:file:`localconfig` and restart the Bugzilla web app. The app reads them
only when it starts handling requests.

:param:`$urlbase`
  The address users type, with scheme, hostname and trailing slash, for
  example :paramval:`https://bugzilla.example.org/`. Most links in
  Bugzilla's pages and email are built from it, not from the request.
  Requests whose ``Host`` header does not match its hostname are
  redirected to it, so the proxy must pass the original ``Host`` header
  on, as the Apache and Nginx examples do.

:param:`$inbound_proxies`
  Set this to :paramval:`*` when Bugzilla is behind a proxy. Any
  non-empty value turns on the HTTPS check described below. ``*`` is also
  the value :file:`scripts/entrypoint.pl` expects: it logs a warning at
  startup if ``$urlbase`` is ``https`` and this is anything else. It does
  not decide whose ``X-Forwarded-For`` header Bugzilla believes.

If ``$urlbase`` starts with ``https`` and ``$inbound_proxies`` is not empty,
Bugzilla answers every page request it does not see as HTTPS, including
plain HTTP requests, with status 500 and the text "Reverse Proxy is
Misconfigured", and logs an error. Redirect port 80 to HTTPS instead of
proxying it. Behind a proxy, Bugzilla sees a request as HTTPS only when
reverse proxy support is on and the proxy sends
``X-Forwarded-Proto: https``. Start the app with ``MOJO_REVERSE_PROXY=1``
to turn it on. If ``$inbound_proxies`` is empty this check is skipped, and
a proxy that does not send the header is not detected.

