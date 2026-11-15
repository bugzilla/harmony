
.. _caddy:

Caddy
#####

The Caddy web server has built in support for reverse proxies. 

It also automates the creation of Let's Encrypt certificates for 
the hosts specified in the Caddyfile.

An example Caddyfile for Bugzilla would be:

.. code-block::
    
    hostname {
        reverse_proxy 127.0.0.1:3001
    }

.. note:: 
    Start the Bugzilla web app so that it listens on the loopback
    interface only and trusts the forwarded headers from Caddy:

    .. code-block:: console

        MOJO_LISTEN=http://127.0.0.1:3001 MOJO_REVERSE_PROXY=1 ./bugzilla.pl daemon

    Bugzilla listens on all interfaces by default, and so does setting
    ``PORT``. With ``MOJO_REVERSE_PROXY=1`` the app trusts forwarding
    headers sent by whatever connects to it, so the backend port must not
    be reachable from other hosts. To use another port, change it in
    ``MOJO_LISTEN`` and in the ``reverse_proxy`` line. Also set
    ``$urlbase`` and ``$inbound_proxies`` as described in
    :ref:`reverse_proxy_settings`.
