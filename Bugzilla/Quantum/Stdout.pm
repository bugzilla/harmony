# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Stdout;
use 5.10.1;
use Moo;

has 'controller' => (
    is       => 'ro',
    required => 1,
);

sub TIEHANDLE { ## no critic (unpack)
    my $class = shift;

    return $class->new(@_);
}

sub PRINTF { ## no critic (unpack)
    my $self = shift;
    $self->PRINT(sprintf @_);
}

sub PRINT { ## no critic (unpack)
    my $self = shift;

    foreach my $chunk (@_) {
        my $str = "$chunk";
        utf8::encode($str);
        $self->controller->write($str);
    }
}

sub BINMODE {
    # no-op
}

1;