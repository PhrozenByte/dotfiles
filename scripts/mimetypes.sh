#!/bin/bash
# mimetypes.sh
# Load default applications for MIME types from a JSON file.
#
# This script reads MIME type <> default application mappings from JSON files
# (pass filesystem paths as script arguments) and configures defaults via
# `xdg-mime default <application> <MIME type>`.
#
# Missing or uninstalled applications are ignored. If the first listed
# application is not installed, the next one is used as fallback.
# Wildcards can be used for both application names and MIME types.
#
# The JSON file must contain an object with the keys `"mimes"` and `"apps"`,
# defining default associations either by MIME type or by application. Entries
# are processed in order; the first available application is used as default,
# any following mapping of the same MIME type is ignored. MIME type aliases
# are resolved automatically.
#
# The `"mimes"` object maps a MIME type (e.g. `"text/plain"`) to an array of
# application names (e.g. `"org.gnome.TextEditor"`). Unknown MIME types are
# ignored, wildcards like `"application/vnd.ms-visio.*"` are supported and
# matched against the system's MIME database. Application names must match the
# basename of a `.desktop` file in `$XDG_DATA_DIRS/applications`. Wildcards
# like `"org.videolan.VLC-*"` are supported and match multiple applications.
# The first available application is used, following applications are ignored.
#
# The `"apps"` object maps an application name to an array of MIME types.
# Application names must match the basename of a `.desktop` file, wildcards
# are supported. MIME types may be specified verbatim (e.g. `"text/plain"`),
# or using wildcards such as `"text/*"`. The latter must match `MimeType=`
# entries in the application's `.desktop` file. Unknown applications, unknown
# MIME types, or already assigned MIME types are ignored.
#
# Example JSON file:
#
#     ```json
#     {
#         "mimes": {
#             "text/html": [ "org.mozilla.firefox", "firefox" ],
#             "application/xhtml+xml": [ "org.mozilla.firefox", "firefox" ],
#             "application/vnd.ms-visio.*": [ "ms-visio" ]
#         },
#         "apps": {
#             "org.gnome.TextEditor": [ "text/plain", "application/json" ],
#             "org.videolan.VLC-*": [ "*/*" ],
#             "org.videolan.VLC": [ "*/*" ]
#         }
#     }
#     ```
#
# This results in the following commands being executed:
#
#     ```sh
#     xdg-mime default firefox.desktop \
#         text/html application/xhtml+xml
#     xdg-mime default ms-viso.desktop \
#         vnd.ms-visio.drawing.main+xml.xml vnd.ms-visio.stencil.main+xml.xml …
#     xdg-mime default org.gnome.TextEditor.desktop \
#         text/plain application/json
#     xdg-mime default org.videolan.VLC.desktop \
#         audio/aac audio/ogg audio/mp3 audio/x-mpegurl video/ogg video/mp4 …
#     xdg-mime default org.videolan.VLC-openbd.desktop \
#         x-content/video-bluray
#     xdg-mime default org.videolan.VLC-opendvd.desktop \
#         x-content/video-dvd
#     ```
#
#
# Copyright (C) 2026 Daniel Rudolf (<https://www.daniel-rudolf.de>)
# License: The MIT License <http://opensource.org/licenses/MIT>
#
# SPDX-License-Identifier: MIT

set -eu -o pipefail
shopt -s nullglob
export LC_ALL=C.UTF-8

[ -x "$(type -p jq)" ] || { echo "Missing script dependency: jq" >&2; exit 1; }
[ -x "$(type -p awk)" ] || { echo "Missing script dependency: awk" >&2; exit 1; }
[ -x "$(type -p grep)" ] || { echo "Missing script dependency: grep" >&2; exit 1; }
[ -x "$(type -p sort)" ] || { echo "Missing script dependency: sort" >&2; exit 1; }
[ -x "$(type -p xdg-mime)" ] || { echo "Missing script dependency: xdg-mime" >&2; exit 1; }

export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share/:/usr/share/}"

quote() {
    local QUOTED=
    for ARG in "$@"; do
        [ "$(printf '%q' "$ARG")" == "$ARG" ] \
            && QUOTED+=" $ARG" \
            || QUOTED+=" ${ARG@Q}"
    done
    echo "${QUOTED:1}"
}

# print usage
if (( $# == 0 )); then
    echo "Usage:" >&2
    echo "    $(basename "${BASH_SOURCE[0]}") JSON_FILE..." >&2
    exit 1
fi

# prepare script
EXIT_CODE=0

declare -A OLD_MIMES=()
declare -A NEW_MIMES=()

__xdg-mime_query() {
    local APP="$(xdg-mime query default "$1" 2>/dev/null ||:)"
    [ -z "$APP" ] || basename "$APP" ".desktop"
}

# prepare applications
# discover all installed applications with '*.desktop' files
declare -A DESKTOP_FILES=()

while IFS= read -d: -r XDG_DATA_DIR; do
    [ -n "$XDG_DATA_DIR" ] && [ -d "${XDG_DATA_DIR%/}/applications" ] || continue

    for DESKTOP_FILE in "${XDG_DATA_DIR%/}/applications/"*".desktop"; do
        APP="$(basename "$DESKTOP_FILE" ".desktop")"
        [[ ! -v DESKTOP_FILES["$APP"] ]] || continue

        DESKTOP_FILES["$APP"]="$DESKTOP_FILE"
    done
done <<<"$XDG_DATA_HOME:$XDG_DATA_DIRS:"

(( ${#DESKTOP_FILES[@]} > 0 )) || { echo "No '.desktop' files found" >&2; exit 1; }

__resolve_app() {
    [ -n "$1" ] || return 0
    printf '%s\n' "${!DESKTOP_FILES[@]}" | grep -Fx "$(basename "$1" ".desktop")" ||:
}

__resolve_apps() {
    local RAW_APP="$1" APP=
    if [[ "$RAW_APP" == *\** ]]; then
        for APP in "${!DESKTOP_FILES[@]}"; do
            [[ "$APP" != $RAW_APP ]] || printf '%s\0' "$APP"
        done
    else
        APP="$(__resolve_app "$RAW_APP")"
        [ -z "$APP" ] || printf '%s\0' "$APP"
    fi
}

# prepare MIME types
# discover all known MIME types from the system's MIME database
MIME_DATABASES=0
declare -a ALL_MIMES=()
declare -A ALL_MIME_ALIASES=()

while IFS= read -u3 -d: -r XDG_DATA_DIR; do
    [ -n "$XDG_DATA_DIR" ] && [ -d "${XDG_DATA_DIR%/}/mime" ] || continue
    ((++MIME_DATABASES))

    if [ -f "${XDG_DATA_DIR%/}/mime/types" ]; then
        readarray -u4 -O${#ALL_MIMES[@]} -t ALL_MIMES \
            4<"${XDG_DATA_DIR%/}/mime/types"
    fi

    if [ -f "${XDG_DATA_DIR%/}/mime/aliases" ]; then
        while IFS=' ' read -u5 -r MIME_ALIAS MIME; do
            ALL_MIME_ALIASES["$MIME_ALIAS"]="$MIME"
        done 5<"${XDG_DATA_DIR%/}/mime/aliases"
    fi
done 3<<<"$XDG_DATA_HOME:$XDG_DATA_DIRS:"

(( ${#ALL_MIMES[@]} > 0 )) || { echo "No MIME database found" >&2; exit 1; }
(( MIME_DATABASES == 1 )) || readarray -t ALL_MIMES < <(printf '%s\n' "${ALL_MIMES[@]}" | sort -u)

__resolve_mime() {
    [ -n "$1" ] || return 0
    [[ ! -v ALL_MIME_ALIASES["$1"] ]] || { echo "${ALL_MIME_ALIASES[$1]}"; return; }
    printf '%s\n' "${ALL_MIMES[@]}" | grep -Fx "$1" ||:
}

__resolve_mimes() {
    local RAW_MIME="$1" MIME=
    if [[ "$RAW_MIME" == *\** ]]; then
        for MIME_ALIAS in "${!ALL_MIME_ALIASES[@]}"; do
            [[ "$MIME_ALIAS" != $RAW_MIME ]] || printf '%s\0' "${ALL_MIME_ALIASES[$MIME_ALIAS]}"
        done
        for MIME in "${ALL_MIMES[@]}"; do
            [[ "$MIME" != $RAW_MIME ]] || printf '%s\0' "$MIME"
        done
    else
        MIME="$(__resolve_mime "$RAW_MIME")"
        [ -z "$MIME" ] || printf '%s\0' "$MIME"
    fi
}

__resolve_app_mimes() {
    local APP="$1" DESKTOP_FILE="${DESKTOP_FILES[$APP]}"
    local RAW_MIME="$2" MIME=

    if [[ "$RAW_MIME" == *\** ]]; then
        while IFS= read -u9 -r MIME; do
            MIME="$(__resolve_mime "$MIME")"
            [ -n "$MIME" ] || continue

            [[ "$MIME" != $RAW_MIME ]] || printf '%s\0' "$MIME"
        done 9< <(awk -F= '/^MimeType=/ { split($2, a, ";"); for (i in a) print a[i] }' "$DESKTOP_FILE")
    else
        MIME="$(__resolve_mime "$RAW_MIME")"
        [ -z "$MIME" ] || printf '%s\0' "$MIME"
    fi
}

# process JSON files
for CONFIG_FILE in "$@"; do
    [ -e "$CONFIG_FILE" ] \
        || { echo "Invalid JSON file ${CONFIG_FILE@Q}: No such file or directory" >&2; EXIT_CODE=1; continue; }
    [ -f "$CONFIG_FILE" ] \
        || { echo "Invalid JSON file ${CONFIG_FILE@Q}: Not a file" >&2; EXIT_CODE=1; continue; }
    [ -r "$CONFIG_FILE" ] \
        || { echo "Invalid JSON file ${CONFIG_FILE@Q}: Permission denied" >&2; EXIT_CODE=1; continue; }
    jq -e 'type == "object"' "$CONFIG_FILE" >/dev/null \
        || { echo "Invalid JSON file ${CONFIG_FILE@Q}: Not a valid JSON file" >&2; EXIT_CODE=1; continue; }

    # register associations by MIME type
    while IFS=$'\t' read -u3 -r RAW_MIME ENTRY; do
        # support wildcards in MIME types, e.g., 'application/vnd.ms-visio.*'
        # make sure to use constrictive patterns, otherwise you might match unrelated MIME types
        # MIME types are matched against the system's MIME database, duplicates are possible due to aliases
        # unknown MIME types are silently ignored
        readarray -u4 -d '' -t MIMES 4< <(__resolve_mimes "$RAW_MIME")

        for MIME in "${MIMES[@]}"; do
            # skip MIME types that have been updated already
            [[ ! -v NEW_MIMES["$MIME"] ]] || continue

            # remember old default application, if any
            [[ -v OLD_MIMES["$MIME"] ]] \
                || OLD_MIMES["$MIME"]="$(__xdg-mime_query "$MIME")"

            while IFS= read -u5 -r RAW_APP; do
                # support wildcards in application names, e.g., 'org.videolan.VLC-*'
                # application names are matched against the basename of '*.desktop' files
                # unknown applications are silently ignored
                readarray -u6 -d '' -t APPS 6< <(__resolve_apps "$RAW_APP")

                for APP in "${APPS[@]}"; do
                    # set new default application for that MIME type
                    NEW_MIMES["$MIME"]="$APP"
                    break 2
                done
            done 5< <(jq -r '.[]' <<<"$ENTRY")
        done
    done 3< <(jq -r '.mimes | to_entries[] | "\(.key)\t\(.value | tojson)"' "$CONFIG_FILE")

    # register associations by application
    while IFS=$'\t' read -u3 -r RAW_APP ENTRY; do
        # resolve application names
        readarray -u4 -d '' -t APPS 4< <(__resolve_apps "$RAW_APP")

        while IFS= read -u5 -r RAW_MIME; do
            for APP in "${APPS[@]}"; do
                # resolve MIME types
                # support wildcards, but match MIME types that are supported by the application only
                # as verbatim MIME type one can specify any MIME type known to the system
                readarray -u6 -d '' -t MIMES 6< <(__resolve_app_mimes "$APP" "$RAW_MIME")

                for MIME in "${MIMES[@]}"; do
                    # skip MIME types that have been updated already
                    [[ ! -v NEW_MIMES["$MIME"] ]] || continue

                    # remember old default application, if any
                    [[ -v OLD_MIMES["$MIME"] ]] \
                        || OLD_MIMES["$MIME"]="$(__xdg-mime_query "$MIME")"

                    # set new default application for that MIME type
                    NEW_MIMES["$MIME"]="$APP"
                done
            done
        done 5< <(jq -r '.[]' <<<"$ENTRY")
    done 3< <(jq -r '.apps | to_entries[] | "\(.key)\t\(.value | tojson)"' "$CONFIG_FILE")

    # register new default applications per MIME type and report changes
    while IFS= read -r MIME; do
        OLD_APP="${OLD_MIMES[$MIME]}"
        NEW_APP="${NEW_MIMES[$MIME]:-}"

        if [ -n "$NEW_APP" ]; then
            [ -z "$OLD_APP" ] \
                && printf '[%s] %s %s (%s)\n' "+" "$MIME" "$NEW_APP" "added" \
                || { [ "$NEW_APP" == "$OLD_APP" ] \
                    && printf '[%s] %s %s (%s)\n' " " "$MIME" "$NEW_APP" "unchanged" \
                    || printf '[%s] %s %s -> %s (%s)\n' "#" "$MIME" "$OLD_APP" "$NEW_APP" "updated"; }

            MIME_RETURN_CODE=0
            xdg-mime default "$NEW_APP.desktop" "$MIME" || MIME_RETURN_CODE=$?
            if (( MIME_RETURN_CODE != 0 )); then
                echo "\`$(quote default "$NEW_APP.desktop" "$MIME")\` failed with rc $MIME_RETURN_CODE" >&2
                EXIT_CODE=1
                continue
            fi
        else
            [ -z "$OLD_APP" ] \
                && printf '[%s] %s (%s)\n' "?" "$MIME" "unknown" \
                || printf '[%s] %s %s (%s)\n' "!" "$MIME" "$OLD_APP" "no app"
        fi
    done < <(printf '%s\n' "${!OLD_MIMES[@]}" | sort)
done

exit $EXIT_CODE
