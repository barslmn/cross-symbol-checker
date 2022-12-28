#!/bin/sh
if [ -z "${CSC_LOGLVL-}" ]; then
    CSC_LOGLVL="INFO"
fi

fancy_message() (
    if [ -z "${1}" ] || [ -z "${2}" ]; then
        return
    fi

    RED="\e[31m"
    GREEN="\e[32m"
    YELLOW="\e[33m"
    MAGENTA="\e[35m"
    RESET="\e[0m"
    MESSAGE_TYPE=""
    MESSAGE=""
    MESSAGE_TYPE="${1}"
    MESSAGE="${2}"

    case ${MESSAGE_TYPE} in
        info) printf "  [${GREEN}+${RESET}] %s\n" "${MESSAGE}" ;;
        progress) printf "  [${GREEN}+${RESET}] %s" "${MESSAGE}" ;;
        recommend) printf "  [${MAGENTA}!${RESET}] %s\n" "${MESSAGE}" ;;
        warn) printf "  [${YELLOW}*${RESET}] WARNING! %s\n" "${MESSAGE}" ;;
        error) printf "  [${RED}!${RESET}] ERROR! %s\n" "${MESSAGE}" ;;
        fatal)
            printf "  [${RED}!${RESET}] ERROR! %s\n" "${MESSAGE}"
            exit 1
            ;;
        *) printf "  [?] UNKNOWN: %s\n" "${MESSAGE}" ;;
    esac
)

get_log_level() {
    lvl="$1"
    case $lvl in
        debug | DEBUG | d | D)
            lvl="0"
            ;;
        info | INFO | I | i)
            lvl="1"
            ;;
        warning | warn | WARNING | WARN | W | w)
            lvl="2"
            ;;
        error | err | ERROR | ERR | E | e)
            lvl="3"
            ;;
    esac
    echo $lvl
}

LOGLVL=$(get_log_level $CSC_LOGLVL)
# if [ "$LOGLVL" = 0 ]; then set -xv; fi

log() {
    level=$1
    message=$2
    loglvl=$(get_log_level "$level")
    if [ "$loglvl" -ge "$LOGLVL" ]; then
        case $loglvl in
            0 | debug)
                fancy_message "info" "$level $message"
                ;;
            1 | info)
                fancy_message "info" "$level $message"
                ;;
            2 | warn)
                fancy_message "warn" "$level $message"
                ;;
            3 | err)
                fancy_message "error" "$level $message"
                ;;
        esac
    fi
}
