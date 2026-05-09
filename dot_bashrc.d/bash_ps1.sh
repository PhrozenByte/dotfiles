# load optional git-prompt.sh dependency
[ ! -f /usr/share/git/git-prompt.sh ] \
    || . /usr/share/git/git-prompt.sh

__ps1() {
    # reset
    local COLOR_CLEAR="\[\033[0m\]"  # Reset

    # regular colors
    local COLOR_BLACK="\[\033[0;30m\]"   # Black
    local COLOR_RED="\[\033[0;31m\]"     # Red
    local COLOR_GREEN="\[\033[0;32m\]"   # Green
    local COLOR_YELLOW="\[\033[0;33m\]"  # Yellow
    local COLOR_BLUE="\[\033[0;34m\]"    # Blue
    local COLOR_PURPLE="\[\033[0;35m\]"  # Purple
    local COLOR_CYAN="\[\033[0;36m\]"    # Cyan
    local COLOR_WHITE="\[\033[0;37m\]"   # White

    # bold colors
    local COLOR_B_BLACK="\[\033[1;30m\]"   # Black
    local COLOR_B_RED="\[\033[1;31m\]"     # Red
    local COLOR_B_GREEN="\[\033[1;32m\]"   # Green
    local COLOR_B_YELLOW="\[\033[1;33m\]"  # Yellow
    local COLOR_B_BLUE="\[\033[1;34m\]"    # Blue
    local COLOR_B_PURPLE="\[\033[1;35m\]"  # Purple
    local COLOR_B_CYAN="\[\033[1;36m\]"    # Cyan
    local COLOR_B_WHITE="\[\033[1;37m\]"   # White

    # lines
    local LINE_TL="\342\224\230"  # line from top to left
    local LINE_TR="\342\224\224"  # line from top to right
    local LINE_BL="\342\224\220"  # line from bottom to left
    local LINE_BR="\342\224\214"  # line from bottom to right
    local LINE_V="\342\224\202"   # vertical line
    local LINE_VL="\342\224\244"  # vertical line and left connector
    local LINE_VR="\342\224\234"  # vertical line and right connector
    local LINE_H="\342\224\200"   # horicontal line
    local LINE_HT="\342\224\264"  # horicontal line and top connector
    local LINE_HB="\342\224\254"  # horicontal line and bottom connector
    local LINE_X="\342\224\274"   # cross

    # first line of PS1
    echo

    # print current time
    echo -n "$LINE_BR$LINE_H[\t]"

    # print current working directory
    local LEN=$(echo -n "\w" | wc -c)
    local MAX=$((MAX = ${COLUMNS:-80} - $(echo -n "--[\t]-[]" | wc -c)))
    if [ $LEN -le $MAX ]; then
        echo -n "$LINE_H[$COLOR_B_BLUE\w$COLOR_CLEAR]"
    else
      local LEN_FIRST=$((MAX / 3))
      local LEN_LAST=$((MAX - LEN_FIRST - 1))
      echo -n "$LINE_H[$COLOR_B_BLUE"
      echo -n "$(echo -n "\w" | head -c $LEN_FIRST)\342\200\246$(echo -n "\w" | tail -c $LEN_LAST)"
      echo -n "$COLOR_CLEAR]"
    fi

    # second line of PS1
    echo

    # print user and host
    if [ -z "${FLATPAK_ID:-}" ]; then
        echo -n "$LINE_TR$LINE_H$LINE_H$LINE_H[\u@\h]"
    else
        echo -n "$LINE_VR$LINE_H$LINE_H$LINE_H[\u@\h]"

        # third line if in Flatpak container
        echo
    fi

    # print current Flatpak container
    if [ -n "${FLATPAK_ID:-}" ]; then
        echo -n "$LINE_TR$LINE_H$LINE_H$LINE_H$LINE_H$LINE_H[📦 $FLATPAK_ID]"
    fi

    # print current Git branch
    if type -t __git_ps1 > /dev/null; then
        echo -n "$(__git_ps1 "$LINE_H[%s]")"
    fi

    # print shell ($ for user shell, # for root shell) and
    # indicate exit code of previous command (green for exit code 0, red otherwise)
    if [ ${1:-0} -eq 0 ]; then
      echo -n "$LINE_H[$COLOR_GREEN\$$COLOR_CLEAR]"
    else
      echo -n "$LINE_H[$COLOR_RED\$$COLOR_CLEAR]"
    fi

    # prompt separator
    echo " "
}

PS1="\$(RETURN=\$?; $(declare -f __ps1); __ps1 \$RETURN)"
