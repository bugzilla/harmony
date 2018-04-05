# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::CGI::Mojo;
use 5.10.1;
use Moo;

has 'controller' => (
    is      => 'ro',
    handles => [qw(param cookie)],
);

has 'content_security_policy' => (
    is => 'lazy',
);

sub _build_content_security_policy {
    my ($self) = @_;
    my $csp = $self->controller->stash->{content_security_policy} // { Bugzilla::CGI::DEFAULT_CSP() };
    return Bugzilla::CGI::ContentSecurityPolicy->new( $csp );
}

sub csp_nonce {
    my ($self) = @_;

    my $csp = $self->content_security_policy;
    return $csp->has_nonce ? $csp->nonce : '';
}

sub script_name {
    my ($self) = @_;

    return $self->controller->req->env->{SCRIPT_NAME};
}

sub http {
    my ($self, $header) = @_;
    return $self->controller->req->headers->header($header);
}

sub redirect {
    my ($self, $location) = @_;

    $self->controller->redirect_to($location);
}

sub Vars {
    my ($self) = @_;

    return $self->controller->req->query_params->to_hash;
}

1;
