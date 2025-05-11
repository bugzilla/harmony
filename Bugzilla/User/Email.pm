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
use Bugzilla::Util;
use Bugzilla::Error;
use Scalar::Util qw(looks_like_number);

#############
# Constants #
#############

use constant DB_TABLE => 'profiles_emails';
use constant NAME_FIELD => 'email';

use constant DB_COLUMNS => qw(
  id
  user_id
  email
  is_primary_email
  display_order
);

use constant VALIDATORS => {
  user_id            => \&_check_user_id,
  email              => \&check_email_for_creation,
  is_primary_email   => \&Bugzilla::Object::check_boolean,
  display_order      => \&_check_display_order,
};

use constant UPDATE_COLUMNS => qw(email is_primary_email display_order);

# There's no gain to caching these objects
use constant USE_MEMCACHED => 0;

###############################
####      Accessors      ######
###############################

sub email   { return $_[0]->{email}; }
sub user_id { return $_[0]->{'user_id'}; }
sub is_primary_email { return $_[0]->{'is_primary_email'}; }

############
# Mutators #
############

sub set_email         { $_[0]->set('email',   $_[1]); }
sub set_primary_email { $_[0]->set('is_primary_email', $_[1]); }
sub set_display_order { $_[0]->set('display_order', $_[1]); }

###############################
####     Constructors     #####
###############################

sub new {
  my ($class, $params) = @_;
  my $email = $class->SUPER::new($params);

  # Return the newly created user email account.
  return $email;
}

sub create {
  my ($class, $params) = @_;
  my $user_email = $class->SUPER::create($params);

  # Return the newly created user email account.
  return $user_email;
}

sub update {
  my ($class, $params) = @_;
  my $updated_email = $class->SUPER::update();

  # Return the updated user email account.
  return $updated_email;
}

sub get_emails_by_user {
    my ($class, $user_id) = @_;
    my $dbh = Bugzilla->dbh;
    my $emails_ref = $dbh->selectall_arrayref("SELECT email, is_primary_email, display_order FROM profiles_emails WHERE user_id = ?",
                                            undef, $user_id);
    return $emails_ref || [];
}

sub get_user_by_email {
    my ($class, $email) = @_;
    my $dbh = Bugzilla->dbh;
    my ($user_id) = $dbh->selectrow_array("SELECT user_id FROM profiles_emails WHERE email = ? LIMIT 1", undef, $email); 
    # We use the defined-or operator because a user_id might be 0 
    return $user_id // 0;
}

sub remove_from_db {
  my $self = shift;
  return $self->is_primary_email ? 0 : $self->SUPER::remove_from_db();
}



###############################
###       Validators        ###
###############################

sub _check_user_id {
  my ($invocant, $id) = @_;
  require Bugzilla::User;
  return Bugzilla::User->check({id => $id})->id;
}

sub check_email_for_creation {
  my ($invocant, $email) = @_;
  
  validate_email_syntax($email)
    || ThrowUserError('illegal_email_address', {addr => $email});
  
  if ($invocant->get_user_by_email($email)) {
    ThrowUserError('email_exists');
  }
 
  return $email;
}

sub _check_display_order { 
  my ($invocant, $value) = @_;
  
  unless (defined $value && looks_like_number($value)) {
        return 0; 
  }
  if ($value == int($value) && $value >= 1) {
        return $value; 
  } else {
        return 0; 
  }
}


1;

__END__
