# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::Legacy;
use Mojo::Base 'Mojolicious::Controller';
use File::Spec::Functions qw(catfile);
use Bugzilla::Constants qw(bz_locations);
use Taint::Util qw(untaint);
use Sub::Name qw(subname);
use autodie;

_load_cgi(index_cgi => 'index.cgi');
_load_cgi(show_bug => 'show_bug.cgi');

sub _load_cgi {
    my ($name, $file) = @_;
    my $content;
    {
        local $/ = undef;
        open my $fh, '<', catfile(bz_locations->{cgi_path}, $file);
        $content = <$fh>;
        untaint($content);
        close $fh;
    }
    my $pkg = __PACKAGE__ . '::' . $name;
    my @lines = (
        qq{package $pkg;},
        qq{#line 1 "$file"},
        "sub { my (\$self) = \@_; $content };"
    );
    my $code = join "\n", @lines;
    my $sub = _eval($code);
    {
        no strict 'refs'; ## no critic (strict)
        *{ $name } = subname($name, $sub);
    }
}

sub _eval { ## no critic (unpack)
    return eval $_[0]; ## no critic (eval)
}

1;