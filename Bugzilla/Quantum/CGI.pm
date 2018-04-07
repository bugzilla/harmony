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

1;
