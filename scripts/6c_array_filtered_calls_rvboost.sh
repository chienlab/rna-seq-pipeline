#!/bin/bash
#PBS -l nodes=1:ppn=6,mem=16g,walltime=3:00:00
#PBS -M SeijiSuenaga@gmail.com
#PBS -m abe

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  Generates a filtered set of variant calls using RVboost, which uses
  UnifiedGenotyper as its variant caller.
  This step is done once for each sample and can be run as a qsub job array.
TOOLS:
  RVboost (RNA-seq variants prioritization using a boosting method)
INPUT:
  Config file at <current directory>/CONFIG.sh
  BAM file(s) at <dataset_dir>/<sample dir>/refined-mapping/<sample>.refined.bam
OUTPUT:
  VCF files in <output_dir>/<sample dir>/unifiedgenotyper/rvboost"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

sample_dir=$(echo "$sample_dir_list" | head -$PBS_ARRAYID | tail -1)
sample_id=$(echo "$sample_list" | head -$PBS_ARRAYID | tail -1)

input_bam="$dataset_dir/$sample_dir/refined-mapping/$sample_id.refined.bam"
echo "Input BAM file:  $input_bam"

output_rvboost_dir="$output_dir/$sample_dir/unifiedgenotyper/rvboost"
echo "Output Directory:  $output_rvboost_dir"
mkdir -p "$output_rvboost_dir"

# ------------------------------------------------------------------------------
# Call variants & rank them by confidence (add annotations: OrgScore, QScore)
# ------------------------------------------------------------------------------

echo "RVboost - Calling & filtering variants"
"$rvboost_dir/src/RV.Boosting.sh" \
    -R "$input_bam" \
    -s "$sample_id" \
    -c "$rvboost_dir/config.txt" \
    -o "$output_rvboost_dir" \
    -T 6

# ------------------------------------------------------------------------------
# Rename output files to be more consistent with the GATK & SNPiR workflows
# ------------------------------------------------------------------------------

output_prefix="$output_rvboost_dir/$sample_id"
default_raw_path="$output_prefix.raw.vcf"
renamed_raw_path="$output_prefix.ug.raw.vcf"
default_scored_path"$output_prefix.filter.vcf"
renamed_scored_path"$output_prefix.ug.rvboost.scored.vcf"
mv "$default_raw_path" "$renamed_raw_path"
mv "$default_scored_path" "$renamed_scored_path"

# ------------------------------------------------------------------------------
# Filter variants by QScore
# ------------------------------------------------------------------------------

min_qscore=0.05
echo "Filtering variants with RVboost QScore < $min_qscore"
filtered_path="$output_prefix.ug.rvboost.filtered.vcf"

awk_filter_script='{
    OFS = "\t"

    # Print header lines
    if ($0 ~ /^#/) {
        print $0
        next
    }

    field_count = split($8, info_fields, ";")

    # Print variants that satisfy the minimum QScore
    for (i = 1; i <= field_count; ++i) {
        split(info_fields[i], field, "=")
        field_key = field[1]
        field_val = field[2]
        if (field_key == "QScore") {
            if (field_val >= awk_min_qscore)
                print $0
            next
        }
    }
}'

awk \
    -v awk_min_qscore=$min_qscore \
    "$awk_filter_script" \
    "$renamed_scored_path" \
    > "$filtered_path"
