#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

if [ ! -e 'Makefile.PL' ]; then
    echo
    echo "Please run this from the root of the Bugzilla source tree."
    echo
    exit -1
fi
if [ -z "$DOCKER" ]; then
    DOCKER=`which docker`
fi
if [ -n "$DOCKER" ] && [ ! -x "$DOCKER" ]; then
    echo
    echo "You specified a custom Docker executable via the DOCKER"
    echo "environment variable at $DOCKER"
    echo "which either does not exist or is not executable."
    echo "Please fix it to point at a working Docker or remove the"
    echo "DOCKER environment variable to use the one in your PATH"
    echo "if it exists."
    echo
    exit -1
fi
if [ -z "$DOCKER" ]; then
    echo
    echo "You do not appear to have docker installed or I can't find it."
    echo "Windows and Mac versions can be downloaded from"
    echo "https://www.docker.com/products/docker-desktop"
    echo "Linux users can install using your package manager."
    echo
    echo "Please install docker or specify the location of the docker"
    echo "executable in the DOCKER environment variable and try again."
    echo
    exit -1
fi
$DOCKER info 1>/dev/null 2>/dev/null
if [ $? != 0 ]; then
    echo
    echo "The docker daemon is not running or I can't connect to it."
    echo "Please make sure it's running and try again."
    echo
    exit -1
fi

export DOCKER_CLI_HINTS=false
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
    read -p "Select a test option (1-6, default is mysql): " choice
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
    $DOCKER build -t bugzilla-release-test -f $DOCKER_FILE .
    if [ $? == 0 ]; then
        $DOCKER run --rm bugzilla-release-test
    else
        echo "docker build failed."
    fi
    exit $?
fi
$DOCKER compose -f $DOCKER_COMPOSE_FILE build
if [ $? == 0 ]; then
    $DOCKER compose -f $DOCKER_COMPOSE_FILE run --rm --name bugzilla6.test bugzilla6.test $TEST_NAME -q -f t/bmo/*.t
    $DOCKER compose -f $DOCKER_COMPOSE_FILE down
else
    echo "docker compose build failed."
fi
