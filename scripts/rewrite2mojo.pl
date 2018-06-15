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
use Mojo::Parameters;
use Data::Dumper;

while (<>) {
    my ($cmd, @args) = split /\s+/, $_;
    next unless $cmd;
    if (lc($cmd) eq "\LRewriteRule") {
        my ($regex, $target, $flags) = @args;
        $flags //= '';
        next if $flags =~ /E=HTTP/;
        next if $target eq '-';
        my $action = 'rewrite_query';
        if ($flags =~ /R/) {
            next;
        }
        my ($script, $query) = $target =~ /^([^?]+)(?:\?(.+))?$/;
        my $name = _file_to_method($script);
        $regex =~ s/^\^//;
        $regex =~ s/\$$//;
        my $regex_name = _regex_to_name($regex);
        my $param_hash = Mojo::Parameters->new($query)->to_hash;
        my $param_str = Data::Dumper->new([$param_hash])->Terse(1)->Indent(0)->Dump;
        say "\$r->any('/:$regex_name' => [$regex_name => qr{$regex}])->to(";
        say "    'CGI#$name' => $param_str";
        say ");";

    }
    # elsif (lc($cmd) eq "\LRedirect") {
    #     my ($type, $path, $url) = @args;
    #     if ($type eq 'permanent') {
    #         say "if (\$path =~ m{^\Q$path\E}s) {";
    #         say "    redirect(\$c, q{$url});";
    #         say "    return;";
    #         say "}";
    #     }
    #     else {
    #         warn "I don't understand Redirect $type\n";
    #     }
    # }
}

sub _file_to_method {
    my ($name) = @_;
    $name =~ s/\./_/s;
    $name =~ s/\W+/_/gs;
    return $name;
}

sub _regex_to_name {
    my ($name) = @_;
    $name =~ s/\./_/s;
    $name =~ s/\W+/_/gs;
    $name =~ s/_+/_/g;
    $name =~ s/^_//s;
    $name =~ s/_$//s;
    return $name;
}


