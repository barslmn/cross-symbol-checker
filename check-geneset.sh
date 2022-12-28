#!/bin/sh
set -o errexit
set -o nounset
if [ "${TRACE-0}" = "1" ]; then
    set -o xtrace
fi

if [ "${1-}" = "help" ]; then
    echo 'Usage: ./check-geneset.sh symbol1 symbol2 -a T2T -s RefSeq -v latest
-a --assembly
    Default assemblies are GRCh37, GRCh38 and T2T.
    You can use multiple assemblies by quoting them together like -a "GRCh37 GRCh38"
-h --help
    Display this help message and exit.
-o --only-target
    Without source, assembly, version parameters check-geneset.sh will run
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
-V
    Print current version and exit
'
    exit
fi

cd "$(dirname "$0")"
. ./logger.sh

PARSED_ARGUMENTS=$(getopt -a -o a:hos:v:Vt: -l assembly:,help,only-target,source:,version:,target: -- "$@")
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
    -h | --help)
        usage
        ;;
    -o | --only-target)
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


export CSC_SOURCES
export CSC_ASSEMBLIES
export CSC_VERSIONS
export CSC_TARGETS

cp -r data/ /dev/shm/CSC_DATA || log "DEBUG" "Can't copy to tmpfs"


main() {
    input_count=$(echo "$@" | wc -w)
    versions=""
    warnings=""
    rows=""
    for symbol in $(echo "$@"); do
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
    io_diff_message="#No difference between input and output counts."
    unmatched_symbols_message="#There are no unmatched symbols"

    unmatched_symbols_count=$(echo "$warnings" | grep "No approved symbol found" | wc -l)
    output_count=$(echo "$rows" | sed "/^$/d" | wc -l)

    io_diff=$(( output_count - input_count + unmatched_symbols_count ))

    if [ $unmatched_symbols_count -eq 0 ]; then
        if [ $io_diff -gt 0 ]; then
            io_diff_message="#There are $io_diff more outputs then inputs! this might happen if there are more than one symbol (e.g. both approved and an alias) for gene in the annotation"
        elif [ $io_diff -lt 0 ]; then # This should not happen? Because there are no unmatched symbols
            io_diff_message="#There are $(( io_diff * -1 )) more inputs then outputs. Check warnings for more info. The target doesn't have one or more symbols."
        else
            io_diff_message="#No difference between input and output counts."
        fi
    else
        unmatched_symbols_message="#There is/are $unmatched_symbols_count unmatched symbol(s)."
        if [ $io_diff -gt 0 ]; then
            io_diff_message="#There are $io_diff more outputs then inputs! this might happen if there are more than one symbol (e.g. both approved and an alias) for gene in the annotation. Or if you selected multiple sources, assemblies or versions."
        elif [ $io_diff -lt 0 ]; then
            io_diff_message="#There are $(( io_diff * -1 )) more inputs then outputs. Check warnings for more info."
        else
            io_diff_message="#There are no duplications for the symbols."
        fi
    fi


    echo "#Input_symbol: Initial symbol entered.
#Approved_symbol: Current symbol approved by HGNC for input symbol.
#Symbol: This is the symbol found in annotation source. This is most likely will be the approved symbol however, might also be the alias, previous, or the withdrawn symbol.
#Status: Status of the Symbol column. Either approved, alias, previous, or withdrawn.
#Source: Annotation source.
#Assembly: Target assembly.
#Version: Version of the target source.
#Chrom: name of the chromosome.
#Start: start position of the gene.
#End: end position of the gene.
#Number of input symbols are $input_count
#Number of output symbols are $output_count
$unmatched_symbols_message
$io_diff_message"
    echo "$(echo "$warnings" | sed "/^$/d" | grep . || echo "#There were no warnings about input symbols.")"
    if [ -z "${rows:-}" ]; then
        echo "No output was produced!"
    else
        echo "$(echo "$versions" | sed "/^$/d" | sort -u  | grep . || echo "#There is no version info")"
        echo "Input_symbol\tApproved_symbol\tSymbol\tStatus\tSource\tAssembly\tVersion\tChrom\tStart\tEnd"
        echo "$(echo "$rows" | sed "/^$/d")"
    fi
}

main "$@"
