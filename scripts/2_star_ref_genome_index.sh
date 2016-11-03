#!/bin/bash
#PBS -l nodes=1:ppn=10,mem=32g,walltime=3:00:00

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  STAR 2-pass mapping, step 1 of 4:  Create Genome Index
  Indexes the given reference genome.  This step is done once per reference
  genome (index can be used to map any BAM to the given reference genome).
TOOLS:
  STAR RNA-seq Aligner
INPUT:
  Config file at <current directory>/CONFIG.sh
  FASTQ files at <dataset_dir>/<sample dir>/<sample><fastq_file_suffix>
OUTPUT:
  STAR index files in <output_dir>/<star_index_dir>"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

echo "Indexing reference genome:  $ref_genome_fasta"
echo "Using annotations:  $ref_genome_annotations"
echo "Output directory:  $star_index_dir"

mkdir -p "$star_index_dir"

"$star" \
    --runMode genomeGenerate \
    --genomeFastaFiles "$ref_genome_fasta" \
    --sjdbGTFfile "$ref_genome_annotations" \
    --genomeDir "$star_index_dir" \
    --sjdbOverhang "$fastq_read_length" \
    --runThreadN 10
