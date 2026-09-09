#!/bin/bash
# gitconfig.sh
# Updates ~/.gitconfig.d/* config files from JSON files.
#
# This script reads Git config values from JSON files (passed as arguments)
# and writes them to the local user's Git config. The config is split into
# a global user config and optional per-remote configs.
#
# Example JSON file:
#
# ```json
# {
#     "config": {
#         "user": { "name": "Daniel Rudolf" }
#     },
#     "remotes": [
#         {
#             "includeFile": "github.com",
#             "remoteUrlPattern": [
#                 "git@github.com:*/**"
#             ],
#             "config": {
#                 "user": { "name": "PhrozenByte" }
#             }
#         }
#     ]
# }
# ```
#
# The JSON file can contain a `"config"` object whose scalar values are written
# to `~/.gitconfig.d/user`. Nested objects are converted to Git's dotted-key
# notation. In the example above, it will write `user.name = Daniel Rudolf`
# to `~/.gitconfig.d/user`. Consequently, Git will use "Daniel Rudolf" as the
# default commit author name.
#
# The optional `"remotes"` key contains a list of remote-specific config
# objects. Each entry must define an `"includeFile"` filename and at least one
# `"remoteUrlPattern"`. The patterns are used to create conditional Git config
# includes in `~/.gitconfig.d/remotes`. The corresponding `"config"` object is
# written to `~/.gitconfig.d/remotes.d/<includeFile>`, using the same syntax
# as the global `"config"` object.
#
# Git therefore conditionally loads the appropriate remote-specific config
# based on the URL of the repository's remote. This can be used, for example,
# to use different Git identities or signing keys for different hosting
# providers while keeping the config in a single JSON source file.
#
# In the example above, the script will write `user.name = PhrozenByte` to
# `~/.gitconfig.d/remotes.d/github.com`. This file is conditionally included
# via `~/.gitconfig.d/remotes` when any of a repository's remote URLs matches
# `git@github.com:*/**`. Consequently, Git will use "PhrozenByte" as the
# default commit author name for matching repositories.
#
# Overall, the above example results in a global Git identity and a separate
# identity for repositories whose remote URLs match the configured patterns.
#
# To actually use the config files created by this script, add the following
# includes to your `~/.gitconfig`:
#
# ```
# [include]
#     path = ~/.gitconfig.d/user
# [include]
#     path = ~/.gitconfig.d/remotes
# ```
#
# Multiple JSON files may be passed at once. They are processed in the order
# given on the command line; later files may therefore override configuration
# values written by earlier files.
#
# Copyright (C) 2026 Daniel Rudolf (<https://www.daniel-rudolf.de>)
# License: The MIT License <http://opensource.org/licenses/MIT>
#
# SPDX-License-Identifier: MIT

set -eu -o pipefail
export LC_ALL=C.UTF-8

[ -x "$(type -p jq)" ] || { echo "Missing script dependency: jq" >&2; exit 1; }
[ -x "$(type -p git)" ] || { echo "Missing script dependency: git" >&2; exit 1; }

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

# print usage
if (( $# == 0 )); then
    echo "Usage:" >&2
    echo "    $(basename "${BASH_SOURCE[0]}") JSON_FILE..." >&2
    exit 1
fi

# prepare script
EXIT_CODE=0

__git() {
    cmd git "$@" \
        || { echo "\`$(quote git "$@")\` failed with rc $?" >&2; EXIT_CODE=1; return 1; }
}

__invalid_remote() {
    local CONFIG_FILE="$1" INDEX="$2"
    echo "Invalid remote config #$((INDEX-1)) in ${CONFIG_FILE@Q}:" "${@:3}" >&2
    EXIT_CODE=1
}

# create ~/.gitconfig.d directory, if necessary
[ ! -e ~/.gitconfig.d ] && cmd mkdir ~/.gitconfig.d \
    || { [ -d ~/.gitconfig.d ] \
        || { echo "Invalid '~/.gitconfig.d' directory: Not a directory" >&2; exit 1; }; }

# create ~/.gitconfig.d/user file, if necessary
[ ! -e ~/.gitconfig.d/user ] && cmd touch ~/.gitconfig.d/user \
    || { [ -f ~/.gitconfig.d/user ] \
        || { echo "Invalid '~/.gitconfig.d/user' file: Not a file" >&2; exit 1; }; }

# create ~/.gitconfig.d/remotes file, if necessary
[ ! -e ~/.gitconfig.d/remotes ] && cmd touch ~/.gitconfig.d/remotes \
    || { [ -f ~/.gitconfig.d/remotes ] \
        || { echo "Invalid '~/.gitconfig.d/remotes' file: Not a file" >&2; exit 1; }; }

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

    # update user config in ~/.gitconfig.d/user
    while IFS=$'\t' read -r KEY VALUE; do
        __git config set --file ~/.gitconfig.d/user \
            "$KEY" "$VALUE"
    done < <(jq -r '.config | paths(scalars) as $p | [($p | join(".")), (getpath($p))] | @tsv' "$CONFIG_FILE")

    # update Git remotes in ~/.gitconfig.d/remotes
    if jq -e '.remotes | length > 0' "$CONFIG_FILE" &>/dev/null; then
        # create ~/.gitconfig.d/remotes.d directory, if necessary
        [ ! -e ~/.gitconfig.d/remotes.d ] && cmd mkdir ~/.gitconfig.d/remotes.d \
            || { [ -d ~/.gitconfig.d/remotes.d ] \
                || { echo "Invalid '~/.gitconfig.d/remotes.d' directory: Not a directory" >&2; exit 1; }; }

        INDEX=0
        while IFS= read -u3 -r ENTRY; do
            ((++INDEX))

            # get filename within ~/.gitconfig.d/remotes.d directory
            FILENAME="$(jq -r '.includeFile // empty' <<<"$ENTRY")"
            [[ "$FILENAME" =~ ^[^/]+$ ]] \
                || { __invalid_remote "$CONFIG_FILE" "$INDEX" "Invalid filename given"; continue; }

            # read remote URL pattern
            readarray -t URL_PATTERNS < <(jq -r '.remoteUrlPattern[]?' <<<"$ENTRY")
            (( ${#URL_PATTERNS[@]} > 0 )) \
                || { __invalid_remote "$CONFIG_FILE" "$INDEX" "No remote URL pattern given"; continue; }

            # write includeIf declarations matching the given remote URL pattern to ~/.gitconfig.d/remotes
            for URL_PATTERN in "${URL_PATTERNS[@]}"; do
                __git config set --file ~/.gitconfig.d/remotes \
                    includeIf."hasconfig:remote.*.url:$URL_PATTERN".path "~/.gitconfig.d/remotes.d/$FILENAME"
            done

            # write Git config to the remote's config file below ~/.gitconfig.d/remotes
            # `git config set --file` will create the file if it doesn't exist yet
            while IFS=$'\t' read -u4 -r KEY VALUE; do
                __git config set --file ~/.gitconfig.d/remotes.d/"$FILENAME" \
                    "$KEY" "$VALUE"
            done 4< <(jq -r '.config | paths(scalars) as $p | [($p | join(".")), (getpath($p))] | @tsv' <<<"$ENTRY")
        done 3< <(jq -c '.remotes[]' "$CONFIG_FILE")
    fi
done

exit $EXIT_CODE
