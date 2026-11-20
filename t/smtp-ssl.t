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
use Capture::Tiny qw(capture_merged);
use Bugzilla::Test::MockParams (mail_delivery_method => 'SMTP');
use Bugzilla::Mailer;

subtest 'defaults build an SMTP transport' => sub {
  is(Bugzilla->params->{smtp_ssl}, 'none', 'smtp_ssl defaults to none');
  my $transport = eval { Bugzilla::Mailer::_smtp_transport('localhost') };
  is($@, '', 'building the transport does not die');
  isa_ok($transport, 'Email::Sender::Transport::SMTP');
};

subtest 'smtp_ssl maps to the Email::Sender ssl value' => sub {
  my %expect = (none => 0, starttls => 'starttls', ssl => 'ssl');
  foreach my $value (sort keys %expect) {
    Bugzilla::Test::MockParams->import(smtp_ssl => $value);
    my $transport = Bugzilla::Mailer::_smtp_transport('localhost');
    is($transport->ssl, $expect{$value}, "smtp_ssl $value");
  }
};

subtest 'update_params converts 5.x boolean smtp_ssl' => sub {
  # The last three are a rerun on already-converted params: no change.
  my %expect = ('1' => 'ssl', '0' => 'none', '' => 'none',
    'none' => 'none', 'starttls' => 'starttls', 'ssl' => 'ssl');
  foreach my $old (sort keys %expect) {

    # Keep the legacy file to smtp_ssl only: the DB-free mocks that
    # MockParams installs during import are not active here.
    $Bugzilla::Test::MockParams::Params = "%param = ('smtp_ssl' => '$old');";
    capture_merged { Bugzilla::Config::update_params() };
    my $new = Bugzilla::Config::read_param_file();
    is($new->{smtp_ssl}, $expect{$old}, "old value '$old'");
  }
};

done_testing;
