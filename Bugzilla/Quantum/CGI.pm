# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Quantum::CGI;
use 5.10.1;
use Moo;

has 'controller' => (
    is      => 'ro',
    handles => [qw(param cookie)],
);

has 'csp_object' => (
    is     => 'ro',
    writer => 'set_csp_object',
);

with 'Bugzilla::CGI::ContentSecurityPolicyAttr';

sub script_name {
    my ($self) = @_;

    return $self->controller->req->env->{SCRIPT_NAME};
}

sub referer {
    my ($self) = @_;
    my $c = $self->controller;

    return $c->req->headers->referrer;
}

sub http {
    my ($self, $header) = @_;
    return $self->controller->req->headers->header($header);
}

sub header {
    my ($self, @args) = @_;
    my $c = $self->controller;
    return '' if @args == 0;

    if (@args == 1) {
        $c->res->headers->content_type($args[0]);
    }

    return '';
}

sub redirect {
    my ($self, $location) = @_;

    $self->controller->redirect_to($location);
}

sub Vars {
    my ($self) = @_;

    return $self->controller->req->query_params->to_hash;
}

sub query_string {
    my ($self) = @_;

    return $self->controller->req->query_params->to_string;
}

sub send_cookie {
    my ($self, %params) = @_;
    my $name = delete $params{'-name'};
    my $value = delete $params{'-value'} or ThrowCodeError('cookies_need_value');
    state $uri      = URI->new( Bugzilla->localconfig->{urlbase} );
    my %attrs = (
        path => $uri->path,
        secure => lc( $uri->scheme ) eq 'https',
        samesite => 'Lax',
    );
    my $expires = delete $params{'-expires'};
    $attrs{expires} = $expires if $expires;
    $attrs{httponly} = 1 if delete $params{'-httponly'};

    if (keys %params) {
        die "Unknown keys: " . join(", ", keys %params);
    }

    $self->controller->cookie($name, $value, \%params);
}

1;

