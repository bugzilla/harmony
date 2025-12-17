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

export CI=""
export CIRCLE_SHA1=""
export CIRCLE_BUILD_URL=""

TEST_NAME="test_bmo"
DOCKER_COMPOSE_FILE=docker-compose.test-mysql.yml
if [ "$#" -eq 0 ]; then
    echo "Available test options:"
    echo "  1) sanity   - Run sanity tests"
    echo "  2) mysql    - Run BMO tests with MySQL (default)"
    echo "  3) pg       - Run BMO tests with PostgreSQL"
    echo "  4) sqlite   - Run BMO tests with SQLite"
    echo "  5) mariadb  - Run BMO tests with MariaDB"
    echo "  6) release  - Run release tests"
    echo
    read -rp "Select a test option (1-6, default is mysql): " choice
    case "$choice" in
        1) set -- "sanity" ;;
        2|"") set -- "mysql" ;;
        3) set -- "pg" ;;
        4) set -- "sqlite" ;;
        5) set -- "mariadb" ;;
        6) set -- "release" ;;
        *) echo "Invalid choice. Using default (mysql)"; set -- "mysql" ;;
    esac
fi
if [ "$1" == "sanity" ]; then
    DOCKER_COMPOSE_FILE=docker-compose.test-mysql.yml
    TEST_NAME="test_sanity"
elif [ "$1" == "mysql" ]; then
    DOCKER_COMPOSE_FILE=docker-compose.test-mysql.yml
elif [ "$1" == "pg" ]; then
    DOCKER_COMPOSE_FILE=docker-compose.test-pg.yml
elif [ "$1" == "sqlite" ]; then
    DOCKER_COMPOSE_FILE=docker-compose.test-sqlite.yml
elif [ "$1" == "mariadb" ]; then
    DOCKER_COMPOSE_FILE=docker-compose.test-mariadb.yml
elif [ "$1" == "release" ]; then
    DOCKER_FILE=docker/images/Dockerfile.perl-testsuite
    if $DOCKER build -t bugzilla-release-test -f "$DOCKER_FILE" .; then
        $DOCKER run --rm bugzilla-release-test
    else
        echo "docker build failed."
    fi
    exit $?
fi
if $DOCKER compose -f "$DOCKER_COMPOSE_FILE" build; then
    if $DOCKER compose -f "$DOCKER_COMPOSE_FILE" run --rm --name bugzilla6.test bugzilla6.test "$TEST_NAME" -q -f t/bmo/*.t; then
        $DOCKER compose -f "$DOCKER_COMPOSE_FILE" down
    else
        echo "docker compose run failed."
        $DOCKER compose -f "$DOCKER_COMPOSE_FILE" down
        exit 1
    fi
else
    echo "docker compose build failed."
    exit 1
fi
