#!/bin/bash
# gsettings.sh
# Loads GSettings and dconf configuration values from a JSON file.
#
# This script reads GSettings and dconf configuration values from a JSON file
# (pass a filesystem path as the only argument) and applies them to the local
# system. It optionally supports Flatpak applications, does not fail when a
# GSettings schema does not exist, and supports relocatable schemas.
#
# The JSON file must contain an object with the keys `"gsettings"` and
# `"dconf"`, each mapping to an array of objects. The script executes the
# corresponding `gsettings` and `dconf` commands accordingly.
#
# `"dconf"` objects must define a `"path"` key specifying the exact dconf path,
# and optionally a `"value"` key containing the value to set. If `"value"` is
# not provided, the corresponding path is reset to its default value. An
# optional `"flatpak"` key enables execution inside a Flatpak sandbox (if the
# Flatpak is installed). Note that only a few Flatpaks support `dconf`; most
# support only `gsettings`.
#
# `"gsettings"` objects must define the `"schema"` and `"key"` keys, specifying
# the GSettings schema and key to modify. If the schema does not exist (e.g.
# the application is not installed), the entry is silently skipped. The
# optional `"value"` and `"flatpak"` keys behave the same as for `dconf`
# objects. For relocatable schemas, a `"path"` key may be provided; otherwise
# it must be omitted. The `"path"` may include a single `*` placeholder
# segment. The actual value is derived from the then required
# `"pathPlaceholder"` object, which must contain `"schema"` and `"key"` keys,
# using the same semantics as described above.
#
# Example JSON file:
#
#     ```json
#     {
#         "gsettings": [
#             {
#                 "schema": "org.gnome.desktop.interface",
#                 "key": "gtk-enable-primary-paste",
#                 "value": true
#             },
#             {
#                 "flatpak": "app.devsuite.Ptyxis",
#                 "schema": "org.gnome.Ptyxis",
#                 "key": "default-columns",
#                 "value": 120
#             },
#             {
#                 "flatpak": "app.devsuite.Ptyxis",
#                 "schema": "org.gnome.Ptyxis.Profile",
#                 "key": "limit-scrollback",
#                 "value": false,
#                 "path": "/org/gnome/Ptyxis/Profiles/*/",
#                 "pathPlaceholder": {
#                     "schema": "org.gnome.Ptyxis",
#                     "key": "profile-uuids"
#                 }
#             }
#         ],
#         "dconf": [
#             {
#                 "path": "/org/gnome/shell/extensions/notifications-alert/color",
#                 "value": "'rgb(255,120,0)'"
#             }
#         ]
#     }
#     ```
#
# This results in the following commands being executed:
#
#     ```sh
#     gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true
#     flatpak run --command=gsettings app.devsuite.Ptyxis set org.gnome.Ptyxis default-columns 120
#     flatpak run --command=gsettings app.devsuite.Ptyxis set \
#         org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/6006f04d727b5abe611b17b06a0081a8/ limit-scrollback false
#     dconf write /org/gnome/shell/extensions/notifications-alert/color "'rgb(255,120,0)'"
#     ```
#
# Copyright (C) 2026 Daniel Rudolf (<https://www.daniel-rudolf.de>)
# License: The MIT License <http://opensource.org/licenses/MIT>
#
# SPDX-License-Identifier: MIT

set -eu -o pipefail
export LC_ALL=C.UTF-8

[ -x "$(type -p jq)" ] || { echo "Missing script dependency: jq" >&2; exit 1; }
[ -x "$(type -p awk)" ] || { echo "Missing script dependency: awk" >&2; exit 1; }
[ -x "$(type -p sed)" ] || { echo "Missing script dependency: sed" >&2; exit 1; }
[ -x "$(type -p grep)" ] || { echo "Missing script dependency: grep" >&2; exit 1; }
[ -x "$(type -p dconf)" ] || { echo "Missing script dependency: dconf" >&2; exit 1; }
[ -x "$(type -p gsettings)" ] || { echo "Missing script dependency: gsettings" >&2; exit 1; }

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

declare -a FLATPAKS=()
if [ -x "$(type -p flatpak)" ]; then
    readarray -t FLATPAKS < <(flatpak list --app --columns=application)
fi

readarray -t HOST_SCHEMAS < <(gsettings list-schemas 2>/dev/null)
if (( ${#HOST_SCHEMAS[@]} == 0 )); then
    echo "Failed to discover GSettings schemas: Is D-Bus running?" >&2
    exit 1
fi

__report() {
    local INFO="$1"
    [ -z "$FLATPAK" ] || INFO+=" (Flatpak $FLATPAK)"
    [ "$2" == "$3" ] \
        && printf '[%s] %s %s (unchanged)\n' " " "$INFO" "$3" \
        || printf '[%s] %s %s -> %s (updated)\n' "#" "$INFO" "$2" "$3"
}

# dconf helper functions
__dconf() {
    local CMD=( dconf "$@" )
    [ -z "$FLATPAK" ] || CMD=( flatpak run --command=dconf "$FLATPAK" "$@" )

    local RETURN_CODE=0
    "${CMD[@]}" || RETURN_CODE=$?

    if (( RETURN_CODE != 0 )); then
        echo "\`$(quote "${CMD[@]}")\` failed with rc $RETURN_CODE" >&2
        EXIT_CODE=1
        return 1
    fi
}

__dconf_read() {
    if [ -n "$FLATPAK" ]; then
        flatpak run --command=dconf "$FLATPAK" read "$@" 2>/dev/null ||:
    else
        dconf read "$@" 2>/dev/null ||:
    fi
}

__dconf_invalid() {
    local CONFIG_FILE="$1" INDEX="$2"
    echo "Invalid dconf entry #$((INDEX-1)) in ${CONFIG_FILE@Q}:" "${@:3}" >&2
    EXIT_CODE=1
}

# gsettings helper functions
__gsettings() {
    local CMD=( gsettings "$@" )
    [ -z "$FLATPAK" ] || CMD=( flatpak run --command=gsettings "$FLATPAK" "$@" )

    local RETURN_CODE=0
    "${CMD[@]}" || RETURN_CODE=$?

    if (( RETURN_CODE != 0 )); then
        echo "\`$(quote "${CMD[@]}")\` failed with rc $RETURN_CODE" >&2
        EXIT_CODE=1
        return 1
    fi
}

__gsettings_get() {
    if [ -n "$FLATPAK" ]; then
        flatpak run --command=gsettings "$FLATPAK" get "$@" 2>/dev/null ||:
    else
        gsettings get "$@" 2>/dev/null ||:
    fi
}

__gsettings_invalid() {
    local CONFIG_FILE="$1" INDEX="$2"
    echo "Invalid gsettings entry #$((INDEX-1)) in ${CONFIG_FILE@Q}:" "${@:3}" >&2
    EXIT_CODE=1
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

    # parse dconf
    INDEX=0
    while IFS= read -r ENTRY; do
        ((++INDEX))

        # check whether optional Flatpak is installed, otherwise fallback to host
        FLATPAK="$(jq -r '.flatpak // empty' <<<"$ENTRY")"
        [ -z "$FLATPAK" ] || printf '%s\n' "${FLATPAKS[@]}" | grep -Fxq "$FLATPAK" \
            || FLATPAK=""

        # read required path
        SCHEMA_PATH="$(jq -r '.path // empty' <<<"$ENTRY")"
        [[ "$SCHEMA_PATH" =~ ^(/[a-zA-Z0-9_-]+)+$ ]] \
            || { __dconf_invalid "$CONFIG_FILE" "$INDEX" "Malformed path given"; continue; }

        # read current value
        OLD_VALUE="$(__dconf_read "$SCHEMA_PATH")"

        # write given value, or reset to default value otherwise
        if jq -e '.value != null' <<<"$ENTRY" >/dev/null; then
            VALUE="$(jq -r '.value' <<<"$ENTRY")"
            __dconf write "$SCHEMA_PATH" "$VALUE" \
                || continue
        else
            __dconf reset "$SCHEMA_PATH" \
                || continue
        fi

        # report whether the value was changed
        __report "$SCHEMA_PATH" "$OLD_VALUE" "$(__dconf_read "$SCHEMA_PATH")"
    done < <(jq -c '.dconf[]?' "$CONFIG_FILE")

    # parse gsettings
    INDEX=0
    while IFS= read -r ENTRY; do
        ((++INDEX))

        # check whether optional Flatpak is installed, otherwise fallback to host
        FLATPAK="$(jq -r '.flatpak // empty' <<<"$ENTRY")"
        [ -z "$FLATPAK" ] || printf '%s\n' "${FLATPAKS[@]}" | grep -Fxq "$FLATPAK" \
            || FLATPAK=""

        # read required schema
        SCHEMA="$(jq -r '.schema // empty' <<<"$ENTRY")"
        [ -n "$SCHEMA" ] \
            || { __gsettings_invalid "$CONFIG_FILE" "$INDEX" "No schema given"; continue; }

        # skip host system entry when the required schema isn't installed
        [ -n "$FLATPAK" ] || printf '%s\n' "${HOST_SCHEMAS[@]}" | grep -Fxq "$SCHEMA" \
            || continue

        # read optional path (template)
        SCHEMA_PATH="$(jq -r '.path // empty' <<<"$ENTRY")"
        [[ "$SCHEMA_PATH" =~ ^(/(([a-zA-Z0-9_-]+|\*)/)*)?$ ]] \
            || { __gsettings_invalid "$CONFIG_FILE" "$INDEX" "Malformed path given"; continue; }

        # concatenate schema and optional path, possibly evaluate a path template
        SCHEMA_PATHS=()
        if [ -z "$SCHEMA_PATH" ]; then
            # no path was given
            SCHEMA_PATHS=( "$SCHEMA" )
        elif [[ "$SCHEMA_PATH" != */\*/* ]]; then
            # given path is no template, use it as-is
            SCHEMA_PATHS=( "$SCHEMA:$SCHEMA_PATH" )
        else
            # given path is a template
            # read now required placeholder info
            SCHEMA_PATH_VAR_SCHEMA="$(jq -r '.pathPlaceholder.schema // empty' <<<"$ENTRY")"
            SCHEMA_PATH_VAR_KEY="$(jq -r '.pathPlaceholder.key // empty' <<<"$ENTRY")"
            [ -n "$SCHEMA_PATH_VAR_SCHEMA" ] && [ -n "$SCHEMA_PATH_VAR_KEY" ] \
                || { __gsettings_invalid "$CONFIG_FILE" "$INDEX" \
                    "Path template given, but placeholder information is missing"; continue; }

            # read placeholder values
            SCHEMA_PATH_VAR="$(__gsettings_get "$SCHEMA_PATH_VAR_SCHEMA" "$SCHEMA_PATH_VAR_KEY")"
            [[ "$SCHEMA_PATH_VAR" =~ ^\[?(\'[a-zA-Z0-9_-]+\'(, \'[a-zA-Z0-9_-]+\')*)\]?$ ]] \
                || { __gsettings_invalid "$CONFIG_FILE" "$INDEX" \
                    "Invalid raw placeholder data for path template: $SCHEMA_PATH_VAR"; continue; }

            # construct paths by replacing the placeholder
            while IFS= read -r SCHEMA_PATH_VAR; do
                SCHEMA_PATHS+=( "$SCHEMA:$(awk -F/ -v var="$SCHEMA_PATH_VAR" \
                    'BEGIN { OFS="/" } { for (i=1; i<=NF; i++) { if ($i == "*") { $i = var } } print }' \
                    <<<"$SCHEMA_PATH")" )
            done < <(sed "s/'//g; s/, /\n/g" <<<"${BASH_REMATCH[1]}")
        fi

        # read required key
        KEY="$(jq -r '.key // empty' <<<"$ENTRY")"
        [ -n "$KEY" ] || { __gsettings_invalid "$CONFIG_FILE" "$INDEX" "No key given"; continue; }

        # read optional value; then either set given value, or reset to default value
        VALUE="$(jq -r '.value' <<<"$ENTRY")"
        VALUE_RESET="$(jq '.value == null // empty' <<<"$ENTRY")"

        for SCHEMA_PATH in "${SCHEMA_PATHS[@]}"; do
            # read current value
            OLD_VALUE="$(__gsettings_get "$SCHEMA_PATH" "$KEY")"

            # set given value, or reset to default value otherwise
            if [ -z "$VALUE_RESET" ]; then
                __gsettings set "$SCHEMA_PATH" "$KEY" "$VALUE" \
                    || continue
            else
                __gsettings reset "$SCHEMA_PATH" "$KEY" \
                    || continue
            fi

            # report whether the value was changed
            __report "$SCHEMA_PATH $KEY" "$OLD_VALUE" "$(__gsettings_get "$SCHEMA_PATH" "$KEY")"
        done
    done < <(jq -c '.gsettings[]?' "$CONFIG_FILE")
done

exit $EXIT_CODE
