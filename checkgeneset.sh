#!/bin/sh
set -o errexit
set -o nounset
if [ "${TRACE-0}" = "1" ]; then
    set -o xtrace
fi

if [ "${1-}" = "help" ]; then
    echo 'Usage: ./script.sh arg-one arg-two

This is an awesome bash script to make your life better.

'
    exit
fi

cd "$(dirname "$0")"

PARSED_ARGUMENTS=$(getopt -a -o s:a: -l source:,assembly: -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
    usage
fi

eval set -- "$PARSED_ARGUMENTS"
while :; do
    case "$1" in
    -s | --source)
        GSC_SOURCES="$2"
        shift 2
        ;;
    -a | --assembly)
        GSC_ASSEMBLIES="$2"
        shift 2
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

export GSC_SOURCES
export GSC_ASSEMBLIES

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
                    rows="$rows$(echo "$line" | cut -f 3-11)\n"
                    ;;
            esac
        done <<-EOF
$(./genesymbolchecker.sh "$symbol")
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
            io_diff_message="#There are $(( io_diff * -1 )) more inputs then outputs. Check warnings for more info. This shouldn't have happened:?"
        else
            io_diff_message="#No difference between input and output counts."
        fi
    else
        unmatched_symbols_message="#There is/are $unmatched_symbols_count unmatched symbol(s)."
        if [ $io_diff -gt 0 ]; then
            io_diff_message="#There are $io_diff more outputs then inputs! this might happen if there are more than one symbol (e.g. both approved and an alias) for gene in the annotation"
        elif [ $io_diff -lt 0 ]; then
            io_diff_message="#There are $(( io_diff * -1 )) more inputs then outputs. Check warnings for more info."
        else
            io_diff_message="#There are no multiple entries for symbols."
        fi
    fi


    echo "#Input_symbol: Initial symbol entered.
#Approved_symbol: Current symbol approved by HGNC for input symbol.
#Symbol: This is the symbol found in annotation source. This is most likely will be the approved symbol however, might also be the alias, previous, or the withdrawn symbol.
#Status: Status of the Symbol column. Either approved, alias, previous, or withdrawn.
#Source: Annotation source.
#Assembly: Target assembly.
#Chrom: name of the chromosome.
#Start: start position of the gene.
#End: end position of the gene.
#Number of input symbols are $input_count
#Number of output symbols are $output_count
$unmatched_symbols_message
$io_diff_message"
    echo "$(echo "$warnings" | sed "/^$/d")"
    echo "$(echo "$versions" | sed "/^$/d" | sort -u)"
    echo "Input_symbol\tApproved_symbol\tSymbol\tStatus\tSource\tAssembly\tChrom\tStart\tEnd"
    echo "$(echo "$rows" | sed "/^$/d")"
}

main "$@"
