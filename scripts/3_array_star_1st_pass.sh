#!/bin/bash
#PBS -l nodes=1:ppn=10,mem=32g,walltime=02:00:00
#PBS -M SeijiSuenaga@gmail.com
#PBS -m abe

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  STAR 2-pass mapping, step 2 of 4:  1st Pass
  Uses reference genome index without splice junction info.
  This step is done once for each sample and can be run as a qsub job array.
TOOLS:
  STAR RNA-seq Aligner
INPUT:
  Config file at <current directory>/CONFIG.sh
  FASTQ files at <dataset_dir>/<sample dir>/<sample><fastq_file_suffix>
  STAR reference genome index in <star_index_dir>
OUTPUT:
  Splice junction files at <output_dir>/<sample dir>/star-pass1/<sample>.SJ.out.tab"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

echo "Reference genome index directory:  $star_index_dir"
if [ $use_compressed_fastq -eq 1 ]; then
    echo "Using compressed input files"             # If input is compressed,
    compressed_input_arg="--readFilesCommand zcat"  # STAR needs special param
fi

sample_dir=$(echo "$sample_dir_list" | head -$PBS_ARRAYID | tail -1)
sample_id=$(echo "$sample_list" | head -$PBS_ARRAYID | tail -1)

read_1="$dataset_dir/$sample_dir/$sample_id$r1_fastq_file_suffix"
read_2="$dataset_dir/$sample_dir/$sample_id$r2_fastq_file_suffix"
echo "Input read 1:  $read_1"
echo "Input read 2:  $read_2"

pass1_dir="$output_dir/$sample_dir/star-pass1"
echo "Output directory:  $pass1_dir"
mkdir -p "$pass1_dir"

"$star" \
    --genomeDir "$star_index_dir" \
    --readFilesIn "$read_1" "$read_2" \
    $compressed_input_arg \
    --outFileNamePrefix "$pass1_dir/$sample_id." \
    --outSAMtype None \
    --runThreadN 10
