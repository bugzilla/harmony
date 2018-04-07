# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum;
use Mojo::Base 'Mojolicious';

use Bugzilla::Constants;
use Bugzilla::Quantum::CGI;
use Try::Tiny;

sub startup {
    my ($self) = @_;

    $self->plugin('Bugzilla::Quantum::Plugin::Glue');
    my $r = $self->routes;

    $r->any( '/' )->to('legacy#index_cgi');
    $r->any( '/show_bug.cgi' )->to('legacy#show_bug');
}

1;