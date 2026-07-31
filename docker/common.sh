#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

##################################################
# Common checks and functions for docker scripts #
##################################################

# Function to print text in red if terminal supports it
echo_red() {
    if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        echo -e "\033[31m$1\033[0m"
    else
        echo "$1"
    fi
}

# Function to print text in green if terminal supports it
echo_green() {
    if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
        echo -e "\033[32m$1\033[0m"
    else
        echo "$1"
    fi
}

# Check that we're in the root of the Bugzilla source tree
if [ ! -e 'Makefile.PL' ]; then
    echo
    echo_red "Please run this from the root of the Bugzilla source tree."
    echo
    exit 1
fi

# Find and validate the Docker executable
if [ -z "$DOCKER" ]; then
    DOCKER=$(which docker)
fi
if [ -n "$DOCKER" ] && [ ! -x "$DOCKER" ]; then
    echo
    echo_red "You specified a custom Docker executable via the DOCKER"
    echo_red "environment variable at $DOCKER"
    echo_red "which either does not exist or is not executable."
    echo "Please fix it to point at a working Docker or remove the"
    echo "DOCKER environment variable to use the one in your PATH"
    echo "if it exists."
    echo
    exit 1
fi
if [ -z "$DOCKER" ]; then
    echo
    echo_red "You do not appear to have docker installed or I can't find it."
    echo "Windows and Mac versions can be downloaded from"
    echo "https://www.docker.com/products/docker-desktop"
    echo "Linux users can install using your package manager."
    echo
    echo "Please install docker or specify the location of the docker"
    echo "executable in the DOCKER environment variable and try again."
    echo
    exit 1
fi

# Check that Docker daemon is running
if ! $DOCKER info >/dev/null 2>&1; then
    echo
    echo_red "The docker daemon is not running or I can't connect to it."
    echo "Please make sure it's running and try again."
    echo
    exit 1
fi

# Disable Docker CLI hints
export DOCKER_CLI_HINTS=false
