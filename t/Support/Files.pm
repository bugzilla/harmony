# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.


package Support::Files;

use 5.14.0;
use strict;
use warnings;

use File::Find;

our @additional_files = ();

use constant IGNORE => qw(
  Bugzilla/DuoAPI.pm
  Bugzilla/DuoWeb.pm
  Bugzilla/Test/MockDB.pm
  Bugzilla/Test/MockParams.pm
  Bugzilla/Report/Ping/Simple.pm
);

our @files = glob('*');
find(sub { push(@files, $File::Find::name) if $_ =~ /\.pm$/; },
  qw(Bugzilla docs));
push(@files, 'extensions/create.pl', 'docs/makedocs.pl', 'cpanfile');

our @extensions = grep { $_ ne 'extensions/create.pl' && !-e "$_/disabled" }
  glob('extensions/*');

foreach my $extension (@extensions) {
  find(
    sub {
      # Skip files under a disabled sub-directory (e.g. Connector.disabled/),
      # which are not stand-alone modules or scripts and cannot be compiled
      # on their own.
      return if $File::Find::name =~ m{\.disabled(?:/|$)};
      return if $File::Find::name =~ m{^extensions/.+/template/};
      push(@files, $File::Find::name) if $_ =~ /\.pm$|\.pl$/;
    },
    $extension
  );
}

our @test_files = glob('t/*.t xt/*/*.t');

sub isTestingFile {
  my ($file) = @_;
  my $exclude;

  foreach my $ignore (IGNORE) {
    return undef if $ignore eq $file;
  }

  if ($file =~ /\.pl$|\.pm$/) {
    return 1;
  }
  my $additional;
  foreach $additional (@additional_files) {
    if ($file eq $additional) { return 1; }
  }
  return undef;
}

our (@testitems, @module_files);

foreach my $currentfile (@files) {
  if (isTestingFile($currentfile)) {
    push(@testitems, $currentfile);
  }
  push(@module_files, $currentfile) if $currentfile =~ /\.pm$/;
}

1;
