#!/bin/sh
. ./logger.sh
mkdir -p data
cd data
# HGNC approved symbols
wget -O- -q http://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/tsv/hgnc_complete_set.txt | gzip -c > hgnc.gz
# map synonyms and previous symbols to current symbols
OTHERSYMBOLS="
prev
alias
"
echo "$OTHERSYMBOLS" | sed '/^$/d' | while read -r other;
do
    current=$(zcat -f hgnc.gz | sed 1q | tr $'\t' '\n' | nl | grep -m1 "symbol" | cut -f1 | tr -d " ")
    other_col=$(zcat -f hgnc.gz | sed 1q | tr $'\t' '\n' | nl | grep "$other"_symbol | cut -f1 | tr -d " ")
    zcat -f hgnc.gz | tr -d '"' | awk -F "\t" -v current=$current -v other_col=$other_col '{split($other_col, others,"|"); for (o in others) {printf "%s\t%s\n", others[o], $current}}' | gzip -c > $other.gz
done
# HGNC withdrawn symbols
wget -O- -q http://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/tsv/withdrawn.txt | gzip -c > withdrawn.gz

# Entrez gene symbols
wget -O- -q https://ftp.ncbi.nih.gov/gene/DATA/GENE_INFO/Mammalia/Homo_sapiens.gene_info.gz > entrez.gz


# Annotation files, download and parse
annotations="
RefSeq  GRCh37 latest https://ftp.ncbi.nlm.nih.gov/refseq/H_sapiens/annotation/GRCh37_latest/refseq_identifiers/GRCh37_latest_genomic.gff.gz
RefSeq  GRCh38 latest https://ftp.ncbi.nlm.nih.gov/refseq/H_sapiens/annotation/GRCh38_latest/refseq_identifiers/GRCh38_latest_genomic.gff.gz
RefSeq  T2T    latest https://ftp.ncbi.nlm.nih.gov/refseq/H_sapiens/annotation/annotation_releases/110/GCF_009914755.1_T2T-CHM13v2.0/GCF_009914755.1_T2T-CHM13v2.0_genomic.gff.gz
Ensembl GRCh37 release97 https://ftp.ensembl.org/pub/grch37/release-97/gff3/homo_sapiens/Homo_sapiens.GRCh37.87.gff3.gz
Ensembl GRCh37 latest https://ftp.ensembl.org/pub/grch37/release-108/gff3/homo_sapiens/Homo_sapiens.GRCh37.87.gff3.gz
Ensembl GRCh38 latest https://ftp.ensembl.org/pub/current_gff3/homo_sapiens/Homo_sapiens.GRCh38.108.chr_patch_hapl_scaff.gff3.gz
Ensembl T2T    latest https://ftp.ensembl.org/pub/rapid-release/species/Homo_sapiens/GCA_009914755.4/ensembl/geneset/2022_07/Homo_sapiens-GCA_009914755.4-2022_07-genes.gff3.gz
"
echo "$annotations" | sed '/^$/d' | while read -r source assembly version url; do
    log "INFO" "Downloading $source annotation for $version version $assembly assembly.";
    log "INFO" "Downloading from $url";

    case "$source" in
        "RefSeq")
            wget -q -O- "$url" \
                | zcat \
                | awk -F"\t" \
                    '
                    /^#!/ {print}
                    /^##/ {next}
                    $3~/gene/ {
                        # sub(/^NC_[0]+/, "chr");
                        # sub(/^chr23/, "chrX"); sub(/^chr24/, "chrY");
                        # split($1,chrom,".");
                        split($9,info,"gene=");
                        split(info[2],gene,";");
                        # printf "%s\t%s\t%s\t%s\n", chrom[1], $4, $5, gene[1]}
                        printf "%s\t%s\t%s\t%s\n", $1, $4, $5, gene[1]}' |
                gzip -c > $source.$assembly.$version.bed.gz &&
                log "INFO" "BED file created at $source.$assembly.$version.bed.gz" ||
                log "ERROR" "An error occured while creating BED file at $source.$assembly.$version.bed.gz";
            ;;
        "Ensembl")
            wget -q -O- "$url" | zcat | awk -F"\t" \
                    '
                    /^#!/ {print}
                    /^##/ {next}
                    $3~/gene/ {
                        split($9,info,"Name=");
                        split(info[2],gene,";");
                        printf "chr%s\t%s\t%s\t%s\n", $1, $4, $5, gene[1]}' |
                gzip -c > $source.$assembly.$version.bed.gz &&
                log "INFO" "BED file created at $source.$assembly.$version.bed.gz" ||
                log "ERROR" "An error occured while creating BED file at $source.$assembly.$version.bed.gz";
            ;;
    esac
done
