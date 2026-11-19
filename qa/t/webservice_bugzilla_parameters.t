# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##########################################
# Test for xmlrpc call to:               #
# Bugzilla.parameters()                  #
##########################################

use strict;
use warnings;
use lib qw(lib ../../lib ../../local/lib/perl5);
use Test::More tests => 114;
use QA::Util;
my ($config, @clients) = get_rpc_clients();

use constant MASK => '********';

my @logged_out = qw(maintainer requirelogin);

my @logged_in = qw(
  allowemailchange
  attachment_base
  commentonchange_resolution
  commentonduplicate
  default_bug_type
  defaultopsys
  defaultplatform
  defaultpriority
  defaultseverity
  duplicate_or_move_bug_status
  emailregexpdesc
  emailsuffix
  letsubmitterchoosemilestone
  letsubmitterchoosepriority
  mailfrom
  maintainer
  maxattachmentsize
  musthavemilestoneonaccept
  noresolveonopenblockers
  password_complexity
  rememberlogin
  require_bug_type
  requirelogin
  search_allow_no_criteria
  urlbase
  use_regression_fields
  use_see_also
  useclassification
  usemenuforusers
  useqacontact
  usestatuswhiteboard
  usetargetmilestone
);

# Core parameters, always defined.
my @core_secrets = qw(
  LDAPbinddn
  RADIUS_secret
  aws_secret_access_key
  duo_akey
  duo_ikey
  duo_skey
  smtp_password
);

# Defined only when the extension is enabled.
my @extension_secrets = qw(
  bitly_token
  github_client_secret
  honeypot_api_key
  phabricator_api_key
);

# Anonymous must run first, before any login on the client.
my @users = ('', 'unprivileged', 'tweakparams', 'admin');

foreach my $rpc (@clients) {
  foreach my $user (@users) {
    $rpc->bz_log_in($user) if $user;
    my $who = $user || 'Logged-out user';

    my $call   = $rpc->bz_call_success('Bugzilla.parameters');
    my $params = $call->result->{parameters};

    if (!$user) {
      is_deeply(
        [sort keys %$params],
        [sort @logged_out],
        "$who sees only the logged-out parameters"
      );
    }
    elsif ($user eq 'unprivileged') {
      is_deeply(
        [sort keys %$params],
        [sort @logged_in],
        "$who sees only the logged-in parameters"
      );
    }
    else {
      foreach my $name (@core_secrets) {
        is($params->{$name}, MASK, "$who gets $name masked");
      }
      foreach my $name (@extension_secrets) {
        ok(!exists $params->{$name} || $params->{$name} eq MASK,
          "$who gets $name masked or absent");
      }
      foreach my $name (qw(urlbase attachment_base)) {
        ok(exists $params->{$name}, "$who sees $name");
      }
      cmp_ok(scalar(keys %$params),
        '>', scalar(@logged_in), "$who sees more parameters than a logged-in user");
    }
  }
}
