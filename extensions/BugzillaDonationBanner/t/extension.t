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

use Bugzilla::Config;
use Bugzilla::Constants;
use Bugzilla::Install::Filesystem;
use Bugzilla::User;
use Capture::Tiny qw(capture_merged);
use Test2::V0;

skip_all('BugzillaDonationBanner is disabled')
  unless Bugzilla->has_extension('BugzillaDonationBanner');

my $Ext = 'Bugzilla::Extension::BugzillaDonationBanner';
my $dbh = Bugzilla->dbh;

sub login_as { Bugzilla->set_user(Bugzilla::User->new($_[0]->id)); }

# CGI.pm remembers the first query it parsed from the environment, so build
# each request from an explicit query string instead.
sub with_query {
  my ($query, $code) = @_;
  local Bugzilla->request_cache->{cgi} = Bugzilla::CGI->new($query);
  return $code->();
}

subtest 'extension' => sub {
  is($Ext->NAME, 'BugzillaDonationBanner', 'NAME');
  ok(Bugzilla->has_extension('BugzillaDonationBanner'), 'is loaded');
};

subtest 'parameter panel' => sub {
  my $panels = Bugzilla::Config::param_panels();
  is($panels->{Donation}, "${Ext}::Config", 'panel is registered');

  my ($param)
    = grep { $_->{name} eq 'donation_banner_visibility' }
    "${Ext}::Config"->get_param_list;
  ok($param, 'visibility parameter exists');
  is($param->{default}, 'admins_only', 'defaults to admins_only');
  is($param->{choices}, [qw(admins_only end_users disabled)], 'choices');

  is($param->{checker}->($_, $param), '', "accepts $_")
    for @{$param->{choices}};
  isnt($param->{checker}->('everyone', $param), '', 'rejects an unknown value');
};

subtest 'user settings are registered' => sub {
  my %expect = (
    donate_banner_pref          => 'next_upgrade',
    donate_banner_last_version  => '0.0',
    donate_banner_reminder_date => '1970-01-01',
  );

  capture_merged { $Ext->install_before_final_checks({}) };
  capture_merged { $Ext->install_before_final_checks({}) };

  for my $name (sort keys %expect) {
    my @rows = @{
      $dbh->selectall_arrayref(
        'SELECT default_value, category FROM setting WHERE name = ?',
        undef, $name
      )
    };
    is(scalar @rows, 1, "$name is registered exactly once");
    is($rows[0][0], $expect{$name}, "$name default");
    is($rows[0][1], 'Bugzilla.org', "$name category");
  }

  my $values = $dbh->selectcol_arrayref(
    'SELECT value FROM setting_value WHERE name = ? ORDER BY sortindex',
    undef, 'donate_banner_pref');
  is($values, [qw(next_upgrade specific_date never)],
    'pref has exactly its three options, and no duplicates after a re-run');
};

subtest 'install_filesystem' => sub {
  my %files;
  $Ext->install_filesystem({files => \%files});

  my $dir = bz_locations()->{extensionsdir} . '/BugzillaDonationBanner';
  is([sort keys %files],
    [map {"$dir/$_"}
      qw(bin/donate.cgi web/buggie_watering.svg web/donation-banner.css
      web/donation-banner.js)],
    'registers the script and the web assets');

  ok(-e $_, "$_ exists") for sort keys %files;

  is($files{"$dir/bin/donate.cgi"}{perms},
    Bugzilla::Install::Filesystem::WS_EXECUTE(), 'script is executable');
  is($files{"$dir/web/$_"}{perms},
    Bugzilla::Install::Filesystem::WS_SERVE(), "$_ is served")
    for qw(buggie_watering.svg donation-banner.css donation-banner.js);
};

subtest 'user_preferences_settings hook' => sub {
  my %skip;
  $Ext->user_preferences_settings({skip_settings => \%skip});
  is(\%skip,
    {
      donate_banner_pref          => 1,
      donate_banner_last_version  => 1,
      donate_banner_reminder_date => 1,
    },
    'hides exactly the three donation settings from the Settings tab'
  );

  # An existing entry from another extension must be preserved.
  my %other = (some_other_setting => 1);
  $Ext->user_preferences_settings({skip_settings => \%other});
  is($other{some_other_setting}, 1, 'leaves other extensions entries alone');
};

subtest 'template_before_process hook' => sub {
  my $user = create_user('hook@donation.test', '*');
  login_as($user);
  local Bugzilla->params->{donation_banner_visibility} = 'end_users';

  my %vars;
  $Ext->template_before_process({file => 'index.html.tmpl', vars => \%vars});
  ok(exists $vars{donation}, 'sets donation for the home page template');
  ok($vars{donation},        'and the banner is due for a new user');

  for my $file ('bug/show.html.tmpl', 'reports/index-extra.html.tmpl',
    'account/prefs/prefs.html.tmpl')
  {
    my %other;
    $Ext->template_before_process({file => $file, vars => \%other});
    ok(!exists $other{donation}, "leaves $file alone");
  }
};

subtest 'user_preferences hook' => sub {
  my $old_mode = Bugzilla->error_mode;
  Bugzilla->error_mode(ERROR_MODE_TEST);

  my $user = create_user('prefs@donation.test', '*');
  my $today
    = "${Ext}::Donation"->can('today') ? "${Ext}::Donation"->can('today')->() : '';
  local Bugzilla->params->{donation_banner_visibility} = 'end_users';

  my $call = sub {
    my (%args) = @_;
    my %vars;
    my $handled = 0;
    login_as($user);
    with_query(
      $args{query} // '',
      sub {
        $Ext->user_preferences({
          current_tab  => $args{tab} // 'donate',
          save_changes => $args{save} // 0,
          vars         => \%vars,
          handled      => \$handled,
        });
      }
    );
    return (\%vars, $handled);
  };

  my ($vars, $handled) = $call->(tab => 'account');
  is($handled, 0, 'ignores other tabs');
  is($vars,    {}, 'and does not touch their variables');

  ($vars, $handled) = $call->();
  is($handled,            1,              'handles the donate tab');
  is($vars->{donate_pref}, 'next_upgrade', 'shows the default preference');
  is($vars->{today},       $today,         'provides today');
  is($vars->{reminder_date}, $today,
    'an unset reminder date falls back to today, not the epoch');
  ok($vars->{donation}, 'builds a banner even though it is not dismissed');
  ok(!$vars->{changes_saved}, 'nothing saved on a plain view');

  ($vars, $handled) = $call->(
    save  => 1,
    query => 'donate_banner_pref=specific_date&donate_banner_reminder_date=2030-05-17'
  );
  is($handled,                1,              'handles a save');
  is($vars->{changes_saved},  1,              'reports the save');
  is($vars->{donate_pref},    'specific_date', 'shows the saved preference');
  is($vars->{reminder_date},  '2030-05-17',   'shows the saved date');

  ($vars, $handled) = $call->(save => 1, query => 'donate_banner_pref=never');
  is($vars->{donate_pref}, 'never', 'saves never');

  ($vars, $handled) = $call->(save => 1, query => '');
  is($vars->{donate_pref}, 'next_upgrade', 'a missing preference means next_upgrade');

  like(
    dies {
      $call->(
        save  => 1,
        query => 'donate_banner_pref=specific_date&donate_banner_reminder_date=nope'
      );
    },
    qr/illegal_date/,
    'a bad date is rejected'
  );
  is(Bugzilla::User->new($user->id)->setting('donate_banner_reminder_date'),
    '2030-05-17', 'and does not overwrite the saved date');

  Bugzilla->error_mode($old_mode);
};

done_testing;
