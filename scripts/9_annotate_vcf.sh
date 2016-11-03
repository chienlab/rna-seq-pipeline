#!/bin/bash

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  Annotates group & workflow VCFs.
  This step is done once for an entire dataset of samples.
TOOLS:
  Annovar
INPUT:
  Config file at <current directory>/CONFIG.sh
  VCF files in
    <group_vcf_dir>/gatk  <group_vcf_dir>/snpir  <group_vcf_dir>/rvboost
    <workflow_vcf_dir>
OUTPUT:
  VCF files in the input directories"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

# ------------------------------------------------------------------------------

function annotate_vcf {
    local input_vcf=$1

    local vcf_dir=$(dirname "$input_vcf")
    local vcf_name=$(basename "$input_vcf" ".vcf")

    echo "Annotating VCF: $input_vcf"

    "$table_annovar" \
        -vcfinput "$input_vcf" \
        "$annovar_dir/humandb/" \
        -buildver hg19 \
        -remove \
        -protocol refGene,cytoBand,genomicSuperDups,esp6500siv2_all,1000g2014oct_all,1000g2014oct_afr,1000g2014oct_eas,1000g2014oct_eur,snp138,ljb26_all,cosmic70 \
        -operation g,r,r,f,f,f,f,f,f,f,f \
        --nastring . --otherinfo \
        -out "$vcf_dir/$vcf_name.merged.annotated"
}

# ------------------------------------------------------------------------------

workflow_names="gatk snpir rvboost"
group_ids=$("$query_dataset_script" groups "$dataset_xml")

for workflow_name in $workflow_names; do
    annotate_vcf "$workflow_vcf_dir/$workflow_name.merged.vcf"

    for group_id in $group_ids; do
        annotate_vcf "$group_vcf_dir/$workflow_name/$group_id.merged.vcf"
    done
done
