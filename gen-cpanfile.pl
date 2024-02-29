#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

######################################################################
# Initialization
######################################################################

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use CPAN::Meta;
use Module::CPANfile;

my $meta = CPAN::Meta->load_file('MYMETA.json');
my $file = Module::CPANfile->from_prereqs($meta->prereqs);

# Manually extract and populate feature information
# https://github.com/miyagawa/cpanfile/issues/52

for my $feature ($meta->features) {
  $file->{_prereqs}->add_feature($feature->identifier, $feature->description);
  my $prereqs = [];
  while (my ($phase, $types) = each %{$feature->{prereqs}->{prereqs}}) {
    while (my ($type, $requirements) = each %$types) {
      my $req_spec = $requirements->as_string_hash;
      while (my ($module, $version) = each %{$req_spec}) {
        push @{$prereqs},
            Module::CPANfile::Prereq->new(
              feature => $feature->identifier,
              phase   => $phase,
              type    => $type,
              module  => $module,
              requirement => Module::CPANfile::Requirement->new(
                name    => $module,
                version => $version,
              ),
            );
      }
    }
  }
  $file->{_prereqs}->{prereqs}{$feature->identifier} = $prereqs;
}

$file->save('cpanfile');
