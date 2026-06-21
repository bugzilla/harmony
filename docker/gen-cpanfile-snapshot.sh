#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Source common Docker script checks and functions
# shellcheck source=docker/common.sh
source "$(dirname "$0")/common.sh"

if [ ! -f "docker/images/Dockerfile.cpanfile" ]; then
    echo
    echo "Can't locate the Dockerfile, try running from the root of"
    echo "your Bugzilla checkout."
    echo
    exit 1
fi

$DOCKER build -t bugzilla-cpanfile -f docker/images/Dockerfile.cpanfile .
$DOCKER run -it -v "$(pwd):/app/result" bugzilla-cpanfile cp cpanfile cpanfile.snapshot /app/result

