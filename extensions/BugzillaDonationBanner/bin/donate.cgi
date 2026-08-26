#!/usr/bin/env perl

use 5.14.0;
use strict;
use warnings;

use lib qw(../../.. ../../../lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Token qw(check_hash_token);
use Bugzilla::Extension::BugzillaDonationBanner::Donation;

my $cgi = Bugzilla->cgi;
if ($cgi->request_method ne 'POST') {
  ThrowCodeError('illegal_request_method',
    {method => $cgi->request_method, accepted => ['POST']});
}

Bugzilla->login(LOGIN_REQUIRED) unless Bugzilla->user->id;
check_hash_token($cgi->param('token'), ['donation_banner']);

Bugzilla::Extension::BugzillaDonationBanner::Donation::dismiss(
  scalar $cgi->param('donate_action'),
  scalar $cgi->param('donate_banner_reminder_date'),
);

$cgi->base_redirect();
