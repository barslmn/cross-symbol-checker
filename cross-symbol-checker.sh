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


# [[file:cross-symbol-checker.org::*Validate gene symbol][Validate gene symbol:1]]
start=$(date +%s)

set -o errexit
set -o nounset
if [ "${TRACE-0}" = "1" ]; then
    set -o xtrace
fi

if [ "${1-}" = "help" ]; then
    echo "Usage: ./cross-symbol-checker.sh symbol
This script checks given symbol against every possible assembly

-c --no-cross-check
    Don't check annotation sources. Just check alternative gene symbols and exit.
-h --help
    Display this help message and exit.
-V
    Print current version and exit

Functionality of the script can be further altered with environment variables.
CSC_SOURCES
    Limit which annotation sources to be used.
CSC_ASSEMBLIES
    Limit which assemblies sources to be used.
CSC_VERSIONS
    Limit which versions sources to be used.
CSC_LOGLVL
    Set log level. Default is INFO.
"

    exit
fi

cd "$(dirname "$0")"
. ./logger.sh

# Check if the data dir cached to /dev/shm
CACHEDIR="/dev/shm/CSC_DATA"
if [ -d $CACHEDIR ]; then
    DATADIR="$CACHEDIR"
    log "DEBUG" "Using the $CACHEDIR"
else
    DATADIR="./data"
    log "DEBUG" "Using the default data dir"
fi
DATADIR="./data"

# Cross checking is enabled by default.
XCHECK=1

PARSED_ARGUMENTS=$(getopt -a -o chV -l no-cross-check,help -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
    usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :; do
    case "$1" in
    -c | --no-cross-check)
        XCHECK=0
        shift
        ;;
    -h | --help)
        usage
        ;;
    -V )
        echo "Cross-symbol checker v0.0.2"
        exit
        ;;
    # -- means the end of the arguments; drop this, and break out of the while loop
    --)
        shift
        break
        ;;
    # If invalid options were passed, then getopt should have reported an error,
    # which we checked as VALID_ARGUMENTS when getopt was called...
    *)
        echo "Unexpected option: $1 - this should not happen."
        usage
        ;;
    esac
done


end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Startup took $runtime seconds"
# Validate gene symbol:1 ends here

start=$(date +%s)

if [ -z "${CSC_SOURCES-}" ]; then
    sources="
    Ensembl
    RefSeq
    "
else
    sources="$CSC_SOURCES"
fi
if [ -z "${CSC_ASSEMBLIES-}" ]; then
    assemblies="
    GRCh37
    GRCh38
    T2T
    "
else
    assemblies="$CSC_ASSEMBLIES"
fi
if [ -z "${CSC_VERSIONS-}" ]; then
    versions="latest"
    # Greps all of the versions
    # versions=$(for source in $(echo "$sources"); do for assembly in $(echo "$assemblies"); do find data/ -name "$source.$assembly.*.bed.gz"; done ;done | cut -d"." -f3 | sort -u)
else
    versions="$CSC_VERSIONS"
fi

# targets will look like this:
# source	assembly	version	file_path
targets=""
for source in $(echo "$sources"); do
    for assembly in $(echo "$assemblies"); do
        for version in $(echo "$versions"); do
            target_path="$DATADIR/$source.$assembly.$version.bed.gz"
            [ -f "$target_path" ] || continue
            targets="$targets\n$source\t$assembly\t$version\t$target_path"
        done
    done
done

if [ -z "${CSC_TARGETS-}" ]; then
    custom_targets=""
else
    for custom_target in $(echo "$CSC_TARGETS" | sort -u); do
        # Here we check if file name has the format
        # source.assembly.version.bed
        custom_target_base="${custom_target##*/}"
        echo ${custom_target_base} | awk -F"." '{print $1" "$2" "$3" "$4}' | read source assembly version bed
        [ ${bed-} ] && targets="$targets\n$source\t$assembly\t$version\t$target_path" || targets="$targets\n$custom_target_base\tCustom\tCustom\t$custom_target"
    done
fi

symbol=$(echo "$1" | tr '[:lower:]' '[:upper:]' | awk '/C([1-9]|1[0-9]|2[0-2]|X|Y)ORF[0-9]+/ {gsub("ORF", "orf", $0)} 1')
if [ "$symbol" != "$1" ]; then
    echo "WARNING $1 capitalization changed to $symbol"
fi
matches=""

approved=$(zcat -f $DATADIR/hgnc.gz | awk -F "\t" -v symbol=$symbol '$2==symbol {print}')
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

alias=$(zcat -f $DATADIR/alias.gz | awk -F "\t" -v symbol=$symbol '$1==symbol {print}')
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

prev=$(zcat -f $DATADIR/prev.gz | awk -F "\t" -v symbol=$symbol '$1==symbol {print}')
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

withdrawn=$(zcat -f $DATADIR/withdrawn.gz | awk -F "\t" -v symbol=$symbol '$3==symbol {print}')
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

# We collect all possible approved_symbol(s) which we expect to be only one.
# However we check in case a symbol maps to multiple symbols.
if [ $(echo "$matches" | sed '/^$/d' | sort -u | wc -l) -eq 1 ]; then # this is what we expect.
    case "$matches" in
        "Approved*")
            log "INFO" "$symbol was already an approved symbol."
            ;;
        "Prev*")
            log "INFO" "previous symbol $symbol matched with an approved symbol."
            ;;
        "Alias*")
            log "INFO" "alias symbol $symbol matched with an approved symbol."
            ;;
    esac
    approved_symbol=$(echo $matches | sed '/^$/d' | cut -f 2)
    echo "APPROVED\t$approved_symbol"
elif [ $(echo "$matches" | sed '/^$/d' | sort -u | wc -l) -gt 1 ]; then # this is what we expect.
    # Some approved symbols are alias to other symbols
    # We are going to handle this case by picking the
    # original input.
    log "WARN" "$symbol matched with multiple approved symbols! $(echo "$matches" | sed '/^$/d' | cut -f 2 | tr '\n' ' ')"
    echo "WARNING $symbol matched with multiple approved symbols! $(echo "$matches" | sed '/^$/d' | cut -f 2 | tr '\n' ' ')"
    while read -r found_in appr_sym; do
        case $found_in in
            "Approved")
                log "INFO" "Orginal input $symbol already was an approved symbol. Carrying out with this symbol."
                approved_symbol="$appr_sym"
                echo "APPROVED\t$approved_symbol"
                ;;
            "Prev")
                log "WARN" "$symbol was also $found_in symbol for approved symbol $appr_sym."
                echo "WARNING $symbol was also $found_in symbol for approved symbol $appr_sym."
                ;;
            "Alias")
                log "INFO" "$symbol was also $found_in symbol for approved symbol $appr_sym."
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

if [ -z "${approved_symbol-}" ]; then
    log "WARN" "No approved symbol found for $symbol"
    echo "WARNING No approved symbol found for $symbol"
    is_date=$(date -d "$symbol" 2>&1 | grep -v "invalid")
    if [ -z "$is_date" ]; then
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

unset alias
alias=$(zcat -f $DATADIR/alias.gz | awk -F "\t" -v symbol=$approved_symbol '$2==symbol {print}')
if [ -z "$alias" ]; then
    # Symbol is not in alias or not a valid symbol
    log "INFO" "$approved_symbol has no alias symbol."
else
    # Symbol is in alias symbols list.
    alias_symbols="$(echo "$alias" | cut -f 1 | sed 's/^/ALIAS\t/')"
    echo "$alias_symbols"
fi

unset prev
prev=$(zcat -f $DATADIR/prev.gz | awk -F "\t" -v symbol=$approved_symbol '$2==symbol {print}')
if [ -z "$prev" ]; then
    # Symbol is not in alias or not a valid symbol
    log "INFO" "$approved_symbol has no prev symbol."
else
    # Symbol is in alias symbols list.
    prev_symbols="$(echo "$prev" | cut -f 1 | sed 's/^/PREV\t/')"
    echo "$prev_symbols"
fi

unset withdrawn
withdrawn=$(zcat -f $DATADIR/withdrawn.gz | (grep "|$approved_symbol|" || true))
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

[ $XCHECK = 0 ] && log "INFO" "--no-cross-check is set. Exiting without cross checking" && exit

table=""
if [ -z "$approved_symbol" ]; then
    log "INFO" "no approved symbol found so not checking annotation sources for approved symbol."
else
    while read -r source assembly version target_file; do
        # Print out gff meta data
        source_info=$(zcat -f "$target_file" | grep -m 3 '^#!' | sed "s/^#!/VERSION $source $assembly /")
        echo "$source_info" | while read -r line; do log "INFO" "$line"; done
        echo "$source_info"

        # Get the non canonical chromosomes
        if [ "$assembly" != "T2T" ]; then
            case "$source" in
                "RefSeq")
                    noncanonical=$(zcat -f "$target_file" | grep -v "^#" | awk -F"\t" '{print $1}' | sort -u | grep -v '^NC');
                    ;;
                "Ensembl")
                    noncanonical=$(zcat -f "$target_file" | grep -v '^#' | awk -F"\t" '{print $1}' | sort -u | grep -vE 'chr([1-9]|1[0-9]|2[0-2]|X|Y|MT)');
                    ;;
            esac
        fi

        while read -r status new_symbol; do
            start_inner=$(date +%s%N)
            if [ -n "${status-}" ]; then
                match=$(zcat -f "$target_file" | (grep -m1 -w "$new_symbol" || true))
                if [ -z "${match:-}" ]; then
                    log "INFO" "$status SYMBOL $new_symbol found in $source $assembly $version"
                    table=""$table"Absent\t$symbol\t$approved_symbol\t$new_symbol\t$status\t$source\t$assembly\t$version\n"
                else
                    # check_noncanonical
                    for contig in $(echo "$noncanonical"); do
                        if echo "$match" | grep -q "$contig"; then
                            log "WARN" "Symbol $new_symbol not in a canonical chromosome in $source $assembly $version"
                            echo "WARNING Symbol $new_symbol not in a canonical chromosome in $source $assembly $version"
                        fi
                    done

                    log "INFO" "$status SYMBOL $new_symbol not found in $source $assembly $version"
                    table=""$table"Present\t$symbol\t$approved_symbol\t$new_symbol\t$status\t$source\t$assembly\t$version\t$match\n"
                fi

            fi
            end_inner=$(date +%s%N)
            runtime_inner=$(( (end_inner - start_inner) / 1000000 ))
            log "DEBUG" "TIME Checking $target_file for symbol $new_symbol took $runtime_inner milliseconds"
        done <<-EOF
$(echo "$approved_symbol"| sed 's/^/APPROVED\t/')
${prev_symbols-}
${alias_symbols-}
${withdrawn_symbols-}
EOF
    done <<-EOF
$(echo ${targets-} | sed '/^$/d')
EOF
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking annotation sources took $runtime seconds"
printf "$table\n" | sed '/^$/d;s/^/TABLE\t/'
