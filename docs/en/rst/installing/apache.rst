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

If Apache terminates TLS, add this header to your TLS virtual host so
Bugzilla generates ``https`` URLs:

.. code-block:: apache

    <VirtualHost *:443>
        RequestHeader set X-Forwarded-Proto "https"
    </VirtualHost>

.. note::
    Bugzilla listens on port 3001 by default. Set the ``PORT`` environment
    variable to change it, and update the ``ProxyPass`` lines to match.
    Start the web app using ``MOJO_REVERSE_PROXY=1 ./bugzilla.pl daemon``
    when running behind Apache, so it trusts the forwarded headers.
