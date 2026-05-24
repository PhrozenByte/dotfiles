if [ -x "$(type -p comm)" ] && [ -x "$(type -p find)" ]; then
    diff-filelist() {
        command comm -3 \
            <(cd "${1:-.}" && command find . -type f | sort) \
            <(cd "${2:-.}" && command find . -type f | sort) |
            sed -e $'s/^\t/+/;t;s/^/-/'
    }
fi

if [ -x "$(type -p rsync)" ]; then
    diff-filemeta() {
        local LINE FILE SKIPPED_DIR
        local CODE ACTION FILETYPE CONTENTS SIZE TIMES PERMS OWNER GROUP XATTR _
        while IFS= read -r LINE; do
            CODE="${LINE:0:11}"
            FILE="${LINE:12}"

            if [ -n "$SKIPPED_DIR" ]; then
                [[ "$FILE" != "$SKIPPED_DIR"/* ]] || continue
                SKIPPED_DIR=
            fi

            ACTION="${CODE:0:1}"
            FILETYPE="${CODE:1:1}"
            CONTENTS="${CODE:2:1}"
            SIZE="${CODE:3:1}"
            TIMES="${CODE:4:1}"
            PERMS="${CODE:5:1}"
            OWNER="${CODE:6:1}"
            GROUP="${CODE:7:1}"
            _="${CODE:8:1}"
            XATTR="${CODE:9:1}"

            if [ "${CODE:2}" == "+++++++++" ]; then
                [ "$FILETYPE" != "d" ] || SKIPPED_DIR="${FILE%/}"
                continue
            fi

            if [ "$PERMS" != "." ] || [ "$OWNER" != "." ] || [ "$GROUP" != "." ] || [ "$XATTR" != "." ] \
                || { [ "$FILETYPE" != "f" ] && [ "$CONTENTS" != "." ]; }
            then
                echo "$LINE"
            fi
        done < <(command rsync -a -EAHX --dry-run --itemize-changes "$@")
    }
fi
