#!/bin/bash
#PBS -l nodes=1:ppn=10,mem=32g,walltime=6:00:00

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  STAR 2-pass mapping, BASIC.
  This is an alternate version of STAR 2-pass mapping, for datasets with only 1
  sample per patient.  For such datasets, the 2nd pass mapping of a sample only
  needs splice junction info from that sample, not all samples.  So, this script
  uses STAR 'basic' 2-pass mapping to performs both passes in one step.
  This step is done once for each sample and can be run as a qsub job array.
TOOLS:
  STAR RNA-seq Aligner
INPUT:
  Config file at <current directory>/CONFIG.sh
  FASTQ files at <dataset_dir>/<sample dir>/<sample><fastq_file_suffix>
  STAR reference genome index in <star_index_dir>
OUTPUT:
  Mapped reads at <output_dir>/<sample dir>/star-pass2/<sample>.Aligned.out.sam
  Expression info at <output_dir>/<sample dir>/star-pass2/<sample>.Aligned.toTranscriptome.out.bam"

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
    compressed_input_arg="--readFilesCommand zcat"  # STAR needs special argument
fi

sample_dir=$(echo "$sample_dir_list" | head -$PBS_ARRAYID | tail -1)
sample_id=$(echo "$sample_list" | head -$PBS_ARRAYID | tail -1)

read_1="$dataset_dir/$sample_dir/$sample_id$r1_fastq_file_suffix"
read_2="$dataset_dir/$sample_dir/$sample_id$r2_fastq_file_suffix"
echo "Input read 1:  $read_1"
echo "Input read 2:  $read_2"

pass2_dir="$output_dir/$sample_dir/star-pass2"
echo "Output directory:  $pass2_dir"
mkdir -p "$pass2_dir"

"$star" \
    --genomeDir "$star_index_dir" \
    --readFilesIn "$read_1" "$read_2" \
    $compressed_input_arg \
    --outFileNamePrefix "$pass2_dir/$sample_id." \
    --outSAMattributes NH HI AS nM NM MD \
    --outSAMtype BAM Unsorted \
    --quantMode TranscriptomeSAM \
    --twopassMode Basic \
    --runThreadN 10
