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
use JSON::MaybeXS qw(decode_json);
use Cwd qw(realpath);

use MojoX::Log::Log4perl::Tiny;

has 'static' => sub { Bugzilla::Quantum::Static->new };

sub startup {
    my ($self) = @_;
    my %D;
    if ($ENV{BUGZILLA_HTTPD_ARGS}) {
        my $args = decode_json($ENV{BUGZILLA_HTTPD_ARGS});
        foreach my $arg (@$args) {
            if ($arg =~ /^-D(\w+)$/) {
                $D{$1} = 1;
            }
            else {
                die "Unknown httpd arg: $arg";
            }
        }
    }

    $self->hook(
        before_dispatch => sub {
             my $c = shift;

             if ($D{HTTPD_IN_SUBDIR}) {
                my $path = $c->req->url->path;
                $path =~ s{^/bmo}{}s;
                $c->req->url->path($path);
             }
        }
    );

    my $extensions = Bugzilla::Extension->load_all();
    Bugzilla->preload_features();
    Bugzilla->template;
    $self->secrets([Bugzilla->localconfig->{side_wide_secret}]);

    $self->plugin('Bugzilla::Quantum::Plugin::Glue');
    $self->log(
        MojoX::Log::Log4perl::Tiny->new(
            logger => Log::Log4perl->get_logger(__PACKAGE__)
        )
    );

    my $r = $self->routes;
    Bugzilla::Quantum::CGI->load_all($r);
    Bugzilla::Quantum::CGI->load_one('bzapi_cgi', 'extensions/BzAPI/bin/rest.cgi');
    $r->any('/bzapi/*PATH_INFO')->to('CGI#bzapi_cgi');

    $r->any('/')->to('CGI#index_cgi');
    $r->any('/rest')->to('CGI#rest_cgi');
    $r->any('/rest/*PATH_INFO')->to('CGI#rest_cgi');

    $r->get(
        '/__lbheartbeat__' => sub {
            my $c = shift;
            $c->reply->file($c->app->home->child('__lbheartbeat__'));
        },
    );

}

1;
