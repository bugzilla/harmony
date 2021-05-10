# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::DB::QuoteExpression::Hash;

use 5.10.1;
use Moo;

has 'qe' => (is => 'ro', required => 1);

extends 'Tie::StdHash';

sub TIEHASH {
  my $class = shift;

  return $class->new(@_);
}


sub FETCH {
  my ($self, $key) = @_;

  return $self->qe->quote_expr($key);
}

1;
