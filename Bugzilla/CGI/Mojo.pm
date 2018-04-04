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

sub script_name {
    my ($self) = @_;

    return $self->controller->req->env->{SCRIPT_NAME};
}

sub Vars {
    my ($self) = @_;

    return $self->controller->req->query_params->to_hash;
}

1;