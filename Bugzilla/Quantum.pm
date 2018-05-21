# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum;
use Mojo::Base 'Mojolicious';

use CGI::Compile; # Needed for its exit() overload
use Bugzilla::Logging;
use Bugzilla::Quantum::Template;
use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::Static;

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

    $self->plugin('Bugzilla::Quantum::Plugin::Glue');

    $self->log(Log::Log4perl->get_logger(__PACKAGE__));

    my $r = $self->routes;
    Bugzilla::Quantum::CGI->load_all($r);

    $r->any('/')->to('CGI#index_cgi');
    $r->any('/rest')->to('CGI#rest_cgi');
    $r->any('/rest/*path_info')->to('CGI#rest_cgi');

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
