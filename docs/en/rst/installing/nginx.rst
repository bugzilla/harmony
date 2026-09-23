.. This document is shared among all non-Windows OSes.

.. _nginx:

Nginx
#####

Bugzilla runs as its own web application. Nginx is used as a reverse
proxy in front of it and can also handle TLS.

Add a server block for your Bugzilla hostname. On Debian and Ubuntu use
:file:`/etc/nginx/sites-available/bugzilla`; on Fedora and Red Hat use
:file:`/etc/nginx/conf.d/bugzilla.conf`:

.. code-block:: nginx

    server {
        listen 80;
        server_name bugzilla.example.org;

        client_max_body_size 10m;

        location / {
            proxy_pass http://127.0.0.1:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

On Debian and Ubuntu, enable the site:

.. code-block:: console

    sudo ln -s /etc/nginx/sites-available/bugzilla /etc/nginx/sites-enabled/

Then reload Nginx with ``sudo systemctl reload nginx``.

If Nginx terminates TLS, serve Bugzilla from a ``443`` server block and
redirect plain HTTP to it. The ``X-Forwarded-Proto $scheme`` header above
already tells Bugzilla to generate ``https`` URLs. Tools such as Certbot can
generate this configuration and the certificates for you.

.. code-block:: nginx

    server {
        listen 443 ssl;
        listen [::]:443 ssl;
        server_name bugzilla.example.org;

        ssl_certificate     /etc/letsencrypt/live/bugzilla.example.org/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/bugzilla.example.org/privkey.pem;

        client_max_body_size 10m;

        location / {
            proxy_pass http://127.0.0.1:3001;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }

    server {
        listen 80;
        listen [::]:80;
        server_name bugzilla.example.org;
        return 301 https://$host$request_uri;
    }

.. note::
    Nginx rejects request bodies larger than 1 MB by default, which blocks
    larger attachment uploads. Set ``client_max_body_size`` to at least the
    value of the :param:`maxattachmentsize` parameter.

.. note::
    Bugzilla listens on port 3001 by default. Set the ``PORT`` environment
    variable to change it, and update ``proxy_pass`` to match. Start the
    web app using ``MOJO_REVERSE_PROXY=1 ./bugzilla.pl daemon`` when
    running behind Nginx, so it trusts the forwarded headers.
