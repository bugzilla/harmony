#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# Ensure this script is run with bash
# BASH_VERSION can be set in some shells; instead, verify declare -A works.
if ! (declare -A __test_assoc 2>/dev/null); then
    echo "This script requires bash. Checking if you have it..."
    bash=$(which bash)
    if [ -n "$bash" ] && [ -x "$bash" ]; then
        echo "Found bash at $bash. Re-running script with bash..."
        echo
        exec bash "$0" "$@"
    else
        echo_red "Could not find bash. Put it in your PATH and try again."
        exit 1
    fi
fi

# Source common Docker script checks and functions
# shellcheck source=docker/common.sh
source "$(dirname "$0")/common.sh"

FILES=()
for f in docker/images/Dockerfile.b*; do
    [[ "$f" != *.bak ]] && FILES+=("${f#docker/images/Dockerfile.}")
done
PS3="Choose an image to build or CTRL-C to abort: "
select IMAGE in "All images" "${FILES[@]}"; do
    CACHE=""
    if [ "$1" == "--no-cache" ]; then
        CACHE="--no-cache"
    fi

    export DOCKER_CLI_HINTS=false
    export CI=""
    export CIRCLE_SHA1=""
    export CIRCLE_BUILD_URL=""

    # Determine which images to build
    if [ "$IMAGE" == "All images" ]; then
        IMAGES_TO_BUILD=("${FILES[@]}")
    else
        IMAGES_TO_BUILD=("$IMAGE")
    fi

    # Track successfully built images
    declare -A BUILT_IMAGES

    for IMAGE in "${IMAGES_TO_BUILD[@]}"; do
        # Figure out the tag name to use for the image. We'll do this by generating
        # a code based on today's date, then attempt to pull it from DockerHub. If
        # we successfully pull, then it already exists, and we bump the interation
        # number on the end.
        DATE=$(date +"%Y%m%d")
        ITER=1
        while $DOCKER pull "bugzilla/${IMAGE}:${DATE}.${ITER}" >/dev/null 2>/dev/null; do
            # as long as we succesfully pull, keep bumping the number on the end
            ((ITER++))
        done
        LINE="Building bugzilla/${IMAGE}:${DATE}.${ITER}"
        echo "##${LINE//?/#}##"
        echo "# ${LINE} #"
        echo "##${LINE//?/#}##"
        if $DOCKER build $CACHE -t "bugzilla/${IMAGE}:${DATE}.${ITER}" -f "docker/images/Dockerfile.${IMAGE}" .; then
            echo
            echo_green "The build appears to have succeeded."

            # Only update Dockerfiles when building the perl-slim image specifically (not variants like perl-slim-mysql)
            if [[ "$IMAGE" == "bugzilla-perl-slim" ]]; then
                echo "Updating FROM lines in Dockerfiles to use bugzilla/${IMAGE}:${DATE}.${ITER}..."
                echo

                # Update all Dockerfiles that reference this image
                for dockerfile in Dockerfile docker/images/Dockerfile.*; do
                    # Skip backups and temp files
                    case "$dockerfile" in
                        *.bak|*.tmp) continue ;;
                    esac
                    if [ -f "$dockerfile" ]; then
                        # Check for both direct references and BZDB variable references
                        if grep -q "FROM bugzilla/${IMAGE}:" "$dockerfile" || grep -q "FROM bugzilla/${IMAGE}\${BZDB}:" "$dockerfile"; then
                            # Create a backup
                            cp "$dockerfile" "${dockerfile}.bak"
                            echo "  Created backup: ${dockerfile}.bak"
                            # Update the FROM line - handle both direct and BZDB variable patterns
                            sed -i.tmp "s|FROM bugzilla/${IMAGE}:[^ ]*|FROM bugzilla/${IMAGE}:${DATE}.${ITER}|g" "$dockerfile"
                            sed -i.tmp "s|FROM bugzilla/${IMAGE}\${BZDB}:[^ ]*|FROM bugzilla/${IMAGE}\${BZDB}:${DATE}.${ITER}|g" "$dockerfile"
                            rm -f "${dockerfile}.tmp"
                            echo "  Updated: $dockerfile"
                        fi
                    fi
                done
                echo
            fi

            # Track the successfully built image
            BUILT_IMAGES["${IMAGE}"]="${DATE}.${ITER}"
        else
            echo
            echo_red "Docker build failed for ${IMAGE}. See output above."
            echo
            if [ ${#IMAGES_TO_BUILD[@]} -eq 1 ]; then
                exit 1
            fi
        fi
    done

    # Check if any images were built successfully
    if [ ${#BUILT_IMAGES[@]} -eq 0 ]; then
        echo_red "No images were built successfully."
        exit 1
    fi
    echo
    echo_green "Successfully built ${#BUILT_IMAGES[@]} image(s):"
    for img in "${!BUILT_IMAGES[@]}"; do
        echo "  - bugzilla/${img}:${BUILT_IMAGES[$img]}"
    done

    # check if the user is logged in
    if [ -z "$PYTHON" ]; then
        PYTHON=$(which python)
    fi
    if [ -z "$PYTHON" ]; then
        PYTHON=$(which python3)
    fi
    if [ ! -x "$PYTHON" ]; then
        echo "The python executable specified in your PYTHON environment value or your PATH is not executable or I can't find it."
        exit 1
    fi
    AUTHINFO=$($PYTHON -c "import json; print(len(json.load(open('${HOME}/.docker/config.json','r',encoding='utf-8'))['auths']))")
    if [ "$AUTHINFO" -gt 0 ]; then
        # user is logged in
        echo
        read -rp "Do you wish to push to DockerHub? [y/N]: " yesno
        case $yesno in
            [Yy]*)
                echo
                echo "Pushing images..."
                for img in "${!BUILT_IMAGES[@]}"; do
                    tag="${BUILT_IMAGES[$img]}"
                    echo "Pushing bugzilla/${img}:${tag}..."
                    $DOCKER push "bugzilla/${img}:${tag}"
                    echo "Tagging bugzilla/${img}:${tag} as bugzilla/${img}:latest..."
                    $DOCKER tag "bugzilla/${img}:${tag}" "bugzilla/${img}:latest"
                    $DOCKER push "bugzilla/${img}:latest"
                done
                echo_green "All images pushed successfully."
                ;;
            *)
                echo
                echo "Not pushing. You can just run this script again when you're ready"
                echo "to push. The prior build results are cached."
                echo_red "Remember DO NOT commit any changes to the FROM lines of Dockerfiles until"
                echo_red "you've pushed to DockerHub. Doing so will break tests on GitHub Actions."
                ;;
        esac
    fi
    break
done
