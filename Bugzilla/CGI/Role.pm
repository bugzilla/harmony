# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::CGI::Role;
use 5.10.1;
use strict;
use warnings;
use Role::Tiny;

requires 'csp_object', 'set_csp_object';

sub DEFAULT_CSP {
    my %policy = (
        default_src => [ 'self' ],
        script_src  => [ 'self', 'nonce', 'unsafe-inline', 'https://www.google-analytics.com' ],
        frame_src   => [ 'none', ],
        worker_src  => [ 'none', ],
        img_src     => [ 'self', 'https://secure.gravatar.com', 'https://www.google-analytics.com' ],
        style_src   => [ 'self', 'unsafe-inline' ],
        object_src  => [ 'none' ],
        connect_src => [
            'self',
            # This is from extensions/OrangeFactor/web/js/orange_factor.js
            'https://treeherder.mozilla.org/api/failurecount/',
        ],
        form_action => [
            'self',
            # used in template/en/default/search/search-google.html.tmpl
            'https://www.google.com/search'
        ],
        frame_ancestors => [ 'none' ],
        report_only     => 1,
    );
    if (Bugzilla->params->{github_client_id} && !Bugzilla->user->id) {
        push @{$policy{form_action}}, 'https://github.com/login/oauth/authorize', 'https://github.com/login';
    }

    return %policy;
}

sub content_security_policy {
    my ($self, %add_params) = @_;
    if (%add_params || !$self->csp_object) {
        my %params = DEFAULT_CSP;
        delete $params{report_only} if %add_params && !$add_params{report_only};
        foreach my $key (keys %add_params) {
            if (defined $add_params{$key}) {
                $params{$key} = $add_params{$key};
            }
            else {
                delete $params{$key};
            }
        }
        $self->set_csp_object( Bugzilla::CGI::ContentSecurityPolicy->new(%params) );
    }

    return $self->csp_object;
}

sub csp_nonce {
    my ($self) = @_;

    my $csp = $self->content_security_policy;
    return $csp->has_nonce ? $csp->nonce : '';
}

# Cookies are removed by setting an expiry date in the past.
# This method is a send_cookie wrapper doing exactly this.
sub remove_cookie {
    my ($self, $name) = @_;

    # Expire the cookie, giving a non-empty dummy value (bug 268146).
    $self->send_cookie(
        '-name'    => $name,
        '-expires' => 'Tue, 15-Sep-1998 21:49:00 GMT',
        '-value'   => 'X'
    );
}

1;
