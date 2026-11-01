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

BEGIN {
  $ENV{LOG4PERL_CONFIG_FILE}     = 'log4perl-t.conf';
  $ENV{BUGZILLA_DISABLE_HOSTAGE} = 1;
}

# Must load before any Bugzilla code so that exit() inside it can be caught.
use CGI::Compile;

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bugzilla.test');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;
use Bugzilla::Test::Util qw(create_user);

use Bugzilla::Constants;
use Bugzilla::Token qw(issue_hash_token);
use Bugzilla::User;
use Capture::Tiny qw(capture_merged);
use Test2::V0;
use Test::Mojo;

skip_all('BugzillaDonationBanner is disabled')
  unless Bugzilla->has_extension('BugzillaDonationBanner');

my $Ext = 'Bugzilla::Extension::BugzillaDonationBanner';
my $url = '/extensions/BugzillaDonationBanner/bin/donate.cgi';

capture_merged { $Ext->install_before_final_checks({}) };

my $user = create_user('route@donation.test', '*');

# Web pages authenticate with the same cookies a browser sends.
my $cookie = 'ABCDEFGHIJKLMNOPQRSTUV';
Bugzilla->dbh->do(
  'INSERT INTO logincookies (cookie, userid, ipaddr, lastused)
   VALUES (?, ?, ?, CURRENT_TIMESTAMP)', undef, $cookie, $user->id, '127.0.0.1'
);
my $login = {Cookie => 'Bugzilla_login=' . $user->id . "; Bugzilla_logincookie=$cookie"};

sub fresh      { return Bugzilla::User->new($user->id); }
sub stored     { return fresh()->setting("donate_banner_$_[0]"); }
sub reset_user {
  Bugzilla->dbh->do(
    q{DELETE FROM profile_setting
       WHERE user_id = ? AND setting_name LIKE 'donate_banner_%'},
    undef, $user->id
  );
}
sub token_for_user {
  Bugzilla->set_user(fresh());
  return issue_hash_token(['donation_banner']);
}

my $t = Test::Mojo->new('Bugzilla::App');
$t->ua->max_redirects(0);

reset_user();

subtest 'only POST is routed' => sub {
  for my $method (qw(get head put delete patch)) {
    my $call = "${method}_ok";
    $t->$call($url)->status_is(404, uc($method) . ' has no route');
  }
  is(stored('pref'), 'next_upgrade', 'nothing changed');
};

subtest 'POST without logging in changes nothing' => sub {
  my $token = token_for_user();
  $t->post_ok($url => form => {donate_action => 'never', token => $token});
  isnt($t->tx->res->code, 302, 'does not redirect as though it succeeded');
  is(stored('pref'), 'next_upgrade', 'preference unchanged');
  is(stored('last_version'), '0.0', 'version unchanged');
};

subtest 'the login cookies are accepted' => sub {
  $t->get_ok('/home' => $login)->status_is(200)
    ->content_like(qr/Log Out|logout/i, 'the page sees a logged-in user');
};

subtest 'POST with a bad token changes nothing' => sub {
  for my $token (undef, '', 'garbage', '1-abcdef') {
    $t->post_ok(
      $url => $login => form =>
        {donate_action => 'never', (defined $token ? (token => $token) : ())}
    );
    isnt($t->tx->res->code, 302,
      'does not redirect as though it succeeded (' . ($token // 'no token') . ')');
    is(stored('pref'), 'next_upgrade', 'preference unchanged');
  }
};

subtest 'a token for another user is refused' => sub {
  my $other = create_user('other@donation.test', '*');
  Bugzilla->set_user(Bugzilla::User->new($other->id));
  my $token = issue_hash_token(['donation_banner']);
  $t->post_ok(
    $url => $login => form => {donate_action => 'never', token => $token}
  );
  isnt($t->tx->res->code, 302, 'does not redirect as though it succeeded');
  is(stored('pref'), 'next_upgrade', 'preference unchanged');
};

subtest 'the script itself refuses anything but POST' => sub {

  # The router already rejects these, so reach the script through a test-only
  # route to prove the fallback holds if that route is ever loosened.
  $t->app->routes->any('/donate-probe')
    ->to('CGI#bugzilla_donation_banner_cgi');

  my $token = token_for_user();
  for my $method (qw(get head put delete)) {
    my $call = "${method}_ok";
    $t->$call("/donate-probe?donate_action=never&token=$token" => $login);
    is($t->tx->res->code, 405, uc($method) . ' gets 405 Method Not Allowed');
    is($t->tx->res->headers->header('Allow'), 'POST', 'and is told to use POST');
    is(stored('pref'), 'next_upgrade',
      uc($method) . ' with valid credentials and token changes nothing');
  }
};

subtest 'POST with a login and a valid token dismisses the banner' => sub {
  my $token = token_for_user();
  $t->post_ok(
    $url => $login => form => {donate_action => 'never', token => $token});
  $t->status_is(302);
  is(stored('pref'), 'never', 'preference stored');
  is(stored('last_version'), BUGZILLA_VERSION, 'version stamped');
};

done_testing;
