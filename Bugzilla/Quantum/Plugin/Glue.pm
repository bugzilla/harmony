# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Plugin::Glue;
use Mojo::Base 'Mojolicious::Plugin';

use Try::Tiny;
use Bugzilla::Constants;
use Bugzilla::Quantum::Template;
use Socket qw(AF_INET inet_aton);
use Sys::Hostname;
use IO::String;

sub register {
    my ( $self, $app, $conf ) = @_;

    my $template = Bugzilla::Template->create;
    $template->{_is_main} = 1;

    $app->renderer->add_handler(
        'bugzilla' => sub {
            my ( $renderer, $c, $output, $options ) = @_;
            my $vars = delete $c->stash->{vars};

            # Helpers
            my %helper;
            foreach my $method ( grep {m/^\w+\z/} keys %{ $renderer->helpers } ) {
                my $sub = $renderer->helpers->{$method};
                $helper{$method} = sub { $c->$sub(@_) };
            }
            $vars->{helper} = \%helper;

            # The controller
            $vars->{c} = $c;
            my $name = $options->{template};
            unless ($name =~ /\./) {
                $name = sprintf '%s.%s.tmpl', $options->{template}, $options->{format};
            }
            $template->process( $name, $vars, $output )
                or die $template->error;
        }
    );

    $app->hook(
        around_dispatch => sub {
            my ($next, $c) = @_;
            local %ENV = _ENV($c);
            my $stdin = _STDIN($c);
            my $stdout = '';
            try {
                local $CGI::Compile::USE_REAL_EXIT = 0;
                local *STDIN; ## no critic (local)
                local *STDOUT;
                open STDIN, '<', $stdin->path or die "STDIN @{[$stdin->path]}: $!" if -s $stdin->path;
                open STDOUT, '>', \$stdout or die "STDOUT capture: $!";

                Bugzilla::init_page();
                Bugzilla->request_cache->{mojo_controller} = $c;
                Bugzilla->template( Bugzilla::Quantum::Template->new( controller => $c, template => $template ) );
                $next->();
            }
            catch {
                die $_ unless ref $_ eq 'ARRAY' && $_->[0] eq "EXIT\n" || /\bModPerl::Util::exit\b/;
            }
            finally {
                if (length $stdout) {
                    warn "setting body\n";
                    $c->res->body($stdout);
                    $c->rendered;
                }
                Bugzilla::_cleanup; ## no critic (private)
                CGI::initialize_globals();
            };
        }
    );
}

sub _ENV {
    my ($c)     = @_;
    my $tx      = $c->tx;
    my $req     = $tx->req;
    my $headers = $req->headers;
    my $content_length = $req->content->is_multipart ? $req->body_size : $headers->content_length;
    my %env_headers = ( HTTP_COOKIE => '', HTTP_REFERER => '' );

    for my $name ( @{ $headers->names } ) {
        my $key = uc "http_$name";
        $key =~ s!\W!_!g;
        $env_headers{$key} = $headers->header($name);
    }

    my $remote_user;
    if ( my $userinfo = $c->req->url->to_abs->userinfo ) {
        $remote_user = $userinfo =~ /([^:]+)/ ? $1 : '';
    }
    elsif ( my $authenticate = $headers->authorization ) {
        $remote_user = $authenticate =~ /Basic\s+(.*)/ ? b64_decode $1 : '';
        $remote_user = $remote_user =~ /([^:]+)/       ? $1            : '';
    }

    return (
        CONTENT_LENGTH => $content_length        || 0,
        CONTENT_TYPE   => $headers->content_type || '',
        GATEWAY_INTERFACE => 'CGI/1.1',
        HTTPS             => $req->is_secure ? 'YES' : 'NO',
        %env_headers,
        QUERY_STRING => $c->stash('cgi.query_string') || $req->url->query->to_string,
        REMOTE_ADDR => $tx->remote_address,
        REMOTE_HOST => gethostbyaddr( inet_aton( $tx->remote_address || '127.0.0.1' ), AF_INET ) || '',
        REMOTE_PORT => $tx->remote_port,
        REMOTE_USER => $remote_user || '',
        REQUEST_METHOD  => $req->method,
        SCRIPT_NAME     => $req->env->{SCRIPT_NAME},
        SERVER_NAME     => hostname,
        SERVER_PORT     => $tx->local_port,
        SERVER_PROTOCOL => $req->is_secure ? 'HTTPS' : 'HTTP', # TODO: Version is missing
        SERVER_SOFTWARE => __PACKAGE__,
    );
}

sub _STDIN {
    my $c = shift;
    my $stdin;

    if ( $c->req->content->is_multipart ) {
        $stdin = Mojo::Asset::File->new;
        $stdin->add_chunk( $c->req->build_body );
    }
    else {
        $stdin = $c->req->content->asset;
    }

    return $stdin if $stdin->isa('Mojo::Asset::File');
    return Mojo::Asset::File->new->add_chunk( $stdin->slurp );
}


1;