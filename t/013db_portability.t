# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.14.0;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5 t);

use Support::Files;

use Test::More;

my %seen_file;
my @files = grep { $_ ne 't/013db_portability.t' && !$seen_file{$_}++ }
  (@Support::Files::testitems, @Support::Files::test_files);

my @rules = (
  {
    token => qr/\bUNIX_TIMESTAMP\s*\(/,
    helper => 'sql_date_format',
    message => 'use $dbh->sql_date_format(...) instead of UNIX_TIMESTAMP()',
  },
  {
    token => qr/\bDATE_FORMAT\s*\(/,
    helper => 'sql_date_format',
    message => 'use $dbh->sql_date_format(...) instead of DATE_FORMAT()',
  },
  {
    token => qr/\bCONCAT\s*\(/,
    helper => 'sql_string_concat',
    message => 'use $dbh->sql_string_concat(...) instead of CONCAT()',
  },
  {
    token => qr/\b(?:POSITION|INSTR|LOCATE)\s*\(/,
    helper => 'sql_position/sql_iposition',
    message => 'use $dbh->sql_position(...) or $dbh->sql_iposition(...) instead',
  },
  {
    token => qr/\bGROUP_CONCAT\s*\(/,
    helper => 'sql_group_concat',
    message => 'use $dbh->sql_group_concat(...) instead of GROUP_CONCAT()',
  },
);

my @violations;

foreach my $file (@files) {
  next if $file =~ m{^Bugzilla/DB(?:/|\.pm$)};

  open(my $fh, '<', $file) or do {
    push @violations, { file => $file, line => 0, text => 'could not open file' };
    next;
  };

  my $line_number = 0;
  while (my $line = <$fh>) {
    $line_number++;
    next if $line =~ /^\s*#/;
    next if $line =~ /^\s*=/;

    foreach my $rule (@rules) {
      next unless $line =~ $rule->{token};
      push @violations, {
        file    => $file,
        line    => $line_number,
        text    => $line,
        helper  => $rule->{helper},
        message => $rule->{message},
      };
    }
  }
  close($fh);
}

is(scalar(@violations), 0, 'no raw vendor-specific SQL where a Bugzilla DB helper exists');

if (@violations) {
  diag(join("\n", map {
    sprintf('%s:%d: %s (%s)', $_->{file}, $_->{line}, $_->{message}, $_->{text})
  } @violations));
}

done_testing();
