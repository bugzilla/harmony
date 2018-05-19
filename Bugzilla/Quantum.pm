# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum;
use Mojo::Base 'Mojolicious';

use CGI::Compile; # Primarily for its exit overload.
use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::Template;
use Bugzilla::Quantum::Legacy;
use Bugzilla::Quantum::Static;
use Bugzilla::PSGI qw(compile_cgi);

use Bugzilla ();
use Bugzilla::Constants qw(bz_locations);
use Bugzilla::BugMail ();
use Bugzilla::CGI ();
use Bugzilla::Extension ();
use Bugzilla::Install::Requirements ();
use Bugzilla::Util ();
use Bugzilla::RNG ();
use Cwd qw(realpath);

has 'static' => sub { Bugzilla::Quantum::Static->new };

sub startup {
    my ($self) = @_;

    my $extensions = Bugzilla::Extension->load_all();
    Bugzilla->preload_features();
    Bugzilla->template;
    $self->secrets([Bugzilla->localconfig->{side_wide_secret}]);

    my $rest = compile_cgi('rest.cgi');
    $self->plugin('Bugzilla::Quantum::Plugin::Glue');
    $self->plugin(
        'MountPSGI' => {
            rewrite => 1,
            '/rest' => $rest,
        }
    );
    $self->plugin(
        'MountPSGI' => {
            rewrite => 1,
            '/rest.cgi' => $rest,
        }
    );
    $self->plugin(
        'MountPSGI' => {
            rewrite => 1,
            '/xmlrpc.cgi' => compile_cgi('xmlrpc.cgi'),
        }
    );
    $self->plugin(
        'MountPSGI' => {
rewrite => 1,
            '/jsonrpc.cgi' => compile_cgi('jsonrpc.cgi'),
        }
    );
    my $r = $self->routes;
    Bugzilla::Quantum::Legacy->expose_routes($r);

    $r->any('/')->to('Legacy#index_cgi');

    $r->get(
        '/__lbheartbeat__' => sub {
            my $c = shift;
            $c->reply->file($c->app->home->child('__lbheartbeat__'));
        },
    );

    my $urlbase = Bugzilla->localconfig->{urlbase};
    $r->get(
        '/quicksearch.html' => sub {
            my $c = shift;
            $c->res->code(301);
            $c->redirect_to( $urlbase . 'page.cgi?id=quicksearch.html' );
        }
    );
    $r->get(
        '/bugwritinghelp.html' => sub {
            my $c = shift;
            $c->res->code(301);
            $c->redirect_to( $urlbase . 'page.cgi?id=bug-writing.html', 301 );
        }
    );
    $r->get(
        '/<bug_id:num>' => sub {
            my $c = shift;
            $c->res->code(301);
            my $bug_id = $c->param('bug_id');
            $c - redirect_to( $urlbase . "show_bug.cgi?id=$bug_id" );
        }
    );
}

1;
