#!/bin/bash
#PBS -l nodes=1:ppn=12,mem=32g,walltime=36:00:00
#PBS -M SeijiSuenaga@gmail.com
#PBS -m abe

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  Generates a filtered set of variant calls using GATK HaplotypeCaller, plus
  several filters from the SNPiR workflow.
  This step is done once for each sample and can be run as a qsub job array.
TOOLS:
  Java
  Perl
  GATK
  SNPiR
  BEDtools (subtract and intersect)
INPUT:
  Config file at <current directory>/CONFIG.sh
  BAM file(s) at <dataset_dir>/<sample dir>/refined-mapping/<sample>.refined.bam
  Reference genome at <ref_genome_fasta>
  Known variant list at <known_dbsnp_vcf>
OUTPUT:
  VCF files in <output_dir>/<sample dir>/haplotypecaller"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

echo "Reference genome FASTA:  $ref_genome_fasta"
echo "Known SNPs:  $known_dbsnp_vcf"

sample_dir=$(echo "$sample_dir_list" | head -$PBS_ARRAYID | tail -1)
sample_id=$(echo "$sample_list" | head -$PBS_ARRAYID | tail -1)

input_bam="$dataset_dir/$sample_dir/refined-mapping/$sample_id.refined.bam"
echo "Input BAM:  $input_bam"

output_haplotypecaller_dir="$output_dir/$sample_dir/haplotypecaller"
echo "Output Directory:  $output_haplotypecaller_dir"
mkdir -p "$output_haplotypecaller_dir"

# ------------------------------------------------------------------------------
# Call raw variants
# ------------------------------------------------------------------------------

raw_vcf="$output_haplotypecaller_dir/$sample_id.hc.raw.vcf"

echo "GATK HaplotypeCaller - Calling raw variants"
"$java" -Xmx16g -jar "$gatk_jar" -T HaplotypeCaller \
    -R "$ref_genome_fasta" \
    -I "$input_bam" \
    -dontUseSoftClippedBases \
    -stand_call_conf 20.0 \
    -stand_emit_conf 20.0 \
    --dbsnp "$known_dbsnp_vcf" \
    -o "$raw_vcf" \
    -nct 12

# ------------------------------------------------------------------------------
# Filter raw variants according to GATK best practices
# ------------------------------------------------------------------------------

echo "GATK VariantFiltration - Filtering clusters of 3+ SNPs within a 35bp window & filtering FS > 30, QD < 2"
filtered_phase_1="$output_haplotypecaller_dir/1_filtered_gatk.vcf"

"$java" -Xmx8g -jar "$gatk_jar" -T VariantFiltration \
    -R "$ref_genome_fasta" \
    -V "$raw_vcf" \
    -window 35 \
    -cluster 3 \
    -filterName FS -filter "FS > 30.0" \
    -filterName QD -filter "QD < 2.0" \
    -o "$filtered_phase_1"

# ------------------------------------------------------------------------------
# Additionally, filter variants using the last 4 steps of the SNPiR workflow
# ------------------------------------------------------------------------------

echo "Preparing for SNPiR by removing variants that failed previous filter conditions"
filtered_phase_2="$output_haplotypecaller_dir/2_rmfailed_for_snpir.vcf"
perl -lane 'print $_ if $_ ~~ /^#/ or $F[6] eq "PASS"' "$filtered_phase_1" \
    > "$filtered_phase_2"

cd "$snpir_dir"

echo "SNPiR - Converting VCF to custom SNPiR format"
filtered_phase_3="$output_haplotypecaller_dir/3_snpir_format.txt"
"$revised_snpir_dir/revised_convertVCF.sh" \
    "$filtered_phase_2" \
    "$filtered_phase_3"

echo "SNPiR - Filtering intronic candidates within 4 bp of splicing junctions"
filtered_phase_4="$output_haplotypecaller_dir/4_filtered_sj.txt"

perl "$revised_snpir_dir/revised_filter_intron_near_splicejuncts.pl" \
    -infile "$filtered_phase_3" \
    -outfile "$filtered_phase_4" \
    -genefile "$revised_snpir_dir/gene_annotation_table"

# In ACF's installation of SNPiR, this file is space-separated instead of tab-separated,
# so the above command uses a fixed one in $revised_snpir_dir instead
#-genefile "$snpir_dir/genome_ref/gene_annotation_table"

echo "SNPiR - Filtering candidates in homopolymer runs"
filtered_phase_5="$output_haplotypecaller_dir/5_filtered_homopolymer.txt"

perl "$snpir_dir/filter_homopolymer_nucleotides.pl" \
    -infile "$filtered_phase_4" \
    -outfile "$filtered_phase_5" \
    -refgenome "$ref_genome_fasta"

echo "SNPiR - Using PBLAT to ensure unique mapping"
filtered_phase_6="$output_haplotypecaller_dir/6_filtered_pblat.txt"

perl "$revised_snpir_dir/pblat_candidates_ln.pl" \
    -infile "$filtered_phase_5" \
    -outfile "$filtered_phase_6" \
    -bamfile "$input_bam" \
    -refgenome "$ref_genome_fasta" \
    -pblatpath "$pblat" \
    -threads 12

echo "SNPiR - Using BEDtools to separate out candidates that are known RNA editing sites"
filtered_phase_7="$output_haplotypecaller_dir/7_filtered_knownedits.bed"

awk '{OFS="\t";$2=$2-1"\t"$2;print $0}' "$filtered_phase_6" \
    | "$bedtools" subtract \
        -a stdin \
        -b "$snpir_dir/genome_ref/Human_AG_all_hg19.bed" \
    > "$filtered_phase_7"

echo "Using SNPiR output & BEDtools intersect to extract final variants from raw VCF"
final_vcf="$output_haplotypecaller_dir/$sample_id.hc.snpir.filtered.vcf"

"$bedtools" intersect \
    -a "$raw_vcf" \
    -b "$filtered_phase_7" \
    -wa \
    -header \
    > "$final_vcf"
