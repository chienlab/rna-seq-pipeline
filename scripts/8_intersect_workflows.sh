#!/bin/bash
#PBS -l nodes=1:ppn=1,mem=1g,walltime=5:00

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  Intersects workflow VCFs to find consensus variants & unique variants.
  This step is done once for an entire dataset of samples.
TOOLS:
  BCFtools
INPUT:
  Config file at <current directory>/CONFIG.sh
  VCF files at
    <workflow_vcf_dir>/gatk.merged.vcf
    <workflow_vcf_dir>/snpir.merged.vcf
    <workflow_vcf_dir>/rvboost.merged.vcf
OUTPUT:
  VCF files in <dataset_dir>/vcf-intersect"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

output_intersect_dir="$output_dir/vcf-intersect"
echo "Output Directory:  $output_intersect_dir"
mkdir -p "$output_intersect_dir"

#-------------------------------------------------------------------------------

gatk_vcf="$workflow_vcf_dir/gatk.merged.vcf"
snpir_vcf="$workflow_vcf_dir/snpir.merged.vcf"
rvboost_vcf="$workflow_vcf_dir/rvboost.merged.vcf"

gatk_vcf_gz="$output_intersect_dir/gatk.vcf.gz"
snpir_vcf_gz="$output_intersect_dir/snpir.vcf.gz"
rvboost_vcf_gz="$output_intersect_dir/rvooost.vcf.gz"

echo "BCFtools - Compressing VCFs for input into isec command"

"$bcftools" convert -O z "$gatk_vcf" > "$gatk_vcf_gz"
"$bcftools" convert -O z "$snpir_vcf" > "$snpir_vcf_gz"
"$bcftools" convert -O z "$rvboost_vcf" > "$rvboost_vcf_gz"

echo "BCFtools - Indexing VCFs for input into isec command"

"$bcftools" index --csi "$gatk_vcf_gz"
"$bcftools" index --csi "$snpir_vcf_gz"
"$bcftools" index --csi "$rvboost_vcf_gz"

#-------------------------------------------------------------------------------

echo "BCFtools - Intersecting to find consensus variants"

"$bcftools" isec \
    --prefix "$output_intersect_dir" \
    --collapse none \
    --nfiles ~111 \
    "$gatk_vcf_gz" "$snpir_vcf_gz" "$rvboost_vcf_gz"

mv "$output_intersect_dir"/{sites,consensus}.txt
mv "$output_intersect_dir"/{0000,consensus_gatk}.vcf
mv "$output_intersect_dir"/{0001,consensus_snpir}.vcf
mv "$output_intersect_dir"/{0002,consensus_rvboost}.vcf

echo "BCFtools - Intersecting to find variants unique to each workflow"

"$bcftools" isec \
    --prefix "$output_intersect_dir" \
    --collapse none \
    --nfiles =1 \
    "$gatk_vcf_gz" "$snpir_vcf_gz" "$rvboost_vcf_gz"

mv "$output_intersect_dir"/{sites,unique}.txt
mv "$output_intersect_dir"/{0000,unique_gatk}.vcf
mv "$output_intersect_dir"/{0001,unique_snpir}.vcf
mv "$output_intersect_dir"/{0002,unique_rvboost}.vcf

rm -f "$gatk_vcf_gz"* "$snpir_vcf_gz"* "$rvboost_vcf_gz"* "$output_intersect_dir/README.txt"
