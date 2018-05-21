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
}




1;