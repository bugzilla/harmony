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


use constant DB_COLUMNS => qw(
  profiles_emails.id
  profiles_emails.user_id
  profiles_emails.email
  profiles_emails.is_primary_email
);


use constant VALIDATORS => {
  user_id            => \&_check_user_id,
  email              => \&_check_email,
  is_primary_email   => \&Bugzilla::Object::check_boolean,
};


sub create {
  my ($class, $params) = @_;
  my $user_email = $class->SUPER::create($params);

  # Return the newly created user email account.
  return $user_email;
}

###############################
###       Validators        ###
###############################

sub _check_user_id {
return 1;
}
sub _check_email {
return 1;
}
1;

__END__
