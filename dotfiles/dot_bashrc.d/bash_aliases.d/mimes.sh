# list mime types by application
if [ -x "$(type -p xdg-mime)" ]; then
    xdg-mime-app() {
        (( $# == 1 )) || { echo "Usage:" >&2; echo "    xdg-mime-app APPLICATION_NAME" >&2; return 1; }
        [ -n "$1" ] && [[ "$1" != */* ]] || { echo "Invalid application name: $1" >&2; return 1; }
        local APP="$(basename "$1" ".desktop")"

        local DESKTOP_FILE= XDG_DATA_DIR=
        while IFS= read -d: -r XDG_DATA_DIR; do
            [ -z "$XDG_DATA_DIR" ] || [ ! -e "${XDG_DATA_DIR%/}/applications/$APP.desktop" ] \
                || DESKTOP_FILE="${XDG_DATA_DIR%/}/applications/$APP.desktop"
        done <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share/:/usr/share/}:"

        [ -n "$DESKTOP_FILE" ] || { echo "Unable to locate '.desktop' file for application: $APP" >&2; return 1; }
        [ -f "$DESKTOP_FILE" ] || { echo "Invalid desktop file ${DESKTOP_FILE@Q}: Not a file" >&2; return 1; }

        local MIMETYPE=
        while read -r MIMETYPE; do
            [ -z "$MIMETYPE" ] || echo "$MIMETYPE"
        done < <(awk -F= '/^MimeType=/ { split($2, a, ";"); for (i in a) print a[i] }' "$DESKTOP_FILE")
    }

    xdg-mime-defaults() {
        local XDG_DATA_DIR
        local -a MIMETYPES=()
        while IFS= read -d: -r XDG_DATA_DIR; do
            [ -z "$XDG_DATA_DIR" ] || [ ! -f "${XDG_DATA_DIR%/}/mime/types" ] \
                || readarray -O${#MIMETYPES[@]} -t MIMETYPES <"${XDG_DATA_DIR%/}/mime/types"
        done <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share/:/usr/share/}:"
        readarray -t MIMETYPES < <(printf '%s\n' "${MIMETYPES[@]}" | sort -u)

        local APPLICATION= MIMETYPE=
        local -A APPLICATIONS=()
        for MIMETYPE in "${MIMETYPES[@]}"; do
            APPLICATION="$(basename "$(xdg-mime query default "$MIMETYPE" 2>/dev/null ||:)" ".desktop")"
            [ -n "$APPLICATION" ] || continue

            [[ ! -v APPLICATIONS["$APPLICATION"] ]] && APPLICATIONS["$APPLICATION"]="$MIMETYPE" \
                || APPLICATIONS["$APPLICATION"]="${APPLICATIONS[$APPLICATION]} $MIMETYPE"
        done

        if (( $# == 0 )); then
            local -a APPLICATION_NAMES=()
            readarray -t APPLICATION_NAMES < <(printf '%s\n' "${!APPLICATIONS[@]}" | sort)
            set -- "${APPLICATION_NAMES[@]}"
        fi

        for APPLICATION in "$@"; do
            APPLICATION="$(basename "$APPLICATION" ".desktop")"
            if [[ -v APPLICATIONS["$APPLICATION"] ]]; then
                echo "$APPLICATION"
                printf '    %s\n' ${APPLICATIONS[$APPLICATION]}
            fi
        done
    }
fi
