#!/usr/bin/perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

while (<>) {
    my ($cmd, @args) = split /\s+/, $_;
    next unless $cmd;
    if (lc($cmd) eq "\LRewriteRule") {
        my ($regex, $target, $flags) = @args;
        $flags //= '';
        next if $flags =~ /E=HTTP/;
        my $action = 'rewrite_query';
        if ($flags =~ /R/) {
            $action = 'redirect';
        }
        say qq{# from line $. of $ARGV};
        say "if (my \@match = \$path =~ m{$regex}s) {";
        say "    $action(\$c, q{$target}, \@match);";
        say "    return;" if $flags =~ /L/;
        say "}";
    }
    elsif (lc($cmd) eq "\LRedirect") {
        say qq{# from line $. of $ARGV};
        say "if (my \@match = \$path =~ m{$regex}s) {";
        say "    $action(\$c, q{$target}, \@match);";
        say "    return;" if $flags =~ /L/;
        say "}";
    }
}


