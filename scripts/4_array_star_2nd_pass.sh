#!/bin/bash
#PBS -l nodes=1:ppn=10,mem=32g,walltime=06:00:00

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  STAR 2-pass mapping, step 4 of 4:  2nd Pass
  Uses reference genome index generated with splice junction info from 1st pass.
  This step is done once for each sample and can be run as a qsub job array.
TOOLS:
  STAR RNA-seq Aligner
INPUT:
  Config file at <current directory>/CONFIG.sh
  FASTQ files at <dataset_dir>/<sample dir>/<sample><fastq_file_suffix>
  STAR reference genome index in <star_index_dir>
  STAR splice junction info in <dataset_dir>/<sample dir>/star-pass1
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

sample_dir=$(echo "$sample_dir_list" | head -$PBS_ARRAYID | tail -1)
sample_id=$(echo "$sample_list" | head -$PBS_ARRAYID | tail -1)

patient_id=$("$query_dataset_script" patient "$sample_id" "$dataset_xml")
patient_samples=$("$query_dataset_script" samples "$patient_id" "$dataset_xml")

echo "Using splice junction files for patient $patient_id:"
for patient_sample in $patient_samples; do
    patient_sample_dir=$("$query_dataset_script" sampledir "$patient_sample" "$dataset_xml")
    sj_path="$dataset_dir/$patient_sample_dir/star-pass1/$patient_sample.SJ.out.tab"

    if [ ! -e "$sj_path" ]; then
        echo "ERROR - Splice junction file doesn't exist:"
        echo "$sj_path"
        exit 1
    fi
    echo "  $sj_path"

    splice_junction_files+=" $sj_path"
done

if [ $use_compressed_fastq -eq 1 ]; then
    echo "Using compressed input files"             # If input is compressed,
    compressed_input_arg="--readFilesCommand zcat"  # STAR needs special argument
fi

read_1="$dataset_dir/$sample_dir/$sample_id$r1_fastq_file_suffix"
read_2="$dataset_dir/$sample_dir/$sample_id$r2_fastq_file_suffix"
echo "Input read 1:  $read_1"
echo "Input read 2:  $read_2"

pass2_dir="$output_dir/$sample_dir/star-pass2"
echo "Output directory:  $pass2_dir"
mkdir -p "$pass2_dir"

echo "STAR - Mapping to reference genome index using splice junction info from 1st pass"
"$star" \
    --genomeDir "$star_index_dir" \
    --readFilesIn "$read_1" "$read_2" \
    $compressed_input_arg \
    --sjdbFileChrStartEnd $splice_junction_files \
    --outFileNamePrefix "$pass2_dir/$sample_id." \
    --outSAMattributes NH HI AS nM NM MD \
    --outSAMtype BAM Unsorted \
    --outFilterType BySJout \
    --outFilterMultimapNmax 20 \
    --outFilterMismatchNmax 999 \
    --outFilterMismatchNoverLmax 0.04 \
    --alignIntronMin 20 \
    --alignIntronMax 1000000 \
    --alignMatesGapMax 1000000 \
    --alignSJoverhangMin 8 \
    --alignSJDBoverhangMin 1 \
    --sjdbScore 1 \
    --runThreadN 10
