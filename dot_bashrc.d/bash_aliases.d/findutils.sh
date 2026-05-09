# find helper
if [ -x "$(type -p find)" ]; then
    # find last changed file in a directory
    find-latest() {
        local FILE_DATE FILE
        while IFS=' ' read -d '' -r FILE_DATE FILE; do
            printf '%s  %s\n' "$(date -d "@$FILE_DATE" +'%Y-%m-%d %H:%M:%S')" "$FILE"
        done < <(find "$@" -type f -printf '%T@ %p\0' | sort -znr)
    }

    # find largest file in a directory
    find-largest() {
        find "$@" -type f -printf '%s  %p\n' | sort -k 1,1hr | numfmt --field=1 --to=si
    }

    # create a histogram of file sizes within a directory
    find-histogram() {
        find "$@" -type f -printf '%s\n' \
            | awk '
                {
                    if ($0 > max) max=$0;
                    class=32;
                    if ($0 == 0) { printf("%d %d\n", 0, 0) }
                    else if ($0 < class) { printf("%d %d\n", 1, class) }
                    else { while ($0 >= class) class *= 2; printf("%d %d\n", class/2, class) }
                }
                END {
                    class=32;
                    printf("%d %d\n", 0, 0);
                    printf("%d %d\n", 1, class);
                    while (max >= class) { class *= 2; printf("%d %d\n", class/2, class) }
                }
            ' | sort -h | uniq -c | numfmt --field=2-3 --to=iec \
            | awk '
                { count=$1-1; total+=count; printf("[%s, %s): %d\n", $2, $3, count) }
                END { printf("Total: %d\n", total) }
            '
    }

    # find links pointing to a directory
    find-links() {
        local SEARCH="$1"
        shift

        local TARGETS=()
        while (( $# > 0 )); do
            TARGETS+=( "$(readlink -m "$1")" )
            shift
        done

        local LINK= TARGET=
        find "$SEARCH" -type l -print0 | while IFS= read -d '' -r LINK; do
            TARGET="$(readlink -m "$LINK")"
            for CHECK in "${TARGETS[@]}"; do
                if [[ "$TARGET" == "${CHECK%/}"/* ]]; then
                    echo "$LINK -> $TARGET"
                fi
            done
        done
    }
fi
