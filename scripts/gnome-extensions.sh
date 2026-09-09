#!/bin/bash
# gnome-extensions.sh
# Installs GNOME Shell extensions directly from extensions.gnome.org.
#
# This script takes GNOME Shell extension UUIDs as arguments and fetches,
# downloads, and installs the latest version on `extensions.gnome.org` that is
# compatible with the locally installed GNOME Shell version.
#
# Note that GNOME Shell will not automatically discover and activate newly
# installed extensions within the current session. In practice, this requires
# a logout/login cycle (or a full Shell restart on X11 systems).
#
# This is a consequence of GNOME's deliberate decisions. There is no technical
# reason that would prevent GNOME Shell from immediately discovering and
# loading newly installed extensions with a CLI workflow. There is a D-Bus
# interface that allows for downloading and installing extensions directly from
# `extensions.gnome.org`, but the D-Bus interface is an absolute mess and,
# while asking for user confirmation (which is fine per se), there is no way
# to wait for the user's decision or completion state. As a result, batch
# installation is not possible with the D-Bus interface either.
#
# Since this worked before, it's yet another example of how some individuals on
# the GNOME staff don't care about users or other devs. Requiring a full
# logout/login cycle is no oversight of this script, but a deliberate decision
# of some individuals, even though others have provided the necessary code and
# pledged to support it. So, thank these individuals on GNOME staff.
#
# Copyright (C) 2026 Daniel Rudolf (<https://www.daniel-rudolf.de>)
# License: The MIT License <http://opensource.org/licenses/MIT>
#
# SPDX-License-Identifier: MIT

set -eu -o pipefail
export LC_ALL=C.UTF-8

[ -x "$(type -p jq)" ] || { echo "Missing script dependency: jq" >&2; exit 1; }
[ -x "$(type -p sed)" ] || { echo "Missing script dependency: sed" >&2; exit 1; }
[ -x "$(type -p grep)" ] || { echo "Missing script dependency: grep" >&2; exit 1; }
[ -x "$(type -p curl)" ] || { echo "Missing script dependency: curl" >&2; exit 1; }
[ -x "$(type -p gnome-shell)" ] || { echo "Missing script dependency: gnome-shell" >&2; exit 1; }
[ -x "$(type -p gnome-extensions)" ] || { echo "Missing script dependency: gnome-extensions" >&2; exit 1; }

quote() {
    local QUOTED=
    for ARG in "$@"; do
        [ "$(printf '%q' "$ARG")" == "$ARG" ] \
            && QUOTED+=" $ARG" \
            || QUOTED+=" ${ARG@Q}"
    done
    echo "${QUOTED:1}"
}

cmd() {
    echo + "$(quote "$@")" >&2
    "$@"
}

urlencode() {
    local SEP="$1"; shift
    printf '%s\n' "$@" | jq -R '@uri' | jq -rs --arg sep "$SEP" 'join($sep)'
}

# print usage
if (( $# == 0 )); then
    echo "Usage:" >&2
    echo "    $(basename "${BASH_SOURCE[0]}") EXTENSION_UUID..." >&2
    exit 1
fi

# prepare script
EXIT_CODE=0

__curl_json() {
    local RESPONSE RETURN_CODE
    RESPONSE="$(curl -sSf -L -H "Accept: application/json" "$@")"
    RETURN_CODE=$?

    [ $RETURN_CODE -eq 0 ] || return $RETURN_CODE

    if ! jq -e '.' &>/dev/null <<<"$RESPONSE"; then
        echo "curl: (22) The requested URL '${@: -1}' returned a malformed JSON response" >&2
        printf '%s\n' "$RESPONSE" >&2
        RETURN_CODE=22
    fi

    printf '%s\n' "$RESPONSE"
    return $RETURN_CODE
}

__latest_version() {
    local EXTENSION="$1"
    local SHELL_VERSION="$2"

    # request all versions from extensions.gnome.org
    local RESPONSE RETURN_CODE
    RESPONSE="$(__curl_json "https://extensions.gnome.org/$(urlencode "/" api v1 extensions "$EXTENSION" versions)/?page=1&page_size=100")"
    RETURN_CODE=$?

    [ $RETURN_CODE -eq 0 ] || return $RETURN_CODE

    # prepare results for pagination
    local RESULT NEXT NEXT_RESULT
    RESULT="$(jq -c '.results // []' <<<"$RESPONSE")"

    # request following pages and append to results
    NEXT="$(jq -r '.next // empty' <<<"$RESPONSE")"
    while [ -n "$NEXT" ]; do
        NEXT_RESULT="$(__curl_json "$NEXT")"
        [ $? -eq 0 ] || return 1

        RESULT="$(jq -s 'add' <<<"$RESULT$(jq -c '.results // []' <<<"$NEXT_RESULT")")"
        NEXT="$(jq -r '.next // empty' <<<"$NEXT_RESULT")"
    done

    # print latest compatible version published on extensions.gnome.org
    # `.shell_versions[]` describes compatible versions split by components with `-1` being a wildcard, i.e., objects
    # like `{ "major": 50, "minor": -1, "patch": -1 }` mean that the version is compatible with GNOME Shell 50.*
    # `.status == 3` checks for status "active", i.e., the version was successfully reviewed by GNOME staff
    jq -r --argjson version "$(jq -c -n --arg version "$SHELL_VERSION" '$version | split(".") | map(tonumber)')" '
        def matches($version): [.[]] as $match | ($match | to_entries | all(.value == -1 or .value == $version[.key]));
        map(select(.status == 3 and (.shell_versions[] | matches($version)))) | map(.version) | last
    ' <<<"$RESULT"
}

# get GNOME Shell version
SHELL_VERSION="$(gnome-shell --version | grep -o '[0-9]\+\(\.[0-9]\+\)\+')"
[ -n "$SHELL_VERSION" ] || { echo "Failed to determine GNOME Shell version" >&2; exit 1; }

# create temporary downloads folder
DOWNLOAD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gnome-extensions.XXXXXX")"
quote + mkdir "$DOWNLOAD_DIR" >&2

for EXTENSION in "$@"; do
    if ! gnome-extensions list | grep -Fxq "$EXTENSION"; then
        # extension wasn't installed yet
        # fetch metadata about the requested extension from extensions.gnome.org
        INFO="$(__curl_json "https://extensions.gnome.org/$(urlencode "/" api v1 extensions "$EXTENSION")/")"
        [ -n "$INFO" ] || { echo "Remote extension not found: $EXTENSION" >&2; EXIT_CODE=1; continue; }

        # get printable name and latest compatible version
        NAME="$(jq -r '.name // empty' <<<"$INFO")"
        VERSION="$(__latest_version "$EXTENSION" "$SHELL_VERSION")"
        [ -n "$VERSION" ] || { echo "No compatible version of ${EXTENSION@Q} found" >&2; EXIT_CODE=1; continue; }

        # download the extension's ZIP archive with `curl`
        echo "Installing ${NAME@Q} v$VERSION ($EXTENSION)..."
        cmd curl -f -L -H 'Accept: application/zip' -o "$DOWNLOAD_DIR/$EXTENSION.zip" \
            "https://extensions.gnome.org/$(urlencode "/" api v1 extensions "$EXTENSION" versions "$VERSION")/?format=zip" \
            || { echo "Failed to download ${EXTENSION@Q}: \`curl\` failed with rc $?" >&2; EXIT_CODE=1; continue; }

        # install extension with `gnome-extensions install`
        cmd gnome-extensions install --force "$DOWNLOAD_DIR/$EXTENSION.zip" \
            || { echo "\`gnome-extensions install\` failed with rc $?" >&2; EXIT_CODE=1; continue; }

        # alternative approach using the official DBus interface
        # however, this will quit prematurely and there's no way to wait for user confirmation
        # thus it's basically impossible to batch install multiple extensions right after another
        # gdbus call --session --dest org.gnome.Shell.Extensions --object-path /org/gnome/Shell/Extensions \
        #     --method org.gnome.Shell.Extensions.InstallRemoteExtension "$EXTENSION"
    else
        # extension is installed already
        INFO="$(LC_ALL=C gnome-extensions info "$EXTENSION")"
        [ -n "$INFO" ] || { echo "Local extension not found: $EXTENSION" >&2; EXIT_CODE=1; continue; }

        # get printable name and installed version
        NAME="$(sed -ne 's/^  Name: \(.*\)$/\1/p' <<<"$INFO")"
        VERSION="$(sed -ne 's/^  Version: \(.*\)$/\1/p' <<<"$INFO")"

        if ! gnome-extensions list --active | grep -Fxq "$EXTENSION"; then
            # extension is installed, but inactive
            # enable extension with `gnome-extensions enable`
            echo "Enabling ${NAME@Q} v$VERSION ($EXTENSION)..."
            cmd gnome-extensions enable "$EXTENSION" \
                || { echo "\`gnome-extensions enable\` failed with rc $?" >&2; EXIT_CODE=1; continue; }
        else
            # extension is installed and enabled
            # nothing to do here...
            echo "Skipping already enabled ${NAME@Q} v$VERSION ($EXTENSION)..."
        fi
    fi
done

# delete download folder
cmd rm -r "$DOWNLOAD_DIR"

exit $EXIT_CODE
