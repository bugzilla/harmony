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
use Bugzilla::Test::MockParams (mail_delivery_method => 'SMTP');
use Bugzilla::Mailer;
use Bugzilla::Config::Common;
use Email::Sender::Failure;
use HTTP::Response;
use JSON::MaybeXS qw(encode_json);
use LWP::UserAgent;

# Secrets used below; none of them may appear in an error message.
my $SECRET  = 'client-secret-XYZ';
my $REFRESH = 'refresh-token-XYZ';
my $ACCESS  = 'access-token-XYZ';

my (@posts, $response);
my $lwp = mock 'LWP::UserAgent' => (
  override => [
    post => sub {
      my ($self, $url, $form) = @_;
      push @posts, {url => $url, form => {%$form}};
      return $response;
    },
  ],
);

sub respond {
  my ($code, $data) = @_;
  $response = HTTP::Response->new(
    $code,
    $code == 200 ? 'OK' : 'Bad Request',
    ['Content-Type' => 'application/json'],
    ref $data ? encode_json($data) : $data
  );
}

sub set_params {
  my %new = @_;
  Bugzilla->params->{$_} = $new{$_} for keys %new;
}

sub reset_state {
  @posts = ();
  delete Bugzilla->process_cache->{smtp_oauth2};
}

set_params(
  smtp_username             => 'bugs@example.com',
  smtp_password             => 'mail-password',
  smtp_oauth2_token_url     => 'https://oauth.example.com/token',
  smtp_oauth2_client_id     => 'client-id',
  smtp_oauth2_client_secret => $SECRET,
  smtp_oauth2_refresh_token => $REFRESH,
);

sub token { Bugzilla::Mailer::_smtp_oauth2_token() }

subtest 'password path is unchanged' => sub {
  set_params(smtp_auth_method => 'password');
  my $transport = Bugzilla::Mailer::_smtp_transport('localhost');
  is($transport->sasl_username, 'bugs@example.com', 'sasl_username passed');
  is($transport->sasl_password, 'mail-password',    'sasl_password passed');
  ok(!$transport->sasl_authenticator, 'no sasl_authenticator');
};

subtest 'token request, cache hit, near-expiry refresh' => sub {
  reset_state();
  respond(200, {access_token => $ACCESS, expires_in => 3600});
  is(token(), $ACCESS, 'returns the access token');
  is(scalar @posts, 1, 'one POST');
  is($posts[0]{url}, 'https://oauth.example.com/token', 'POST to token_url');
  is_deeply(
    $posts[0]{form},
    {
      grant_type    => 'refresh_token',
      client_id     => 'client-id',
      client_secret => $SECRET,
      refresh_token => $REFRESH,
    },
    'POST form fields'
  );

  is(token(), $ACCESS, 'second call returns the token');
  is(scalar @posts, 1, 'second call is a cache hit');

  Bugzilla->process_cache->{smtp_oauth2}{expires} = time() + 299;
  respond(200, {access_token => 'access-2', expires_in => 3600});
  is(token(), 'access-2', 'under 300s left: refreshed');
  is(scalar @posts, 2, 'refresh made a POST');
};

subtest 'param change invalidates the cache' => sub {
  reset_state();
  respond(200, {access_token => $ACCESS, expires_in => 3600});
  token();
  set_params(smtp_oauth2_refresh_token => 'other-refresh');
  token();
  is(scalar @posts, 2, 'refresh_token change: new POST');
  set_params(smtp_username => 'other@example.com');
  token();
  is(scalar @posts, 3, 'smtp_username change: new POST');
  set_params(
    smtp_oauth2_refresh_token => $REFRESH,
    smtp_username             => 'bugs@example.com'
  );
};

subtest 'no expires_in: not cached' => sub {
  reset_state();
  respond(200, {access_token => $ACCESS});
  is(token(), $ACCESS, 'returns the token');
  ok(!Bugzilla->process_cache->{smtp_oauth2}, 'nothing cached');
  token();
  is(scalar @posts, 2, 'next call POSTs again');
};

subtest 'token errors' => sub {
  reset_state();
  respond(200, {access_token => $ACCESS, expires_in => 3600});
  token();
  Bugzilla->process_cache->{smtp_oauth2}{expires} = time();

  respond(400,
    {error => 'invalid_grant', error_description => "bad $REFRESH $SECRET"});
  my $ok = eval { token(); 1 };
  my $err = $@;
  ok(!$ok, 'HTTP error dies');
  like($err, qr/^SMTP OAuth2 token request failed: 400 Bad Request \(invalid_grant\)/,
    'message has status and error code');
  ok(!Bugzilla->process_cache->{smtp_oauth2}, 'cache cleared');
  foreach my $secret ($SECRET, $REFRESH, $ACCESS, 'grant_type', 'bad ') {
    unlike($err, qr/\Q$secret\E/, "message does not contain '$secret'");
  }

  respond(500, "not json $REFRESH");
  eval { token() };
  like($@, qr/^SMTP OAuth2 token request failed: 500 Bad Request\n\z/,
    'non-JSON error body is not echoed');

  respond(200, {token_type => 'Bearer'});
  eval { token() };
  like($@, qr/^SMTP OAuth2 token response has no access_token\n\z/,
    'missing access_token dies');
};

subtest 'oauth2 transport never falls back to the password' => sub {
  reset_state();
  set_params(smtp_auth_method => 'oauth2');
  respond(401, {error => 'invalid_client'});
  my $transport = eval { Bugzilla::Mailer::_smtp_transport('localhost') };
  like($@, qr/^SMTP OAuth2 token request failed: 401/,
    'dies with the token error');
  ok(!$transport, 'no transport built');
  set_params(smtp_auth_method => 'password');
};

subtest 'AUTH failure clears the cache' => sub {
  my $auth_fail
    = Email::Sender::Failure->new('failed AUTH: 535 5.7.8 not accepted');
  my $other_fail = Email::Sender::Failure->new('unable to establish SMTP');

  foreach my $case ([oauth2 => $other_fail, 1], [password => $auth_fail, 1],
    [oauth2 => $auth_fail, 0])
  {
    my ($method, $failure, $kept) = @$case;
    set_params(smtp_auth_method => $method);
    Bugzilla->process_cache->{smtp_oauth2}
      = {key => 'k', token => 't', expires => time() + 3600};
    Bugzilla::Mailer::_smtp_oauth2_clear_on_failure($failure);
    is(!!Bugzilla->process_cache->{smtp_oauth2}, !!$kept,
      "$method / '" . $failure->message . "': " . ($kept ? 'kept' : 'cleared'));
  }
  set_params(smtp_auth_method => 'password');
  reset_state();
};

subtest 'checkers' => sub {
  my $entry
    = {name => 'smtp_auth_method', type => 's', choices => ['password', 'oauth2']};
  my $has_feature;
  my $bz = mock 'Bugzilla' => (
    override => [feature => sub { $_[1] eq 'smtp_oauth2' ? $has_feature : 1 }],
  );

  $has_feature = 0;
  like(check_smtp_auth_method('oauth2', $entry), qr/not available/,
    'oauth2 rejected without the smtp_oauth2 feature');
  is(check_smtp_auth_method('password', $entry), '',
    'password accepted without the feature');
  $has_feature = 1;
  is(check_smtp_auth_method('oauth2', $entry), '',
    'oauth2 accepted with the feature');
  isnt(check_smtp_auth_method('bogus', $entry), '', 'unknown value rejected');

  is(check_smtp_oauth2_token_url(''), '', 'empty token_url accepted');
  is(check_smtp_oauth2_token_url('https://oauth2.example.com/token'),
    '', 'https token_url accepted');
  isnt(check_smtp_oauth2_token_url('http://oauth2.example.com/token'),
    '', 'http token_url rejected');
};

SKIP: {
  my $have_xoauth2 = eval {
    require Authen::SASL;
    Authen::SASL->VERSION('2.1800');
    require Authen::SASL::Perl::XOAUTH2;
    1;
  };
  skip 'Authen::SASL >= 2.1800 with XOAUTH2 not installed', 1
    unless $have_xoauth2;

  subtest 'oauth2 transport uses XOAUTH2' => sub {
    reset_state();
    set_params(smtp_auth_method => 'oauth2');
    respond(200, {access_token => $ACCESS, expires_in => 3600});
    my $transport = Bugzilla::Mailer::_smtp_transport('localhost');
    ok(!defined $transport->sasl_username, 'no sasl_username');
    ok(!defined $transport->sasl_password, 'no sasl_password');
    my $sasl = $transport->sasl_authenticator;
    isa_ok($sasl, 'Authen::SASL');
    is($sasl->mechanism, 'XOAUTH2', 'mechanism is XOAUTH2');
    my $conn = $sasl->client_new('smtp', 'localhost');
    is($conn->mechanism, 'XOAUTH2', 'client uses XOAUTH2');
    is(
      $conn->client_start,
      "user=bugs\@example.com\001auth=Bearer $ACCESS\001\001",
      'user is smtp_username, pass is the access token'
    );
    set_params(smtp_auth_method => 'password');
  };
}

done_testing;
