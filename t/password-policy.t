#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
use 5.14.0;
use strict;
use warnings;
use lib qw( . lib local/lib/perl5 );

use Test::More;
use Test2::Tools::Mock qw(mock);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');

# Avoid rendering the error templates when a password is rejected; see
# Bugzilla::Error, which just dies with a Dumper() of the error vars
# when the error mode is ERROR_MODE_TEST.
Bugzilla->usage_mode(USAGE_MODE_TEST);

# What the mocked password_check hook should do to $reason, for tests
# that want to simulate an extension. undef means "do nothing".
my $hook_sets_reason;

my $hook_mock = mock 'Bugzilla::Hook' => (
  override => [
    process => sub {
      my ($name, $args) = @_;
      return unless $name eq 'password_check';
      ${$args->{reason}} = $hook_sets_reason if defined $hook_sets_reason;
    },
  ],
);

# Calls assert_password_is_secure and returns (1, undef) if it was
# accepted, or (0, $reason) if it was rejected.
sub check_password {
  my ($password) = @_;
  my $ok = eval { Bugzilla->assert_password_is_secure($password); 1 };
  return (1, undef) if $ok;
  my ($reason) = $@ =~ /'reason'\s*=>\s*'([^']*)'/;
  return (0, $reason);
}

subtest 'no_constraints applies no checks' => sub {
  Bugzilla::Test::MockParams->import(password_complexity => 'no_constraints');
  $hook_sets_reason = undef;

  my ($ok, $reason) = check_password('a');
  ok($ok, 'a 1-character password is accepted') or diag("reason: $reason");
};

subtest 'bmo rejects a password that is too short' => sub {
  Bugzilla::Test::MockParams->import(password_complexity => 'bmo');
  $hook_sets_reason = undef;

  my ($ok, $reason) = check_password('Ab1!');
  ok(!$ok, 'short password is rejected');
  is($reason, 'too short', 'rejected for being too short');
};

subtest 'bmo rejects a long but simple password' => sub {
  Bugzilla::Test::MockParams->import(password_complexity => 'bmo');
  $hook_sets_reason = undef;

  my ($ok, $reason) = check_password('aaaaaaaaaaaaaaaa');
  ok(!$ok, 'long, single-character-class password is rejected');
  is($reason, 'not complex enough', 'rejected for not being complex enough');
};

subtest 'bmo accepts a complex password' => sub {
  Bugzilla::Test::MockParams->import(password_complexity => 'bmo');
  $hook_sets_reason = undef;

  my ($ok, $reason) = check_password('Password1!');
  ok($ok, 'a password meeting 3 of 5 features is accepted')
    or diag("reason: $reason");
};

subtest 'a hook can reject a password the core check accepted' => sub {
  Bugzilla::Test::MockParams->import(password_complexity => 'no_constraints');
  $hook_sets_reason = 'extension says no';

  my ($ok, $reason) = check_password('anything goes');
  ok(!$ok, 'password rejected by the hook');
  is($reason, 'extension says no', 'hook reason is used');
};

subtest 'a hook cannot clear a core rejection' => sub {
  Bugzilla::Test::MockParams->import(password_complexity => 'bmo');

  # Even a hook that actively tries to clear the rejection must not be
  # consulted once the core check has already rejected the password.
  $hook_sets_reason = '';

  my ($ok, $reason) = check_password('Ab1!');
  ok(!$ok, 'password is still rejected');
  is($reason, 'too short', 'core rejection reason is preserved');
};

done_testing;
