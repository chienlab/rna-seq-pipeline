#!/bin/bash
#PBS -l nodes=1:ppn=2,mem=16g,walltime=02:00:00

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  This script, when submitted as an array of jobs via \"qsub -t 1-n\",
  converts a set of BAM files to FASTQ files.  This step is only
  needed if you don't have the original FASTQ files.
TOOLS:
  biobambam2
INPUT:
  Config file at <current directory>/CONFIG.sh
  BAM file(s) at <dataset_dir>/<sample dir>/<sample>.bam
OUTPUT:
  FASTQ files at <output_dir>/<sample dir>/<sample><fastq_file_suffix>"

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

input_bam_file="$dataset_dir/$sample_dir/$sample_id.bam"
echo "Converting BAM: $input_bam_file"

output_dir="$output_dir/$sample_dir"
echo "Output Directory: $output_dir"
mkdir -p "$output_dir"

"$biobambam2_bamtofastq" \
    gz=1 \
    level=4 \
    filename="$input_bam_file" \
    F="$output_dir/$sample_id$r1_fastq_file_suffix" \
    F2="$output_dir/$sample_id$r2_fastq_file_suffix"
