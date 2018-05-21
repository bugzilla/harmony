# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::CGI;
use Mojo::Base 'Mojolicious::Controller';

use CGI::Compile;
use Bugzilla::Constants qw(bz_locations);
use File::Slurper qw(read_text);
use File::Spec::Functions qw(catfile);
use Sub::Quote 2.005000;
use Taint::Util qw(untaint);

my %CGIS;

_load_all();

sub expose_routes {
    my ($class, $r) = @_;
    foreach my $cgi (keys %CGIS) {
        $r->any("/$cgi")->to("CGI#$CGIS{$cgi}");
    }
}

sub _load_all {
    foreach my $script (glob '*.cgi') {
        my $name = _load_cgi($script);
        $CGIS{ $script } = $name;
    }
}

sub _load_cgi {
    my ($file) = @_;
    my $name = $file;
    $name =~ s/\.cgi$//s;
    $name =~ s/\W+/_/gs;
    my $subname = "handle_$name";
    my $content = read_text(catfile(bz_locations->{cgi_path}, $file));
    untaint($content);
    $content = 'my ($self) = @_; ' . $content;
    my %options = (
        package => __PACKAGE__ . "::$name",
        file    => $file,
        line    => 1,
        no_defer => 1,
    );
    quote_sub $subname, $content, {}, \%options;
    return $subname;
}

1;