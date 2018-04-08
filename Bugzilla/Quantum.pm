# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum;
use Mojo::Base 'Mojolicious';

use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::Template;
use Bugzilla::Quantum::Legacy;
use Bugzilla::PSGI qw(compile_cgi);

use Bugzilla ();
use Bugzilla::Constants ();
use Bugzilla::BugMail ();
use Bugzilla::CGI ();
use Bugzilla::Extension ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Util ();
use Bugzilla::RNG ();

sub startup {
    my ($self) = @_;

    Bugzilla::Extension->load_all();
    Bugzilla->preload_features();
    Bugzilla->template;

    $self->plugin('Bugzilla::Quantum::Plugin::Glue');

    $self->plugin(
        'MountPSGI' => {
            rewrite => 1,
            '/rest' => $rest,
            '/rest.cgi' => $rest,
            '/jsonrpc.cgi' => compile_cgi('jsonrpc.cgi'),
            '/xmlrpc.cgi' => compile_cgi('xmlrpc.cgi'),
        }
    );
    my $r = $self->routes;

    $r->any( '/' )->to('legacy#index_cgi');
    $r->any( '/show_bug.cgi' )->to('legacy#show_bug');
    $r->any('/bug/:id')->to('legacy#show_bug');
}

1;