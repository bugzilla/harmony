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
use Bugzilla::Quantum::CGI;
use Bugzilla::Quantum::Template;

sub register {
    my ( $self, $app, $conf ) = @_;

    my $template = Bugzilla::Template->create;
    $template->{_is_main} = 1;

    $app->renderer->add_handler(
        'bugzilla' => sub {
            my ( $renderer, $c, $output, $options ) = @_;
            my %params;

            # Helpers
            foreach my $method ( grep {m/^\w+\z/} keys %{ $renderer->helpers } ) {
                my $sub = $renderer->helpers->{$method};
                $params{$method} = sub { $c->$sub(@_) };
            }

            # Stash values
            $params{$_} = $c->stash->{$_} for grep {m/^\w+\z/} keys %{ $c->stash };
            $params{self} = $params{c} = $c;
            my $name = $options->{template};
            unless ($name =~ /\./) {
                $name = sprintf '%s.%s.tmpl', $options->{template}, $options->{format};
            }
            $template->process( $name, \%params, $output )
                or die $template->error;
        }
    );

    $app->hook(
        around_dispatch => sub {
            my ($next, $c) = @_;
            try {
                local %{ Bugzilla->request_cache } = ();
                local $CGI::Compile::USE_REAL_EXIT = 0;
                # HACK, should just make i_am_cgi smarter.
                local $ENV{'SERVER_SOFTWARE'} = 1;
                Bugzilla->cgi( Bugzilla::Quantum::CGI->new(controller => $c) );
                Bugzilla->template( Bugzilla::Quantum::Template->new( controller => $c, template => $template ) );
                $next->();
            } catch {
                die $_ unless ref $_ eq 'ARRAY' && $_->[0] eq "EXIT\n" || /\bModPerl::Util::exit\b/;
            };
        }
    );
}

1;