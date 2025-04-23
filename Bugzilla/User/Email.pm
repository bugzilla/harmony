# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::User::Email;

use 5.10.1;
use strict;
use warnings;

use base qw(Bugzilla::Object);

use Bugzilla::Constants;

#############
# Constants #
#############

use constant DB_TABLE => 'profiles_emails';


sub create {
  my ($class, $params) = @_;
  my $user_email = $class->SUPER::create($params);


  # Return the newly created user email account.
  return $user_email;
}
1;

__END__
