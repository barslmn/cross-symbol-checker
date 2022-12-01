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
# 3. Check if prev, alias withdrwan symbols are in annotation sources.


# [[file:genesymbolchecker.org::*Validate gene symbol][Validate gene symbol:1]]
symbol=$1
matches=""
# Validate gene symbol:1 ends here

approved=$(zcat data/hgnc.gz | awk -F "\t" -v symbol=$symbol '$2==symbol {print}')
if [ -z "$approved" ]; then
    # Symbol is not in approved list or not a valid symbol
    echo "INFO $symbol is not in approved list :("
else
    # Symbol is in approved list.
    echo "INFO $symbol is in approved list."
    matches="$matches\nApproved\t$(echo "$approved" | cut -f 2)"
fi

alias=$(zcat data/alias.gz | awk -F "\t" -v symbol=$symbol '$1==symbol {print}')
if [ -z "$alias" ]; then
    # Symbol is not in alias or not a valid symbol
    echo "INFO $symbol is not an alias symbol."
else
    # Symbol is in alias symbols list.
    echo "INFO $symbol is an alias symbol."
    matches="$matches\nAlias\t$(echo "$alias" | cut -f 2)"
fi

prev=$(zcat data/prev.gz | awk -F "\t" -v symbol=$symbol '$1==symbol {print}')
if [ -z "$prev" ]; then
    # Symbol is not in previous symbols or not a valid symbol
    echo "INFO $symbol is not a previous symbol."
else
    # Symbol is in previous symbols list.
    echo "INFO $symbol is a previous symbol."
    matches="$matches\nPrev\t$(echo "$prev" | cut -f 2)"
fi

withdrawn=$(zcat data/withdrawn.gz | awk -F "\t" -v symbol=$symbol '$3==symbol {print}')
if [ -z "$withdrawn" ]; then
    # Symbol is not withdrawn or not a valid symbol
    echo "INFO $symbol is not in withdrawn list."
else
    # Symbol is withdrawn/merged/split
    echo "$withdrawn" | read -r ID STATUS SYMBOL REPORTS
    case STATUS in
        "Entry Withdrawn")
            echo "WITHDRAWN $symbol is gone!"
            ;;
        "Merged/Split")
            echo "$REPORTS" |
                tr ', ' '\n' |
                sed '/^$/d;s/|/ /g' |
                while read -r NEWID NEWSYMBOL NEWSTATUS; do
                    case "$NEWSTATUS" in
                        "Entry Withdrawn")
                            echo "MERGED/SPLIT $symbol has been $STATUS into $NEWSYMBOL which itself also got withdrawn. ;("
                            # matches="$matches\nWithdrawn but it got withdrawn too."
                            ;;
                        "Approved")
                            echo "MERGED/SPLIT $symbol now lives on with the name $NEWSYMBOL."
                            matches="$matches\nWithdrawn$NEWSYMBOL"
                            ;;
                    esac
                done
            ;;
    esac
fi

# We collect all possible approved_symbol(s) which we expect to be only one.
# However we check in case a symbol maps to multiple symbols.
if [ $(echo "$matches" | sed '/^$/d' | sort -u | wc -l) -eq 1 ]; then # this is what we expect.
    case $found_in in
        "Approved")
            echo "INFO $1 was already an approved symbol."
            ;;
        "Prev")
            echo "INFO previous symbol $1 mapped to an approved symbol."
            ;;
        "Alias")
            echo "INFO alias symbol $1 mapped to an approved symbol."
            ;;
    esac
    approved_symbol=$(echo $matches | sed '/^$/d' | cut -f 2)
    echo "APPROVED\t$approved_symbol"

else
    # Some approved symbols are alias to other symbols
    # We are going to handle this case by picking the
    # original input.
    echo "WARN $1 mapped to multiple symbols!"
    echo "WARN $(echo "$matches" | sed '/^$/d' | cut -f 2 | tr '\n' ' ')"
    while read -r found_in appr_sym; do
        case $found_in in
            "Approved")
                echo "INFO Orginal input $1 already was an approved symbol. Carrying out with this symbol."
                approved_symbol="$appr_sym"
                echo "APPROVED\t$approved_symbol"
                ;;
            "Prev")
                echo "WARN $1 was also $found_in symbol for approved symbol $appr_sym."
                ;;
            "Alias")
                echo "INFO $1 was also $found_in symbol for approved symbol $appr_sym."
                ;;
        esac
    done <<-EOF
$(echo "$matches")
EOF
fi

if [ -z "$approved_symbol" ]; then
    echo "WARN couldn't find an approved symbol for $symbol"
    is_date=$(date -d "$symbol" 2>1 | grep -v "invalid")
    if [ -z "$is_date"]; then
        echo "INFO doesn't look like a date."
    else
        echo "WARN This is a date"
    fi
    exit
else
    :
fi

unset alias
alias=$(zcat data/alias.gz | awk -F "\t" -v symbol=$approved_symbol '$2==symbol {print}')
if [ -z "$alias" ]; then
    # Symbol is not in alias or not a valid symbol
    echo "INFO $approved_symbol has no alias symbol."
else
    # Symbol is in alias symbols list.
    alias_symbols="$(echo "$alias" | cut -f 1)"
    echo "$(echo "$alias_symbols" | sed 's/^/ALIAS\t/')"
fi

unset prev
prev=$(zcat data/prev.gz | awk -F "\t" -v symbol=$approved_symbol '$2==symbol {print}')
if [ -z "$prev" ]; then
    # Symbol is not in alias or not a valid symbol
    echo "INFO $approved_symbol has no prev symbol."
else
    # Symbol is in alias symbols list.
    prev_symbols="$(echo "$prev" | cut -f 1)"
    echo "$(echo "$prev_symbols" | sed 's/^/PREV\t/')"
fi

unset withdrawn
withdrawn=$(zcat data/withdrawn.gz | grep "|$approved_symbol|")
if [ -z "$withdrawn" ]; then
    # Symbol is not in alias or not a valid symbol
    echo "INFO $approved_symbol has no withdrawn symbol."
else
    # Symbol is in alias symbols list.
    withdrawn_symbols="$(echo "$withdrawn" | awk -F"\t" '{print $3}')"
    echo "$(echo "$withdrawn_symbols" | sed 's/^/WITHDRAWN\t/')"
fi

check_noncanonical() {
    for contig in $(echo "$noncanonical"); do
        if echo "$match" | grep -q "$contig"; then
            echo "WARN Symbol not in a canonical chromosome"
        fi
    done
}

sources="
Ensembl
RefSeq
"
assemblies="
GRCh37
GRCh38
T2T
"
table=""
if [ -z "$approved_symbol" ]; then
    echo "INFO no approved symbol found so not checking annotation sources for approved symbol."
else
    for source in $(echo "$sources"); do
        for assembly in $(echo "$assemblies"); do

            # Print out gff meta data
            source_info=$(zcat data/$source.$assembly.bed.gz | grep -m 3 '^#!' | sed "s/^#!/INFO VERSION $source $assembly /")
            echo "$source_info"

            # Get the non canonical chromosomes
            case "$source" in
                "RefSeq")
                    noncanonical=$(zcat "data/$source.$assembly.bed.gz" | grep -v "^#" | awk -F"\t" '{print $1}' | sort -u | grep -v '^NC');
                    ;;
                "Ensembl")
                    noncanonical=$(zcat "data/$source.$assembly.bed.gz" | grep -v '^#' | awk -F"\t" '{print $1}' | sort -u | grep -vE 'chr([1-9]|1[0-9]|2[0-2]|X|Y|MT)');
                    ;;
            esac


            ###### TODO this part in a for loop ############
            # We preprocess these files so we can just use grep with -w instead of awk
            match=$(zcat data/$source.$assembly.bed.gz | grep -w "$approved_symbol")
            check_noncanonical
            if [ -z "$match" ]; then
                echo "INFO APPROVED SYMBOL $approved_symbol found in $source $assembly"
                table="$table$approved_symbol\t$approved_symbol\tAPPROVED\t$source\t$assembly\tNotFound\n"
            else
                echo "INFO APPROVED SYMBOL $approved_symbol not found in $source $assembly"
                table="$table$approved_symbol\t$approved_symbol\tAPPROVED\t$source\t$assembly\tFound\n"
            fi
            # Check if alias, previous or withdrawn symbol is in the annotations
            for prev_symbol in $(echo "$prev_symbols"); do
                match=$(zcat data/$source.$assembly.bed.gz | grep -w "$prev_symbols")
                check_noncanonical
                if [ -z "$match" ]; then
                    echo "INFO PREV SYMBOL $prev_symbol found in $source $assembly"
                    table="$table$approved_symbol\t$prev_symbol\tPREV\t$source\t$assembly\tNotFound\n"
                else
                    echo "INFO PREV SYMBOL $prev_symbol not found in $source $assembly"
                    table="$table$approved_symbol\t$prev_symbol\tPREV\t$source\t$assembly\tFound\n"
                fi
            done
            for alias_symbol in $(echo "$alias_symbols"); do
                match=$(zcat data/$source.$assembly.bed.gz | grep -w "$alias_symbol")
                check_noncanonical
                if [ -z "$match" ]; then
                    table="$table$approved_symbol\t$alias_symbol\tALIAS\t$source\t$assembly\tNotFound\n"
                    echo "INFO ALIAS SYMBOL $alias_symbol found in $source $assembly"
                else
                    table="$table$approved_symbol\t$alias_symbol\tALIAS\t$source\t$assembly\tFound\n"
                    echo "INFO ALIAS SYMBOL $alias_symbol not found in $source $assembly"
                fi
            done
            for withdrawn_symbol in $(echo "$withdrawn_symbols"); do
                match=$(zcat data/$source.$assembly.bed.gz | grep -w "$withdrawn_symbol")
                check_noncanonical
                if [ -z "$match" ]; then
                    table="$table$approved_symbol\t$withdrawn_symbol\tWITHDRAWN\t$source\t$assembly\tNotFound\n"
                    echo "INFO WITHDRAWN SYMBOL $withdrawn_symbol found in $source $assembly"
                else
                    table="$table$approved_symbol\t$withdrawn_symbol\tWITHDRAWN\t$source\t$assembly\tFound\n"
                    echo "INFO WITHDRAWN SYMBOL $withdrawn_symbol not found in $source $assembly"
                fi
            done
            ###### TODO this part in a for loop ############
        done
    done
fi
echo "$(echo "$table" | sed '/^$/d;s/^/TABLE\t/')"
