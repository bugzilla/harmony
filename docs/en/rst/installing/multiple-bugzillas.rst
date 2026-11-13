.. _multiple-bz-dbs:

One Installation, Multiple Instances
####################################

This is a somewhat specialist feature; if you don't know whether you need it,
you don't. It is useful to admins who want to run many separate instances of
Bugzilla from a single installed codebase.

This is possible by using the ``PROJECT`` environment variable. When accessed,
Bugzilla checks for the existence of this variable, and if present, uses
its value to check for an alternative configuration file named
:file:`localconfig.<PROJECT>` in the same location as
the default one (:file:`localconfig`). It also checks for
customized templates in a directory named
:file:`<PROJECT>` in the same location as the
default one (:file:`template/<langcode>`). By default
this is :file:`template/en/default` so ``PROJECT``'s templates
would be located at :file:`template/en/PROJECT`.

To set up an alternate installation, just export ``PROJECT=foo`` before
running :command:`checksetup.pl` for the first time. It will
result in a file called :file:`localconfig.foo` instead of
:file:`localconfig`. Edit this file as described above, with
reference to a new database, and re-run :command:`checksetup.pl`
to populate it. That's all.

Each instance runs as its own Bugzilla web app process. Start it with
``PROJECT`` set and on its own port:

.. code-block:: console

    PROJECT=foo PORT=3002 MOJO_REVERSE_PROXY=1 ./bugzilla.pl daemon

Then configure your web server to proxy the instance's hostname to that
port, as described in :ref:`web_server`.

Don't forget to also export this variable before accessing Bugzilla
by other means, such as repeating tasks like those above.
