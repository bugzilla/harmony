# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# This file is loaded inside a Safe compartment, so keep it as plain package
# data: do not add strict/warnings pragmas or lexical %strings declarations.

%strings = (
  feature_push_amqp  => 'Push: AMQP Support',
  feature_push_stomp => 'Push: STOMP Support',
);
