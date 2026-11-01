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
use Bugzilla::User;
use Capture::Tiny qw(capture_merged);
use Mojo::DOM;
use Test2::V0;

skip_all('BugzillaDonationBanner is disabled')
  unless Bugzilla->has_extension('BugzillaDonationBanner');

my $Ext      = 'Bugzilla::Extension::BugzillaDonationBanner';
my $Donation = "${Ext}::Donation";
my $dismiss  = $Donation->can('dismiss');

my $evil_message = q{<script>alert("m")</script> & <b>bold</b>};
my $evil_url     = q{https://example.test/?a=1&b="><img src=x onerror=alert(1)>};

sub render {
  my (%vars) = @_;
  my $out = '';
  Bugzilla->template->process('donation/banner.html.tmpl', \%vars, \$out)
    or die 'template error: ' . Bugzilla->template->error;
  return Mojo::DOM->new($out);
}

# Boolean attributes such as "hidden" have no value, so check the tag itself.
sub has_attr {
  my ($el, $name) = @_;
  return $el->to_string =~ m{^<[^>]*\s\Q$name\E(?=[\s=>/])} ? 1 : 0;
}

sub banner {
  return {
    url             => 'https://bugzilla.org/donate',
    message         => 'Support the people who keep Bugzilla running.',
    show_thanks     => 0,
    token           => '1700000000-abc_DEF-123',
    today           => '2026-11-01',
    settings_link   => 'editparams.cgi?section=donation#donation_banner_visibility_desc',
    @_,
  };
}

subtest 'nothing is rendered without banner data' => sub {
  for my $dismissal (0, 1) {
    my $dom = render(donation => undef, show_dismissal => $dismissal);
    is($dom->all_text =~ s/\s+//gr, '', "no text (show_dismissal=$dismissal)");
    is($dom->find('div,link,script,form,a')->size, 0, 'no elements');
  }
};

subtest 'parts common to both contexts' => sub {
  for my $dismissal (0, 1) {
    my $dom = render(donation => banner(), show_dismissal => $dismissal);
    my $ctx = "show_dismissal=$dismissal";

    like($dom->at('link[rel=stylesheet]')->attr('href'),
      qr{extensions/BugzillaDonationBanner/web/donation-banner\.css$},
      "stylesheet is loaded with the banner ($ctx)");
    is($dom->find('link[rel=stylesheet]')->size, 1, "only one stylesheet ($ctx)");

    like($dom->at('img.donation_banner_image')->attr('src'),
      qr{extensions/BugzillaDonationBanner/web/buggie_watering\.svg$}, "image ($ctx)");
    ok(length $dom->at('img.donation_banner_image')->attr('alt'), "alt text ($ctx)");

    my $cta = $dom->at('a.donation_banner_cta');
    is($cta->attr('href'), 'https://bugzilla.org/donate', "donate link ($ctx)");
    is($cta->attr('rel'),  'noreferrer', "donate link is noreferrer ($ctx)");
    is($cta->text, 'Donate to Bugzilla', "donate link text ($ctx)");

    is($dom->at('.donation_banner_message')->text,
      'Support the people who keep Bugzilla running.', "message ($ctx)");
    ok($dom->at('.donation_banner.home_banner'), "banner classes ($ctx)");
  }
};

subtest 'home page context shows the dismissal controls' => sub {
  my $dom = render(donation => banner(), show_dismissal => 1);

  ok(!$dom->at('.donation_banner_preferences'), 'no preferences-page class');

  my $script = $dom->at('script');
  like($script->attr('src'),
    qr{extensions/BugzillaDonationBanner/web/donation-banner\.js$}, 'script is loaded');
  ok(has_attr($script, 'defer'), 'script is deferred');

  my $details = $dom->at('details.donation_banner_dismissal');
  ok($details, 'controls live in a disclosure');
  ok(!has_attr($details, 'open'), 'which starts collapsed');

  my $form = $details->at('form');
  is($form->attr('method'), 'post', 'form posts');
  like($form->attr('action'),
    qr{extensions/BugzillaDonationBanner/bin/donate\.cgi$}, 'to the extension script');
  is($form->at('input[type=hidden][name=token]')->attr('value'),
    '1700000000-abc_DEF-123', 'carries the token');

  my $select = $form->at('select[name=donate_action]');
  ok(has_attr($select, 'required'), 'an action is required');
  is($select->find('option')->map(attr => 'value')->to_array,
    ['', qw(next_upgrade week month date never)], 'offers every reminder choice');
  ok(has_attr($select->at('option[value=""]'), 'disabled'),
    'the placeholder cannot be submitted');

  my $date = $form->at('#donate_banner_date_field');
  ok(has_attr($date, 'hidden'), 'date picker starts hidden');
  my $input = $date->at('input[type=date][name=donate_banner_reminder_date]');
  is($input->attr('value'), '2026-11-01', 'date picker defaults to today');

  ok($form->at('button[type=submit]'), 'has a submit button');

  my $note = $details->at('p.donation_banner_preferences_note a');
  like($note->attr('href'), qr{userprefs\.cgi\?tab=donate$},
    'points back to the Donate preferences');
};

subtest 'preferences page context has no dismissal controls' => sub {
  my $dom = render(donation => banner(), show_dismissal => 0);

  ok($dom->at('.donation_banner_preferences'), 'has the preferences-page class');
  is($dom->find('form')->size,    0, 'no form');
  is($dom->find('script')->size,  0, 'no script');
  is($dom->find('details')->size, 0, 'no disclosure');
  is($dom->find('input,select,button')->size, 0, 'no controls');
};

subtest 'every offered choice is one dismiss() handles' => sub {
  my $old_mode = Bugzilla->error_mode;
  Bugzilla->error_mode(ERROR_MODE_TEST);
  capture_merged { $Ext->install_before_final_checks({}) };

  my $user = create_user('choices@donation.test', '*');
  my @choices
    = grep {length}
    @{render(donation => banner(), show_dismissal => 1)
      ->find('select[name=donate_action] option')->map(attr => 'value')->to_array};
  is(scalar @choices, 5, 'five choices');

  for my $choice (@choices) {
    Bugzilla->set_user(Bugzilla::User->new($user->id));
    Bugzilla->user->settings->{donate_banner_last_version}->set('1.0');
    Bugzilla->set_user(Bugzilla::User->new($user->id));

    $dismiss->($choice, '2030-01-01');

    is(Bugzilla::User->new($user->id)->setting('donate_banner_last_version'),
      BUGZILLA_VERSION, "'$choice' is acted on rather than ignored");
  }

  Bugzilla->error_mode($old_mode);
};

subtest 'banner extras' => sub {
  my $thanks = render(donation => banner(show_thanks => 1), show_dismissal => 1);
  like($thanks->at('.donation_banner_thanks')->text, qr/Thanks for upgrading/,
    'thanks line when show_thanks');
  ok(!render(donation => banner(), show_dismissal => 1)
      ->at('.donation_banner_thanks'), 'no thanks line otherwise');

  my $noted = render(
    donation        => banner(visibility_note => 'Only admins see this.'),
    show_dismissal  => 1
  );
  like($noted->at('p.notice')->text, qr/Only admins see this\./, 'visibility note');
  like($noted->at('p.notice a')->attr('href'),
    qr{editparams\.cgi\?section=donation#donation_banner_visibility_desc$},
    'links to the admin parameter');
  ok(!render(donation => banner(), show_dismissal => 1)->at('p.notice'),
    'no note when there is none');
};

subtest 'output is escaped' => sub {
  for my $dismissal (0, 1) {
    my $dom = render(
      donation => banner(
        message         => $evil_message,
        url             => $evil_url,
        token           => q{"><script>alert(2)</script>},
        visibility_note => q{<i>note</i>},
      ),
      show_dismissal => $dismissal,
    );
    my $ctx = "show_dismissal=$dismissal";

    is($dom->at('.donation_banner_message')->text, $evil_message,
      "message is shown as text ($ctx)");
    is($dom->at('.donation_banner_message')->children->size, 0,
      "message adds no elements ($ctx)");
    is($dom->at('a.donation_banner_cta')->attr('href'), $evil_url,
      "url survives as one attribute ($ctx)");
    ok(!$dom->at('a.donation_banner_cta')->attr('onerror'), "url injects no attribute ($ctx)");
    is($dom->find('img')->size, 1, "url injects no element ($ctx)");
    is($dom->at('p.notice')->children->first->tag, 'a',
      "note markup is escaped ($ctx)");

    if ($dismissal) {
      is($dom->at('input[name=token]')->attr('value'),
        q{"><script>alert(2)</script>}, "token cannot break out ($ctx)");
      is($dom->find('script')->size, 1, "only our own script element ($ctx)");
    }
  }
};

done_testing;
