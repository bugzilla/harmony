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

TAG_FILE="docker/base-image-tags.env"

MENU_IMAGES=()
for image in "${FILES[@]}"; do
    MENU_IMAGES+=("$image")
    if [[ "$image" == bugzilla-perl-slim-* ]]; then
        MENU_IMAGES+=("${image/bugzilla-perl-slim-/bugzilla-perl-full-}")
    fi
done

write_base_tags_file() {
    cat > "$TAG_FILE" <<EOF
BUGZILLA_PERL_SLIM_TAG=${BUGZILLA_PERL_SLIM_TAG}
BUGZILLA_PERL_FULL_TAG=${BUGZILLA_PERL_FULL_TAG}
EOF
}

resolve_base_tag() {
    local base_image="$1"

    if [ -n "${BUILT_IMAGES[$base_image]}" ]; then
        echo "${BUILT_IMAGES[$base_image]}"
        return 0
    fi

    if [[ "$base_image" == "bugzilla-perl-slim" ]]; then
        echo "$BUGZILLA_PERL_SLIM_TAG"
    elif [[ "$base_image" == "bugzilla-perl-full" ]]; then
        echo "$BUGZILLA_PERL_FULL_TAG"
    else
        echo ""
    fi
}

if [ -f "$TAG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$TAG_FILE"
fi

BUGZILLA_PERL_SLIM_TAG="${BUGZILLA_PERL_SLIM_TAG:-}"
BUGZILLA_PERL_FULL_TAG="${BUGZILLA_PERL_FULL_TAG:-}"

PS3="Choose an image to build or CTRL-C to abort: "
select IMAGE in "All images" "${MENU_IMAGES[@]}"; do
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
        IMAGES_TO_BUILD=()

        if [[ " ${FILES[*]} " == *" bugzilla-perl-slim "* ]]; then
            IMAGES_TO_BUILD+=("bugzilla-perl-slim")
        fi
        if [[ " ${FILES[*]} " == *" bugzilla-perl-full "* ]]; then
            IMAGES_TO_BUILD+=("bugzilla-perl-full")
        fi

        for image in "${FILES[@]}"; do
            case "$image" in
                bugzilla-perl-slim|bugzilla-perl-full)
                    continue
                    ;;
                bugzilla-perl-slim-*)
                    IMAGES_TO_BUILD+=("$image")
                    IMAGES_TO_BUILD+=("${image/bugzilla-perl-slim-/bugzilla-perl-full-}")
                    ;;
                *)
                    IMAGES_TO_BUILD+=("$image")
                    ;;
            esac
        done
    else
        IMAGES_TO_BUILD=("$IMAGE")
    fi

    # Track successfully built images
    declare -A BUILT_IMAGES

    for IMAGE in "${IMAGES_TO_BUILD[@]}"; do
        DOCKERFILE_IMAGE="$IMAGE"
        BUILD_ARGS=()
        BASE_IMAGE=""

        if [[ "$IMAGE" == bugzilla-perl-full-* ]]; then
            DOCKERFILE_IMAGE="${IMAGE/bugzilla-perl-full-/bugzilla-perl-slim-}"
            BUILD_ARGS+=(--build-arg SIZE=full)
            BASE_IMAGE="bugzilla-perl-full"
        elif [[ "$IMAGE" == "bugzilla-perl-full" ]]; then
            BASE_IMAGE="bugzilla-perl-slim"
        elif [[ "$IMAGE" == bugzilla-perl-slim-* ]]; then
            BUILD_ARGS+=(--build-arg SIZE=slim)
            BASE_IMAGE="bugzilla-perl-slim"
        fi

        if [ -n "$BASE_IMAGE" ]; then
            BASE_TAG=$(resolve_base_tag "$BASE_IMAGE")
            if [ -z "$BASE_TAG" ]; then
                echo
                echo_red "Could not determine a base tag for ${BASE_IMAGE}."
                echo_red "Build ${BASE_IMAGE} first, or set tags in ${TAG_FILE}."
                echo
                if [ ${#IMAGES_TO_BUILD[@]} -eq 1 ]; then
                    exit 1
                fi
                continue
            fi
            BUILD_ARGS+=(--build-arg "BASE_TAG=${BASE_TAG}")
            echo "Using base bugzilla/${BASE_IMAGE}:${BASE_TAG} for ${IMAGE}"
        fi

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
        if $DOCKER build $CACHE "${BUILD_ARGS[@]}" -t "bugzilla/${IMAGE}:${DATE}.${ITER}" -f "docker/images/Dockerfile.${DOCKERFILE_IMAGE}" .; then
            echo
            echo_green "The build appears to have succeeded."

            # Only update literal pinned FROM references when building a base perl image.
            if [[ "$IMAGE" == "bugzilla-perl-slim" || "$IMAGE" == "bugzilla-perl-full" ]]; then
                echo "Updating FROM lines in Dockerfiles to use bugzilla/${IMAGE}:${DATE}.${ITER}..."
                echo

                for dockerfile in Dockerfile docker/images/Dockerfile.perl-testsuite; do
                    if [ ! -f "$dockerfile" ]; then
                        continue
                    fi
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
                done

                if [[ "$IMAGE" == "bugzilla-perl-slim" ]]; then
                    BUGZILLA_PERL_SLIM_TAG="${DATE}.${ITER}"
                    write_base_tags_file
                    echo "  Updated: ${TAG_FILE} (BUGZILLA_PERL_SLIM_TAG=${BUGZILLA_PERL_SLIM_TAG})"
                elif [[ "$IMAGE" == "bugzilla-perl-full" ]]; then
                    BUGZILLA_PERL_FULL_TAG="${DATE}.${ITER}"
                    write_base_tags_file
                    echo "  Updated: ${TAG_FILE} (BUGZILLA_PERL_FULL_TAG=${BUGZILLA_PERL_FULL_TAG})"
                fi
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
