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

use Bugzilla::Test::MockDB;
use Bugzilla::Test::MockParams (password_complexity => 'no_constraints');

use Test2::V0;
use URI;

use Bugzilla;
BEGIN { Bugzilla->extensions }

my $Ext = 'Bugzilla::Extension::MoreBugUrl';

# Each entry: matcher class, URLs it must handle, URLs it must not handle.
my %cases = (
  BitBucket => {
    yes => ['https://bitbucket.org/user/project/issue/1234'],
    no  => [
      'https://example.com/user/project/issue/1234',
      'https://bitbucket.org/user/project/pull-requests/1234',
    ],
  },
  PHP => {
    yes => ['https://bugs.php.net/bug.php?id=1234'],
    no  => [
      'https://bugs.php.net/bug.php?id=abc',
      'https://example.com/bug.php?id=1234',
      'https://bugs.php.net/other.php?id=1234',
    ],
  },
  Redmine => {
    yes => ['https://demo.redmine.example/issues/111'],
    no  => ['https://demo.redmine.example/issues/', 'https://demo.redmine.example/issues/abc'],
  },
  ReviewBoard => {
    yes => ['https://reviews.example/r/1234', 'https://reviews.example/r/1234/'],
    no  => ['https://reviews.example/r/', 'https://reviews.example/r/abc'],
  },
  RT => {
    yes => ['https://rt.example/Ticket/Display.html?id=1234'],
    no  => [
      'https://rt.example/Ticket/Display.html?id=abc',
      'https://rt.example/Ticket/Display.html',
      'https://rt.example/Ticket/Other.html?id=1234',
    ],
  },
  Savane => {
    yes => ['https://savannah.example/bugs/?1234', 'https://savannah.example/bugs/index.php?1234'],
    no  => ['https://savannah.example/bugs/?abc', 'https://savannah.example/support/?1234'],
  },
  WineHQForums => {
    yes => ['https://forum.winehq.org/viewtopic.php?f=8&t=1234'],
    no  => [
      'https://forum.winehq.org/viewtopic.php?f=8',
      'https://forum.winehq.org/viewtopic.php?f=a&t=1234',
      'https://example.com/viewtopic.php?f=8&t=1234',
    ],
  },
);

foreach my $name (sort keys %cases) {
  my $class = "${Ext}::${name}";
  subtest $name => sub {
    ok(eval "require $class; 1", "$class loads") or diag($@);
    isa_ok($class, ['Bugzilla::BugUrl'], "$class is a BugUrl sub-class");
    foreach my $url (@{$cases{$name}{yes}}) {
      is($class->should_handle(URI->new($url)), 1, "handles $url");
    }
    foreach my $url (@{$cases{$name}{no}}) {
      is($class->should_handle(URI->new($url)), 0, "does not handle $url");
    }
  };
}

subtest 'extension registers its sub-classes with the hook' => sub {
  my @sub_classes = Bugzilla::BugUrl->SUB_CLASSES;
  Bugzilla::Hook::process('bug_url_sub_classes', {sub_classes => \@sub_classes});
  foreach my $name (sort keys %cases) {
    ok((grep { $_ eq "${Ext}::${name}" } @sub_classes), "$name is registered");
  }
};

subtest 'class_for resolves URLs through the hook' => sub {
  is(Bugzilla::BugUrl->class_for('https://bugs.php.net/bug.php?id=1234'),
    "${Ext}::PHP", 'PHP URL resolves to the PHP sub-class');
};

subtest 'invalid URL error page lists the extension trackers' => sub {
  my $output = '';
  Bugzilla->template->process(
    'global/user-error.html.tmpl',
    {
      error       => 'bug_url_invalid',
      reason      => 'show_bug',
      url         => 'http://example.com/nope',
      field_descs => {see_also => 'See Also'},
      user        => Bugzilla->user,
      constants   => {},
    },
    \$output
  ) or diag(Bugzilla->template->error);
  like($output, qr/Review Board review request/, 'tracker list comes from the hook');
};

done_testing;
