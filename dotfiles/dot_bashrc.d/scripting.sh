# quote arguments if needed
quote() {
    local QUOTED=
    for ARG in "$@"; do
        [ "$(printf '%q' "$ARG")" == "$ARG" ] \
            && QUOTED+=" $ARG" \
            || QUOTED+=" ${ARG@Q}"
    done
    echo "${QUOTED:1}"
}

# print and run a command
cmd() {
    echo + "$(quote "$@")" >&2
    "$@"
}

# manage bitwise flags
has_flag() {
    local VALUE="$1" FLAG="$2"
    (( ( VALUE & FLAG ) == FLAG ))
}

set_flag() {
    local VALUE="$1" FLAG="$2"
    echo $(( VALUE | FLAG ))
}

unset_flag() {
    local VALUE="$1" FLAG="$2"
    echo $(( VALUE ^ FLAG ))
}
