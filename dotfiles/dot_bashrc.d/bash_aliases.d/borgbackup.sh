# Borg Backup helper
if [ -x "$(type -p borg)" ]; then
    # sort `borg diff` by size change
    borg-diff-sorted() {
        borg diff --content-only --json-lines "$@" \
            | jq -r '
                . as $obj |
                {
                  path: .path,
                  added: (
                    [ .changes[] |
                      if .type == "modified" then .added
                      elif .type == "added" then .size
                      elif (.type | startswith("added ")) then "added"
                      else null
                      end
                    ] |
                    reduce .[] as $item (
                      null;
                      if type == "string" then .
                      elif $item | type == "string" then $item
                      else . + $item
                      end
                    )
                  ),
                  removed: (
                    [ .changes[] |
                      if .type == "modified" then .removed
                      elif .type == "removed" then .size
                      elif (.type | startswith("removed ")) then "removed"
                      else null
                      end
                    ] |
                    reduce .[] as $item (
                      null;
                      if type == "string" then .
                      elif $item | type == "string" then $item
                      else . + $item
                      end
                    )
                  )
                } |
                "\(.added // "")\t\(.removed // "")\t\(.path)"
            ' \
            | sort -t $'\t' -s -k1,1gr -k1,1r -k2,2g -k2,2 -k3,3 \
            | awk -F'\t' '
                function human(x, p) {
                  if (x+0 != x) return x
                  if (x < 100000) return sprintf("%s%d B ", p, x)
                  split("B kB MB GB TB PB", units, " ")
                  for (i = 1; x >= 10000 && i < length(units); i++) x /= 1000
                  return sprintf("%s%.2f %s", p, x, units[i])
                }
                { printf "%12s  %12s  %s\n", human($1, "+"), human($2, "-"), $3 }
            '
    }

    # list known repos
    borg-list-repos() {
        __read_inifile() {
            \awk -F= -v section="$1" -v field="$2" '
                { for (i = 1; i <= NF; i++) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", $i) } }
                /^\[.+\]/ { found=0 }
                $0 ~ "^\\[(" section ")\\]" { found=1 }
                found && $1 == field { print $2; exit }
            ' "$3"
        }

        local REPO_ID REPO_LAST_LOCATION REPO_LAST_USAGE
        local CACHE_SIZE CACHE_LOCATION CACHE_TIMESTAMP
        local BORG_DIR RC=0

        if [ -n "${BORG_BASE_DIR:-}" ]; then
            [ -n "${BORG_CACHE_DIR:-}" ] || local BORG_CACHE_DIR="$BORG_BASE_DIR/.cache/borg"
            [ -n "${BORG_CONFIG_DIR:-}" ] || local BORG_CONFIG_DIR="$BORG_BASE_DIR/.config/borg"
            [ -n "${BORG_DATA_DIR:-}" ] || local BORG_DATA_DIR="$BORG_BASE_DIR/.local/share/borg"
        else
            [ -n "${BORG_CACHE_DIR:-}" ] || local BORG_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/borg"
            [ -n "${BORG_CONFIG_DIR:-}" ] || local BORG_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/borg"
            [ -n "${BORG_DATA_DIR:-}" ] || local BORG_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/borg"
        fi
        [ -n "${BORG_SECURITY_DIR:-}" ] || local BORG_SECURITY_DIR="$BORG_DATA_DIR/security:$BORG_CONFIG_DIR/security"
        [ -n "${BORG_KEYS_DIR:-}" ] || local BORG_KEYS_DIR="$BORG_CONFIG_DIR/keys"

        local -A BORG_REPO_SECURITY=()
        while read -r -d: BORG_DIR; do
            if [ -d "$BORG_DIR" ] && [ -n "$(find "$BORG_DIR" -maxdepth 0 -not -empty)" ]; then
                for REPO_ID in "$BORG_DIR"/*/; do
                    REPO_ID="$(basename "$REPO_ID")"

                    [ -z "${BORG_REPO_SECURITY[$REPO_ID]:-}" ] \
                        || { echo "Inconsistent security dir of Borg repo ${REPO_ID@Q}: Duplicate directories" \
                            "at $BORG_DIR and $(dirname "${BORG_REPO_SECURITY[$REPO_ID]}")" >&2; RC=1; }
                    BORG_REPO_SECURITY[$REPO_ID]="$BORG_DIR/$REPO_ID"
                done
            fi
        done <<<"$BORG_SECURITY_DIR:"

        if [ -d "$BORG_CACHE_DIR" ] && [ -n "$(find "$BORG_CACHE_DIR" -maxdepth 0 -not -empty)" ]; then
            for REPO_ID in "$BORG_CACHE_DIR"/*/; do
                REPO_ID="$(basename "$REPO_ID")"

                if [ -z "${BORG_REPO_SECURITY[$REPO_ID]:-}" ]; then
                    echo "Borg cache but no security info for Borg repo ${REPO_ID@Q} found" >&2
                    RC=1
                fi
            done
        fi

        for REPO_ID in "${!BORG_REPO_SECURITY[@]}"; do
            REPO_LAST_LOCATION="$(\cat "${BORG_REPO_SECURITY[$REPO_ID]}/location")"
            REPO_LAST_USAGE="$(\cat "${BORG_REPO_SECURITY[$REPO_ID]}/manifest-timestamp")"

            CACHE_SIZE="-"
            CACHE_LOCATION=""
            CACHE_TIMESTAMP=""
            if [ -d "$BORG_CACHE_DIR/$REPO_ID" ]; then
                CACHE_SIZE="$(\du -sh "$BORG_CACHE_DIR/$REPO_ID" | cut -f1)"

                CACHE_LOCATION="$(__read_inifile "cache" "previous_location" "$BORG_CACHE_DIR/$REPO_ID/config")"
                [ "$CACHE_LOCATION" == "$REPO_LAST_LOCATION" ] && CACHE_LOCATION="" || RC=1

                CACHE_TIMESTAMP="$(__read_inifile "cache" "timestamp" "$BORG_CACHE_DIR/$REPO_ID/config")"
                [ "$CACHE_TIMESTAMP" == "$REPO_LAST_USAGE" ] && CACHE_TIMESTAMP="" || RC=1
            fi

            printf '%-68s%-36s%-8s%s\n' "$REPO_ID" "$REPO_LAST_USAGE" "$CACHE_SIZE" "$REPO_LAST_LOCATION"
            [ -z "$CACHE_LOCATION" ] || { echo "Inconsistent location of Borg repo ${REPO_ID@Q}:" \
                "Cache was last used at ${CACHE_LOCATION@Q}" >&2; RC=1; }
            [ -z "$CACHE_TIMESTAMP" ] || { echo "Inconsistent last usage of Borg repo ${REPO_ID@Q}:" \
                "Cache was last used on ${CACHE_TIMESTAMP@Q}" >&2; RC=1; }
        done

        return $RC
    }
fi
