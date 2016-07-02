#!/bin/bash
#PBS -l nodes=2:ppn=6,mem=32g,walltime=36:00:00
#PBS -M SeijiSuenaga@gmail.com
#PBS -m abe

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  Adds read groups, sorts, marks duplicates, splits reads that span splice
  junctions, creates index, realigns around known indels & SNPs, reassigns
  mapping qualities, and recalibrates base quality scores.
  This step is done once for each sample and can be run as a qsub job array.
TOOLS:
  Java
  Picard
  GATK
INPUT:
  Config file at <current directory>/CONFIG.sh
  STAR mapping at <dataset_dir>/<sample dir>/star-pass2/<sample>.Aligned.out.bam
  Reference genome at <ref_genome_fasta>
  Known variant lists at
    <known_mills_indel_vcf>, <known_1kg_indel_vcf>, <known_dbsnp_vcf>
OUTPUT:
  Mapping at <output_dir>/<sample dir>/refined-mapping/<sample>.refined.bam"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

echo "Reference genome FASTA:  $ref_genome_fasta"
echo "Input Dataset Directory:  $dataset_dir"

sample_dir=$(echo "$sample_dir_list" | head -$PBS_ARRAYID | tail -1)
sample_id=$(echo "$sample_list" | head -$PBS_ARRAYID | tail -1)

output_sample_dir="$output_dir/$sample_dir/refined-mapping"
echo "Output Directory:  $output_sample_dir"
mkdir -p "$output_sample_dir"

#-------------------------------------------------------------------------------
# Refine with Picard
#-------------------------------------------------------------------------------

echo "Picard AddOrReplaceReadGroups - Adding read groups & sorting"
grouped_sorted_bam="$output_sample_dir/reads_grouped_sorted.bam"

"$java" \
    -d64 -Xmx8g -jar "$picard_jar" AddOrReplaceReadGroups \
    INPUT="$dataset_dir/$sample_dir/star-pass2/$sample_id.Aligned.out.bam" \
    OUTPUT="$grouped_sorted_bam" \
    SORT_ORDER=coordinate \
    RGID="$sample_id" \
    RGLB=stranded \
    RGPL=illumina \
    RGPU="barcode" \
    RGSM="$sample_id" \
    VALIDATION_STRINGENCY=SILENT

echo "Picard MarkDuplicates - Marking duplicates & creating index"
dedupe_metrics="$output_sample_dir/dedupMetrics.txt"
deduped_bam="$output_sample_dir/reads_deduped.bam"
deduped_bai="$output_sample_dir/reads_deduped.bai"

"$java" \
    -d64 -Xmx8g -jar "$picard_jar" MarkDuplicates \
    INPUT="$grouped_sorted_bam" \
    OUTPUT="$deduped_bam" \
    CREATE_INDEX=true \
    VALIDATION_STRINGENCY=SILENT \
    METRICS_FILE="$dedupe_metrics"

rm -f "$grouped_sorted_bam"

#-------------------------------------------------------------------------------
# Refine with GATK
#-------------------------------------------------------------------------------

echo "GATK SplitNCigarReads - Splitting reads into grouped exon segments & hard-clipping sequences that overhang into intronic regions"
split_bam="$output_sample_dir/reads_split.bam"
split_bai="$output_sample_dir/reads_split.bai"

"$java" \
    -d64 -Xmx8g -jar "$gatk_jar" -T SplitNCigarReads \
    -R "$ref_genome_fasta" \
    -I "$deduped_bam" \
    -o "$split_bam" \
    -U ALLOW_N_CIGAR_READS \
    -rf ReassignOneMappingQuality \
    -RMQF 255 \
    -RMQT 60

rm -f "$deduped_bam"
rm -f "$deduped_bai"

echo "GATK RealignerTargetCreator - Preparing to realign around known indels/SNPs"
interval_file="$output_sample_dir/realigner_target.intervals"

"$java" \
    -d64 -Xmx8g -jar "$gatk_jar" -T RealignerTargetCreator \
    -I "$split_bam" \
    -R "$ref_genome_fasta" \
    -o "$interval_file" \
    -known "$known_mills_indel_vcf" \
    -known "$known_1kg_indel_vcf" \
    -nt 2

echo "GATK IndelRealigner - Realigning & reassigning STAR mapping quality 255 to GATK-compatible 60"
realigned_bam="$output_sample_dir/reads_realigned.bam"
realigned_bai="$output_sample_dir/reads_realigned.bai"

mkdir -p "$java_tmp_dir"

"$java" \
    -d64 -Xmx8g -Djava.io.tmpdir="$java_tmp_dir" -jar "$gatk_jar" -T IndelRealigner \
    -I "$split_bam" \
    -R "$ref_genome_fasta" \
    -targetIntervals "$interval_file" \
    -o "$realigned_bam" \
    -known "$known_mills_indel_vcf" \
    -known "$known_1kg_indel_vcf" \
    --consensusDeterminationModel KNOWNS_ONLY \
    -LOD 0.4

rm -f "$interval_file"
rm -f "$split_bam"
rm -f "$split_bai"

echo "GATK BaseRecalibrator - Recalibrating base scores & generating recalibration report"
recalibration_report="$output_sample_dir/recalibration_report.grp"

"$java" \
    -d64 -Xmx8g -jar "$gatk_jar" -T BaseRecalibrator \
    -R "$ref_genome_fasta" \
    -I "$realigned_bam" \
    -knownSites "$known_mills_indel_vcf" \
    -knownSites "$known_1kg_indel_vcf" \
    -knownSites "$known_dbsnp_vcf" \
    -o "$recalibration_report" \
    -nct 6

echo "GATK BaseRecalibrator - Generating post-recalibration report"
post_recalibration_report="$output_sample_dir/post_recalibration_report.grp"

"$java" \
    -d64 -Xmx8g -jar "$gatk_jar" -T BaseRecalibrator \
    -R "$ref_genome_fasta" \
    -I "$realigned_bam" \
    -knownSites "$known_mills_indel_vcf" \
    -knownSites "$known_1kg_indel_vcf" \
    -knownSites "$known_dbsnp_vcf" \
    -BQSR "$recalibration_report" \
    -o "$post_recalibration_report" \
    -nct 6

echo "GATK AnalyzeCovariates - Generating comparison of base score accuracy before & after recalibration"
recalibration_plots="$output_sample_dir/recalibration_plots.pdf"

# Try to load R so we can generate recalibration plots
module load R/3.2.3 \
    || true  # Don't abort if this non-critical step fails

"$java" \
    -d64 -Xmx8g -jar "$gatk_jar" -T AnalyzeCovariates \
    -R "$ref_genome_fasta" \
    -before "$recalibration_report" \
    -after "$post_recalibration_report" \
    -plots "$recalibration_plots" \
    || true  # Don't abort if this non-critical step fails

echo "GATK PrintReads - Writing recalibrated scores to BAM"
recalibrated_bam="$output_sample_dir/$sample_id.refined.bam"

"$java" \
   -d64 -Xmx8g -jar "$gatk_jar" -T PrintReads \
   -R "$ref_genome_fasta" \
   -I "$realigned_bam" \
   -BQSR "$recalibration_report" \
   -o "$recalibrated_bam" \
   -nct 6

rm -f "$realigned_bam"
rm -f "$realigned_bai"
rm -f "$recalibration_report"
rm -f "$post_recalibration_report"
