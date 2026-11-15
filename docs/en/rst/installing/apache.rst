.. This document is shared among all non-Windows OSes.

.. _apache:

Apache
######

Bugzilla runs as its own web application. Apache is used as a reverse
proxy in front of it and can also handle TLS.

.. note::
  Previous versions of Bugzilla ran using Apache's ModPerl or as CGI.
  Neither is used anymore, so no Bugzilla-specific changes to the main
  Apache configuration file are needed.

Enable the proxy and header modules. On Debian and Ubuntu:

.. code-block:: console

    sudo a2enmod proxy proxy_http headers

On Fedora and Red Hat these modules are enabled by default.

Add a virtual host for your Bugzilla hostname. On Debian and Ubuntu use
:file:`/etc/apache2/sites-available/bugzilla.conf`; on Fedora and Red Hat
use :file:`/etc/httpd/conf.d/bugzilla.conf`:

.. code-block:: apache

    <VirtualHost *:80>
        ServerName bugzilla.example.org

        ProxyPreserveHost On
        ProxyPass / http://127.0.0.1:3001/
        ProxyPassReverse / http://127.0.0.1:3001/
    </VirtualHost>

On Debian and Ubuntu, enable the site and reload Apache:

.. code-block:: console

    sudo a2ensite bugzilla
    sudo systemctl reload apache2

On Fedora and Red Hat, reload with ``sudo systemctl reload httpd``.

If Apache terminates TLS, serve Bugzilla from a ``443`` virtual host.
Enable ``mod_ssl`` too (``sudo a2enmod ssl`` on Debian and Ubuntu; on
Fedora and Red Hat install the ``mod_ssl`` package). The
``X-Forwarded-Proto`` header tells Bugzilla that the request arrived over
HTTPS. Most links in Bugzilla's pages and email come from ``$urlbase``, not
from this header; see :ref:`reverse_proxy_settings`.

.. code-block:: apache

    <VirtualHost *:443>
        ServerName bugzilla.example.org

        SSLEngine on
        SSLCertificateFile    /etc/letsencrypt/live/bugzilla.example.org/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/bugzilla.example.org/privkey.pem

        RequestHeader set X-Forwarded-Proto "https"

        ProxyPreserveHost On
        ProxyPass / http://127.0.0.1:3001/
        ProxyPassReverse / http://127.0.0.1:3001/
    </VirtualHost>

Then replace the ``80`` virtual host above with a redirect, because with an
``https`` ``$urlbase`` and ``$inbound_proxies`` set, Bugzilla rejects plain
HTTP requests (see :ref:`reverse_proxy_settings`):

.. code-block:: apache

    <VirtualHost *:80>
        ServerName bugzilla.example.org
        Redirect permanent / https://bugzilla.example.org/
    </VirtualHost>

.. note::
    Start the Bugzilla web app so that it listens on the loopback
    interface only and trusts the forwarded headers from Apache:

    .. code-block:: console

        MOJO_LISTEN=http://127.0.0.1:3001 MOJO_REVERSE_PROXY=1 ./bugzilla.pl daemon

    Bugzilla listens on all interfaces by default, and so does setting
    ``PORT``. With ``MOJO_REVERSE_PROXY=1`` the app trusts forwarding
    headers sent by whatever connects to it, so the backend port must not
    be reachable from other hosts. To use another port, change it in
    ``MOJO_LISTEN`` and in the ``ProxyPass`` lines. Also set ``$urlbase``
    and ``$inbound_proxies`` as described in :ref:`reverse_proxy_settings`.
