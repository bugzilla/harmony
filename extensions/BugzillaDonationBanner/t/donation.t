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

BEGIN { $ENV{LOG4PERL_CONFIG_FILE} = 'log4perl-t.conf'; }

use Bugzilla::Test::MockLocalconfig (urlbase => 'http://bugzilla.test');
use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams;
use Bugzilla::Test::Util qw(create_user);

use Bugzilla::Constants;
use Bugzilla::Group;
use Bugzilla::User;
use Capture::Tiny qw(capture_merged);
use DateTime;
use Test2::V0;
use Test2::Tools::Mock qw(mock);

skip_all('BugzillaDonationBanner is disabled')
  unless Bugzilla->has_extension('BugzillaDonationBanner');

my $Ext      = 'Bugzilla::Extension::BugzillaDonationBanner';
my $Donation = "${Ext}::Donation";
require $Donation =~ s{::}{/}gr . '.pm';

my $get_banner = $Donation->can('get_banner');
my $save       = $Donation->can('save_preference');
my $dismiss    = $Donation->can('dismiss');
my $today      = $Donation->can('today');

capture_merged { $Ext->install_before_final_checks({}) };

my $dbh = Bugzilla->dbh;

my $admin = create_user('admin@donation.test', '*');
$dbh->do(
  'INSERT INTO user_group_map (user_id, group_id, isbless, grant_type)
   VALUES (?, ?, 0, ?)', undef,
  $admin->id, Bugzilla::Group->new({name => 'admin'})->id, GRANT_DIRECT
);
my $plain = create_user('plain@donation.test', '*');

sub reload   { return Bugzilla::User->new($_[0]->id); }
sub login_as { Bugzilla->set_user(reload($_[0])); }
sub stored   { return reload($_[0])->setting("donate_banner_$_[1]"); }

# Replace the user's stored donation settings and make them the current user.
sub set_state {
  my ($user, %state) = @_;
  $dbh->do(
    q{DELETE FROM profile_setting
       WHERE user_id = ? AND setting_name LIKE 'donate_banner_%'}, undef,
    $user->id
  );
  login_as($user);
  my $settings = Bugzilla->user->settings;
  $settings->{"donate_banner_$_"}->set($state{$_}) for keys %state;
  return;
}

# These tests need the banner to be due, so default to a never-seen version.
sub due_state { return (pref => 'next_upgrade', last_version => '0.0'); }

is(Bugzilla->params->{donation_banner_visibility},
  'admins_only', 'visibility defaults to admins_only');

subtest 'anonymous users never see a banner' => sub {
  Bugzilla->set_user(Bugzilla::User->new);
  for my $mode (qw(disabled admins_only end_users)) {
    local Bugzilla->params->{donation_banner_visibility} = $mode;
    is($get_banner->(),  undef, "anonymous, $mode");
    is($get_banner->(1), undef, "anonymous, $mode, ignoring preference");
  }
};

subtest 'visibility modes' => sub {
  my @cases = (
    # mode, admin sees it, plain user sees it
    ['disabled',    0, 0],
    ['admins_only', 1, 0],
    ['end_users',   1, 1],
  );
  for my $case (@cases) {
    my ($mode, $admin_sees, $plain_sees) = @$case;
    local Bugzilla->params->{donation_banner_visibility} = $mode;

    for my $ignore (0, 1) {
      my $label = $ignore ? "$mode (ignoring preference)" : $mode;
      set_state($admin, due_state());
      is(!!$get_banner->($ignore), !!$admin_sees, "admin, $label");
      set_state($plain, due_state());
      is(!!$get_banner->($ignore), !!$plain_sees, "plain user, $label");
    }
  }
};

subtest 'visibility note' => sub {
  {
    local Bugzilla->params->{donation_banner_visibility} = 'admins_only';
    set_state($admin, due_state());
    like($get_banner->()->{visibility_note}, qr/only shown .* admin privs/,
      'admins_only note');
  }
  {
    local Bugzilla->params->{donation_banner_visibility} = 'end_users';
    set_state($admin, due_state());
    like($get_banner->()->{visibility_note},
      qr/visible to all logged-in users/, 'end_users note for an admin');
    set_state($plain, due_state());
    is($get_banner->()->{visibility_note}, undef,
      'no note for a non-admin');
  }
};

subtest 'banner data' => sub {
  local Bugzilla->params->{donation_banner_visibility} = 'end_users';
  set_state($plain, due_state());
  my $banner   = $get_banner->();
  my @messages = $Donation->can('BANNER_MESSAGES')->();

  is($banner->{url}, 'https://bugzilla.org/donate', 'donation url');
  ok((grep { $_ eq $banner->{message} } @messages), 'message is a known one');
  like($banner->{token}, qr/^\d+-\S+$/, 'hash token');
  like($banner->{today}, qr/^\d{4}-\d\d-\d\d$/, 'today is an ISO date');
  is($banner->{today}, $today->(), 'today matches today()');
  like($banner->{settings_link}, qr/section=donation/, 'settings link');
};

subtest 'next_upgrade preference' => sub {
  local Bugzilla->params->{donation_banner_visibility} = 'end_users';
  my $current = BUGZILLA_VERSION;

  set_state($admin, pref => 'next_upgrade', last_version => '0.0');
  my $banner = $get_banner->();
  ok($banner,                 'shown when never dismissed');
  ok(!$banner->{show_thanks}, 'no thanks for a fresh install');

  set_state($admin, pref => 'next_upgrade', last_version => '0');
  ok(!$get_banner->()->{show_thanks}, 'no thanks for last_version 0');

  set_state($admin, pref => 'next_upgrade', last_version => '4.0');
  ok($get_banner->()->{show_thanks}, 'admin is thanked after an upgrade');

  set_state($plain, pref => 'next_upgrade', last_version => '4.0');
  ok($get_banner->(),                 'non-admin sees it after an upgrade');
  ok(!$get_banner->()->{show_thanks}, 'non-admin is not thanked');

  set_state($admin, pref => 'next_upgrade', last_version => $current);
  is($get_banner->(), undef, 'hidden on the version it was dismissed');
  ok($get_banner->(1), 'still built when ignoring the preference');
};

subtest 'specific_date preference' => sub {
  local Bugzilla->params->{donation_banner_visibility} = 'end_users';
  my $now = $today->();

  my %cases = (
    'a past date'  => ['2000-01-01', 1],
    'today'        => [$now,         1],
    'a future date' => ['2999-12-31', 0],
  );
  for my $label (sort keys %cases) {
    my ($date, $due) = @{$cases{$label}};
    set_state($admin, pref => 'specific_date', reminder_date => $date);
    is(!!$get_banner->(), !!$due, "reminder on $label");
    ok($get_banner->(1), "reminder on $label, ignoring preference");
  }
};

subtest 'never preference' => sub {
  local Bugzilla->params->{donation_banner_visibility} = 'end_users';
  set_state($admin, pref => 'never');
  is($get_banner->(), undef, 'hidden');
  ok($get_banner->(1), 'still built when ignoring the preference');
};

subtest 'save_preference' => sub {
  my $old_mode = Bugzilla->error_mode;
  Bugzilla->error_mode(ERROR_MODE_TEST);

  for my $pref (qw(next_upgrade never)) {
    set_state($admin, pref => 'specific_date', last_version => '1.0');
    $save->($pref, '');
    is(stored($admin, 'pref'), $pref, "stores $pref");
    is(stored($admin, 'last_version'), BUGZILLA_VERSION,
      "$pref stamps the current version");
  }

  set_state($admin, pref => 'never', last_version => '1.0');
  $save->('specific_date', '2030-05-17');
  is(stored($admin, 'pref'),          'specific_date', 'stores specific_date');
  is(stored($admin, 'reminder_date'), '2030-05-17',    'stores the date');
  is(stored($admin, 'last_version'),  BUGZILLA_VERSION, 'stamps the version');

  for my $bad ('', 'not-a-date', '2030-02-30') {
    set_state($admin, pref => 'never', last_version => '1.0');
    like(dies { $save->('specific_date', $bad) },
      qr/illegal_date/, "rejects date '$bad'");
    is(stored($admin, 'pref'),         'never', 'pref unchanged');
    is(stored($admin, 'last_version'), '1.0',   'version unchanged');
  }

  set_state($admin, pref => 'never', last_version => '1.0');
  like(dies { $save->('bogus', '') }, qr/invalid_parameter/,
    'rejects an unknown preference');
  is(stored($admin, 'pref'),         'never', 'pref unchanged');
  is(stored($admin, 'last_version'), '1.0',   'version unchanged');

  Bugzilla->error_mode($old_mode);
};

subtest 'dismiss' => sub {
  my $old_mode = Bugzilla->error_mode;
  Bugzilla->error_mode(ERROR_MODE_TEST);

  # Dec 28 keeps both the week and the month offsets across a year boundary.
  my $clock = mock 'DateTime' => (override => [
    now => sub {
      return DateTime->new(
        year => 2026, month => 12, day => 28, hour => 12,
        time_zone => 'UTC'
      );
    },
  ]);
  is($today->(), '2026-12-28', 'clock is frozen');

  set_state($admin, due_state());
  $dismiss->('week');
  is(stored($admin, 'pref'),          'specific_date', 'week: pref');
  is(stored($admin, 'reminder_date'), '2027-01-04',    'week: +7 days');
  is(stored($admin, 'last_version'),  BUGZILLA_VERSION, 'week: version');

  set_state($admin, due_state());
  $dismiss->('month');
  is(stored($admin, 'pref'),          'specific_date', 'month: pref');
  is(stored($admin, 'reminder_date'), '2027-01-27',    'month: +30 days');

  set_state($admin, due_state());
  $dismiss->('date', '2031-02-03');
  is(stored($admin, 'pref'),          'specific_date', 'date: pref');
  is(stored($admin, 'reminder_date'), '2031-02-03',    'date: chosen date');

  set_state($admin, due_state());
  like(dies { $dismiss->('date', 'garbage') }, qr/illegal_date/,
    'date: rejects a bad date');
  is(stored($admin, 'pref'), 'next_upgrade', 'date: pref unchanged on error');

  set_state($admin, pref => 'specific_date', last_version => '1.0');
  $dismiss->('next_upgrade');
  is(stored($admin, 'pref'),         'next_upgrade',  'next_upgrade: pref');
  is(stored($admin, 'last_version'), BUGZILLA_VERSION, 'next_upgrade: version');

  set_state($admin, due_state());
  $dismiss->('never');
  is(stored($admin, 'pref'), 'never', 'never: pref');

  set_state($admin, pref => 'never', last_version => '1.0',
    reminder_date => '2020-01-01');
  $dismiss->('bogus');
  is(stored($admin, 'pref'),          'never',      'unknown action: pref');
  is(stored($admin, 'last_version'),  '1.0',        'unknown action: version');
  is(stored($admin, 'reminder_date'), '2020-01-01', 'unknown action: date');

  Bugzilla->error_mode($old_mode);
};

done_testing;
