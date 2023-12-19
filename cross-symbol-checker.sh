#!/bin/sh
# Usage and argument parsing
# Steps:
# 1. Validate the gene symbol.
#    1. Check if the given symbol is in the approved symbols.
#    2. Check if the given symbol is an alias symbol.
#    3. Check if the given symbol is a previous symbol.
#    4. Check if the given symbol is withdrawn, split or merged.
#    5. Get the previous, alias or withdrawn symbols
# 2. Check symbol in annotation sources.
# 3. Check if prev, alias withdrawn symbols are in annotation sources.


# [[file:cross-symbol-checker.org::*Usage and argument parsing][Usage and argument parsing:1]]
start=$(date +%s)

set -o errexit
set -o nounset
if [ "${TRACE-0}" = "1" ]; then
    set -o xtrace
fi

usage() {
    echo "
    This script checks given gene symbols against given assemblies

    Usage
    -----
        $0 [OPTIONS] [SYMBOL ...]

    Example
    -------
        $0 -a T2T -s RefSeq -v latest WNT10B WNT10A WNT10C

    Options
    -------
    -a --assembly
        Default assemblies are GRCh37, GRCh38 and T2T.
        You can use multiple assemblies by quoting them together like -a "GRCh37 GRCh38"

    -c --no-cross-check
        Don't check annotation sources. Just check alternative gene symbols and exit.

    -l --log-level
        Set log level. Default is INFO. Possible values are DEBUG, INFO, WARN, ERROR, FATAL

    -h --help
        Display this help message and exit.

    -o --only-target
        By default check-geneset.sh will run for every assembly. Use this option
        to check only against given target file.

    -s --source
        Default assemblies are GRCh37, GRCh38 and T2T.
        You can use multiple assemblies by quoting them together like -a "GRCh37 GRCh38"

    -t --target
        Custom bed file. If file name has the format: source.assembly.version.bed,
        columns in the output table will be filled accordingly.
        Custom file should look like this:
               chrom	start	end	symbol
               chr1	1266694	1270686	TAS1R3
               chr1	1270656	1284730	DVL1
               chr1	1288069	1297157	MXRA8

    -v --version
        There is only one version for all of the assemblies which is latest.
        You can install older assemblies and specify them with this parameter.

    -V --version
        Print current version and exit
"
    exit
}

if [ $# -eq 0 ]; then
    usage
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

PARSED_ARGUMENTS=$(getopt -a -o a:chs:v:Vt:o -l assembly:,no-ross-check,help,source:,version:,target:,only-target -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
    usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :; do
    case "$1" in
    -a | --assembly)
        CSC_ASSEMBLIES="$2"
        shift 2
        ;;
    -c | --no-cross-check)
        XCHECK=0
        shift
        ;;
    -l | --log-level)
        CSC_LOGLVL="$2"
        export CSC_LOGLVL
        shift 2
        ;;
    -o | --only-target)
        [ -z ${CSC_TARGETS-} ] && echo "Can't use -o parameter without a target file." && exit
        CSC_ASSEMBLIES="Unset"
        CSC_SOURCES="Unset"
        CSC_VERSIONS="Unset"
        shift 1
        ;;
    -s | --source)
        CSC_SOURCES="$2"
        shift 2
        ;;
    -t | --target)
        CSC_TARGETS="$2"
        shift 2
        # Validate target files
        for target in $(echo "$CSC_TARGETS"); do
            [ -f "$target" ] && log "DEBUG" "Found target file $target." || (log "ERROR" "Can't find target file $target. exiting..." && exit 1)
            target_col_number=$(zcat -f "$target" | grep -v '^#' | awk '{print NF}' | uniq)
            [ $(echo "$target_col_number" | wc -l) -gt 1 ] && log "ERROR" "Mismatch in target column numbers for given target file $target. There are lines with $(echo "$target_col_number" | tr "\n" " ") columns. exiting..." && exit 1
            [ "$target_col_number" -ne 4 ] && log "ERROR" "Target $target has $target_col_number number of columns. Custom target files should have 4 columns: chrom start end and symbol. exiting..." && exit 1
            log "DEBUG" "Custom target $target looks okay."

            # We are checking if there are any non valid symbols in the custom target file
            # This takes quite some time if the target file is large.
            # A multiprocessing approach can be beneficial here
            # Another approach might be sorting the data files alphabetically spliting the files by first one or two characters and just searching the splitted file.
            # [ $(zcat -f "$target" | grep -v '^#' | awk '{print $4}' | xargs -I% ./cross-symbol-checker.sh -c % | grep -m1 "#WARNING No approved symbol found") ] && log "ERROR" "Found a non valid symbol at target file $target. exiting..." && exit 1 || log "DEBUG" "Custom target file $target symbols looks okay."
        done
        ;;
    -v | --version)
        CSC_VERSIONS="$2"
        shift 2
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

cp -r data/ /dev/shm/CSC_DATA || log "DEBUG" "Can't copy to tmpfs"

matches=""

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Startup took $runtime seconds"
# Usage and argument parsing:1 ends here

# Get annotations


# [[file:cross-symbol-checker.org::*Get annotations][Get annotations:1]]
get_annotation_sources() {
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
        read source assembly version bed <<-EOF
$(echo ${custom_target_base} | awk -F"." '{print $1" "$2" "$3" "$4}')
EOF
        [ -z ${bed-} ] && targets="$targets\n$custom_target_base\tCustom\tCustom\t$custom_target" || targets="$targets\n$source\t$assembly\t$version\t$custom_target"
    done
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME setting up annotations took $runtime seconds"
}
# Get annotations:1 ends here

# Check capitalization

# [[file:cross-symbol-checker.org::*Check capitalization][Check capitalization:1]]
check_capitalization() {
start=$(date +%s)

symbol=$(echo "$1" | tr '[:lower:]' '[:upper:]' | awk '/C([1-9]|1[0-9]|2[0-2]|X|Y)ORF[0-9]+/ {gsub("ORF", "orf", $0)} 1')
if [ "$symbol" != "$1" ]; then
    echo "WARNING $1 capitalization changed to $symbol"
fi
end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking capitalization took $runtime seconds"
}
# Check capitalization:1 ends here

# Check if the given symbol is in the approved symbols.

# [[file:cross-symbol-checker.org::*Check if the given symbol is in the approved symbols.][Check if the given symbol is in the approved symbols.:1]]
check_approved() {
start=$(date +%s)

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
}
# Check if the given symbol is in the approved symbols.:1 ends here

# Check if the given symbol is an alias symbol.

# [[file:cross-symbol-checker.org::*Check if the given symbol is an alias symbol.][Check if the given symbol is an alias symbol.:1]]
check_alias() {
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
}
# Check if the given symbol is an alias symbol.:1 ends here

# Check if the given symbol is a previous symbol.

# [[file:cross-symbol-checker.org::*Check if the given symbol is a previous symbol.][Check if the given symbol is a previous symbol.:1]]
check_prev() {
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
}
# Check if the given symbol is a previous symbol.:1 ends here

# Check if the given symbol is withdrawn, split or merged.

# [[file:cross-symbol-checker.org::*Check if the given symbol is withdrawn, split or merged.][Check if the given symbol is withdrawn, split or merged.:1]]
check_withdrawn() {
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
}
# Check if the given symbol is withdrawn, split or merged.:1 ends here

# Get the approved symbol

# [[file:cross-symbol-checker.org::*Get the approved symbol][Get the approved symbol:1]]
get_approved_symbol() {
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
}
# Get the approved symbol:1 ends here

# Check for date


# [[file:cross-symbol-checker.org::*Check for date][Check for date:1]]
check_date() {
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
}
# Check for date:1 ends here

# Get the alias previous and withdrawn symbols


# [[file:cross-symbol-checker.org::*Get the alias previous and withdrawn symbols][Get the alias previous and withdrawn symbols:1]]
get_alias_prev_withdrawn() {
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
    log "INFO" "$approved_symbol has no prev symbol."
else
    prev_symbols="$(echo "$prev" | cut -f 1 | sed 's/^/PREV\t/')"
    echo "$prev_symbols"
fi

unset withdrawn
withdrawn=$(zcat -f $DATADIR/withdrawn.gz | (grep "|$approved_symbol|" || true))
if [ -z "$withdrawn" ]; then
    log "INFO" "$approved_symbol has no withdrawn symbol."
else
    withdrawn_symbols="$(echo "$withdrawn" | cut -f 3 | sed 's/^/WITHDRAWN\t/')"
    echo "$withdrawn_symbols"
fi

end=$(date +%s)
runtime=$((end - start))
log "DEBUG" "TIME Checking for other symbols took $runtime seconds"
}
# Get the alias previous and withdrawn symbols:1 ends here

# Check symbol in annotation sources


# [[file:cross-symbol-checker.org::*Check symbol in annotation sources][Check symbol in annotation sources:1]]
check_annotation_sources() {
    start=$(date +%s)

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
                        for contig in $(echo "${noncanonical-}"); do
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
    table=$(echo "$table" | sed '/^$/d;s/^/TABLE\t/')
}
# Check symbol in annotation sources:1 ends here

# main

# [[file:cross-symbol-checker.org::*main][main:1]]
main() {

    if [ $XCHECK = 0 ]; then
            log "INFO" "--no-cross-check is set. Not getting annotation sources."
    else
        get_annotation_sources
    fi

    input_count=$(echo "$@" | wc -w)
    versions=""
    warnings=""
    rows=""
    for symbol in $(echo "$@"); do
        check_capitalization "$symbol"
        check_approved
        check_alias
        check_prev
        check_withdrawn
        get_approved_symbol
        check_date

        if [ $XCHECK = 0 ]; then
             log "INFO" "--no-cross-check is set. Exiting without cross checking"
        else
            check_annotation_sources
        fi

        while read -r line; do
            case "$line" in
                "VERSION"* )
                    versions="$versions#$line\n"
                    ;;
                "WARNING"* )
                    warnings="$warnings#$line\n"
                    ;;
                "TABLE	Present"* )
                    rows="$rows$(echo "$line" | cut -f 3-12)\n"
                    ;;
            esac
        done <<-EOF
$(./cross-symbol-checker.sh "$symbol")
EOF
    done

    # Final checks about what is found and not.
    io_diff_message="#SUMMARY No difference between input and output counts."
    unmatched_symbols_message="#SUMMARY There are no unmatched symbols"

    unmatched_symbols_count=$(echo "$warnings" | grep "No approved symbol found" | wc -l)
    output_count=$(echo "$rows" | sed "/^$/d" | wc -l)

    io_diff=$(( output_count - input_count + unmatched_symbols_count ))

    if [ $unmatched_symbols_count -eq 0 ]; then
        if [ $io_diff -gt 0 ]; then
            io_diff_message="#SUMMARY There are $io_diff more outputs then inputs! this might happen if there are more than one symbol (e.g. both approved and an alias) for gene in the annotation"
        elif [ $io_diff -lt 0 ]; then # This should not happen? Because there are no unmatched symbols
            io_diff_message="#SUMMARY There are $(( io_diff * -1 )) more inputs then outputs. Check warnings for more info. The target doesn't have one or more symbols."
        else
            io_diff_message="#SUMMARY No difference between input and output counts."
        fi
    else
        unmatched_symbols_message="#SUMMARY There is/are $unmatched_symbols_count unmatched symbol(s)."
        if [ $io_diff -gt 0 ]; then
            io_diff_message="#SUMMARY There are $io_diff more outputs then inputs! this might happen if there are more than one symbol (e.g. both approved and an alias) for gene in the annotation. Or if you selected multiple sources, assemblies or versions."
        elif [ $io_diff -lt 0 ]; then
            io_diff_message="#SUMMARY There are $(( io_diff * -1 )) more inputs then outputs. Check warnings for more info."
        else
            io_diff_message="#SUMMARY There are no duplications for the symbols."
        fi
    fi


    echo "#COLUMN Input_symbol: Initial symbol entered.
#COLUMN Approved_symbol: Current symbol approved by HGNC for input symbol.
#COLUMN Symbol: This is the symbol found in annotation source. Pay extra attention if it's not an approved symbol.
#COLUMN Status: Status of the Symbol column. Either approved, alias, previous, or withdrawn.
#COLUMN Source: Annotation source.
#COLUMN Assembly: Target assembly.
#COLUMN Version: Version of the target source.
#COLUMN Chrom: name of the chromosome.
#COLUMN Start: start position of the gene.
#COLUMN End: end position of the gene.
#SUMMARY Number of input symbols are $input_count
#SUMMARY Number of output symbols are $output_count
$unmatched_symbols_message
$io_diff_message"
    echo "$(echo "$warnings" | sed "/^$/d" | grep . || echo "#SUMMARY There were no warnings about input symbols.")"
    if [ -z "${rows:-}" ]; then
        echo "No output was produced!"
    else
        echo "$(echo "$versions" | sed "/^$/d" | sort -u  | grep . || echo "#There is no version info")"
        echo "Input_symbol\tApproved_symbol\tSymbol\tStatus\tSource\tAssembly\tVersion\tChrom\tStart\tEnd"
        echo "$(echo "$rows" | sed "/^$/d")"
    fi
}

main "$@"
# main:1 ends here
