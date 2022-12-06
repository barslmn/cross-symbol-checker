#!/bin/sh
# Validate gene symbol
# Steps:
# 1. Validate the gene symbol.
#    1. Check if the given symbol is in the approved symbols.
#    2. Check if the given symbol is an alias symbol.
#    3. Check if the given symbol is a previous symbol.
#    4. Check if the given symbol is withdrawn, split or merged.
#    5. Get the previous, alias or withdrawn symbols
# 2. Check symbol in annotation sources.
# 3. Check if prev, alias withdrawn symbols are in annotation sources.


# [[file:genesymbolchecker.org::*Validate gene symbol][Validate gene symbol:1]]
start=$(date +%s)

set -o errexit
set -o nounset
if [ "${TRACE-0}" = "1" ]; then
    set -o xtrace
fi

if [ "${1-}" = "help" ]; then
    echo "Usage: ./script.sh symbols

This is an awesome bash script to make your life better."
    exit
fi

cd "$(dirname "$0")"

if [ -z "${GSC_LOGLVL-}" ]; then
    GSC_LOGLVL="INFO"
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

LOGLVL=$(get_log_level $GSC_LOGLVL)
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

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Startup took $runtime seconds"
# Validate gene symbol:1 ends here

start=$(date +%s)

if [ -z "${GSC_SOURCES-}" ]; then
    sources="
    Ensembl
    RefSeq
    "
else
    sources="$GSC_SOURCES"
fi
if [ -z "${GSC_ASSEMBLIES-}" ]; then
    assemblies="
    GRCh37
    GRCh38
    T2T
    "
else
    assemblies="$GSC_ASSEMBLIES"
fi

symbol=$1
matches=""

approved=$(zcat data/hgnc.gz | awk -F "\t" -v symbol=$symbol '$2==symbol {print}')
if [ -z "$approved" ]; then
    # Symbol is not in approved list or not a valid symbol
    log "INFO" "$symbol is not in approved list :("
else
    # Symbol is in approved list.
    log "INFO" "$symbol is in approved list."
    matches="$matches\nApproved\t$(echo "$approved" | cut -f 2)"
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking approved symbol took $runtime seconds"

start=$(date +%s)

alias=$(zcat data/alias.gz | awk -F "\t" -v symbol=$symbol '$1==symbol {print}')
if [ -z "$alias" ]; then
    # Symbol is not in alias or not a valid symbol
    log "INFO" "$symbol is not an alias symbol."
else
    # Symbol is in alias symbols list.
    log "INFO" "$symbol is an alias symbol."
    matches="$matches\nAlias\t$(echo "$alias" | cut -f 2)"
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking alias symbol took $runtime seconds"

start=$(date +%s)

prev=$(zcat data/prev.gz | awk -F "\t" -v symbol=$symbol '$1==symbol {print}')
if [ -z "$prev" ]; then
    # Symbol is not in previous symbols or not a valid symbol
    log "INFO" "$symbol is not a previous symbol."
else
    # Symbol is in previous symbols list.
    log "INFO" "$symbol is a previous symbol."
    matches="$matches\nPrev\t$(echo "$prev" | cut -f 2)"
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking previous symbol took $runtime seconds"

start=$(date +%s)

withdrawn=$(zcat data/withdrawn.gz | awk -F "\t" -v symbol=$symbol '$3==symbol {print}')
if [ -z "$withdrawn" ]; then
    # Symbol is not withdrawn or not a valid symbol
    log "INFO" "$symbol is not in withdrawn list."
else
    # Symbol is withdrawn/merged/split
    echo "$withdrawn" | read -r ID STATUS SYMBOL REPORTS
    case STATUS in
        "Entry Withdrawn")
            log "INFO" "WITHDRAWN $symbol is gone!"
            ;;
        "Merged/Split")
            echo "$REPORTS" |
                tr ', ' '\n' |
                sed '/^$/d;s/|/ /g' |
                while read -r NEWID NEWSYMBOL NEWSTATUS; do
                    case "$NEWSTATUS" in
                        "Entry Withdrawn")
                            log "INFO" "MERGED/SPLIT $symbol has been $STATUS into $NEWSYMBOL which itself also got withdrawn. ;("
                            # matches="$matches\nWithdrawn but it got withdrawn too."
                            ;;
                        "Approved")
                            log "INFO" "MERGED/SPLIT $symbol now lives on with the name $NEWSYMBOL."
                            matches="$matches\nWithdrawn$NEWSYMBOL"
                            ;;
                    esac
                done
            ;;
    esac
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking withdrawn symbol took $runtime seconds"

start=$(date +%s)

if [ -z "${matches+}" ]; then
    log "WARN" "couldn't find an approved symbol for $symbol"
    echo "WARNING couldn't find an approved symbol for $symbol"
    is_date=$(date -d "$symbol" 2>1 | grep -v "invalid")
    if [ -z "$is_date"]; then
        log "INFO" "doesn't look like a date."
    else
        log "WARN" "This is a date"
        echo "WARNING This is a date"
    fi
    # TODO warn about this symbol
    exit
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking if any approved symbol found took $runtime seconds"

start=$(date +%s)

# We collect all possible approved_symbol(s) which we expect to be only one.
# However we check in case a symbol maps to multiple symbols.
if [ $(echo "$matches" | sed '/^$/d' | sort -u | wc -l) -eq 1 ]; then # this is what we expect.
    case "$matches" in
        "Approved*")
            log "INFO" "$1 was already an approved symbol."
            ;;
        "Prev*")
            log "INFO" "previous symbol $1 mapped to an approved symbol."
            ;;
        "Alias*")
            log "INFO" "alias symbol $1 mapped to an approved symbol."
            ;;
    esac
    approved_symbol=$(echo $matches | sed '/^$/d' | cut -f 2)
    echo "APPROVED\t$approved_symbol"

else
    # Some approved symbols are alias to other symbols
    # We are going to handle this case by picking the
    # original input.
    log "WARN" "$1 mapped to multiple approved symbols! $(echo "$matches" | sed '/^$/d' | cut -f 2 | tr '\n' ' ')"
    echo "WARNING $1 mapped to multiple approved symbols! $(echo "$matches" | sed '/^$/d' | cut -f 2 | tr '\n' ' ')"
    while read -r found_in appr_sym; do
        case $found_in in
            "Approved")
                log "INFO" "Orginal input $1 already was an approved symbol. Carrying out with this symbol."
                approved_symbol="$appr_sym"
                echo "APPROVED\t$approved_symbol"
                ;;
            "Prev")
                log "WARN" "$1 was also $found_in symbol for approved symbol $appr_sym."
                echo "WARNING $1 was also $found_in symbol for approved symbol $appr_sym."
                ;;
            "Alias")
                log "INFO" "$1 was also $found_in symbol for approved symbol $appr_sym."
                ;;
        esac
    done <<-EOF
$(echo "$matches")
EOF
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking if more than one approved symbol found took $runtime seconds"

start=$(date +%s)

unset alias
alias=$(zcat data/alias.gz | awk -F "\t" -v symbol=$approved_symbol '$2==symbol {print}')
if [ -z "$alias" ]; then
    # Symbol is not in alias or not a valid symbol
    log "INFO" "$approved_symbol has no alias symbol."
else
    # Symbol is in alias symbols list.
    alias_symbols="$(echo "$alias" | cut -f 1 | sed 's/^/ALIAS\t/')"
    echo "$alias_symbols"
fi

unset prev
prev=$(zcat data/prev.gz | awk -F "\t" -v symbol=$approved_symbol '$2==symbol {print}')
if [ -z "$prev" ]; then
    # Symbol is not in alias or not a valid symbol
    log "INFO" "$approved_symbol has no prev symbol."
else
    # Symbol is in alias symbols list.
    prev_symbols="$(echo "$prev" | cut -f 1 | sed 's/^/PREV\t/')"
    echo "$prev_symbols"
fi

unset withdrawn
withdrawn=$(zcat data/withdrawn.gz | (grep "|$approved_symbol|" || true))
if [ -z "$withdrawn" ]; then
    # Symbol is not in alias or not a valid symbol
    log "INFO" "$approved_symbol has no withdrawn symbol."
else
    # Symbol is in alias symbols list.
    withdrawn_symbols="$(echo "$withdrawn" | cut -f 3 | sed 's/^/WITHDRAWN\t/')"
    echo "$withdrawn_symbols"
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking for other symbols took $runtime seconds"

start=$(date +%s)


table=""
if [ -z "$approved_symbol" ]; then
    log "INFO" "no approved symbol found so not checking annotation sources for approved symbol."
else
    for source in $(echo "$sources"); do
        for assembly in $(echo "$assemblies"); do

            # Print out gff meta data
            source_info=$(zcat data/$source.$assembly.bed.gz | grep -m 3 '^#!' | sed "s/^#!/VERSION $source $assembly /")
            echo "$source_info" | while read -r line; do log "INFO" "$line"; done
            echo "$source_info"

            # Get the non canonical chromosomes
            if [ "$assembly" != "T2T" ]; then
                case "$source" in
                    "RefSeq")
                        noncanonical=$(zcat "data/$source.$assembly.bed.gz" | grep -v "^#" | awk -F"\t" '{print $1}' | sort -u | grep -v '^NC');
                        ;;
                    "Ensembl")
                        noncanonical=$(zcat "data/$source.$assembly.bed.gz" | grep -v '^#' | awk -F"\t" '{print $1}' | sort -u | grep -vE 'chr([1-9]|1[0-9]|2[0-2]|X|Y|MT)');
                        ;;
                esac
            fi

            while read -r status new_symbol; do
                start_inner=$(date +%s)
                if [ -n "${status-}" ]; then
                    match=$(zcat data/$source.$assembly.bed.gz | (grep -m1 -w "$new_symbol" || true))
                    if [ -z "${match:-}" ]; then
                        log "INFO" "$status SYMBOL $new_symbol found in $source $assembly"
                        table=""$table"Absent\t$symbol\t$approved_symbol\t$new_symbol\t$status\t$source\t$assembly\n"
                    else
                        # check_noncanonical
                        for contig in $(echo "$noncanonical"); do
                            if echo "$match" | grep -q "$contig"; then
                                log "WARN" "Symbol $new_symbol not in a canonical chromosome in $source $assembly"
                                echo "WARNING Symbol $new_symbol not in a canonical chromosome in $source $assembly"
                            fi
                        done

                        log "INFO" "$status SYMBOL $new_symbol not found in $source $assembly"
                        table=""$table"Present\t$symbol\t$approved_symbol\t$new_symbol\t$status\t$source\t$assembly\t$match\n"
                    fi

                    end_inner=$(date +%s)
                    runtime_inner=$((end_inner - start_inner))
                    log "DEBUG" "TIME Checking annotation for approved took $runtime_inner seconds"
                fi
            done <<-EOF
$(echo "$approved_symbol"| sed 's/^/APPROVED\t/')
${prev_symbols-}
${alias_symbols-}
${withdrawn_symbols-}
EOF
        done
    done
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking annotation sources took $runtime seconds"
echo "$(echo "$table" | sed '/^$/d;s/^/TABLE\t/')"
