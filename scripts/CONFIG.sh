#-------------------------------------------------------------------------------
# INPUT DATASET
#-------------------------------------------------------------------------------

# For all steps
dataset_dir="/genomics/jchien/ssuenaga/151125_SN316_0506_AC84APACXX"
dataset_xml="${dataset_dir}/dataset.xml"

# For STAR mapping
r1_fastq_file_suffix=".R1.fastq.gz"
r2_fastq_file_suffix=".R2.fastq.gz"
use_compressed_fastq=1
fastq_read_length=100

#-------------------------------------------------------------------------------
# OUTPUT
#-------------------------------------------------------------------------------

# For all steps
output_dir="${dataset_dir}"

# For STAR mapping
star_index_dir="/scratch/jchien/ssuenaga/ucsc-hg19-100bp-STAR-index"

# For VCF merging
sample_vcf_dir="${output_dir}/vcf-per-sample"
patient_vcf_dir="${output_dir}/vcf-per-patient"
workflow_vcf_dir="${output_dir}/vcf-per-workflow"

#-------------------------------------------------------------------------------
# REFERENCE FILES
#-------------------------------------------------------------------------------

ref_dir="/genomics/jchien/refs/hg19"

# For STAR mapping, mapping refinement, variant calling, & SNPiR variant filtering
ref_genome_fasta="${ref_dir}/ucsc.hg19.fasta"
ref_genome_annotations="${ref_dir}/ucsc.hg19.annotations.gtf"

# For mapping refinement & variant calling
known_mills_indel_vcf="${ref_dir}/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf"
known_1kg_indel_vcf="${ref_dir}/1000G_phase1.indels.hg19.sites.vcf"
known_snp_vcf="${ref_dir}/dbsnp_138.hg19.vcf"

#-------------------------------------------------------------------------------
# TOOLS
#-------------------------------------------------------------------------------

tools_dir="/tools/cluster/6.2"
jchien_bin_dir="/genomics/jchien/analyse_bin"

# If starting with BAM files instead of FASTQ files
biobambam2_bamtofastq="${tools_dir}/biobambam2/2.0.16/bin/bamtofastq"

# For STAR mapping
star="${tools_dir}/star/2.4.2a/STAR"

# For mapping refinement (GATK best practices)
picard_jar="${tools_dir}/picard-tools/1.140/picard.jar"
java_tmp_dir="/scratch/jchien/ssuenaga/javaTmp"

# For mapping refinement, variant calling, & GATK variant filtering
gatk_jar="${tools_dir}/gatk/3.4-46/GenomeAnalysisTK.jar"

# For RVboost & SNPiR variant filtering
rvboost_dir="${tools_dir}/rvboost/0.1"
snpir_dir="${tools_dir}/snpir/20140512"
revised_snpir_dir="/genomics/jchien/scripts/rna-seq-pipeline/snpir"
pblat="${tools_dir}/pblat/1.6/pblat"

# For SNPiR variant filtering & finding concordance between VCFs
bedtools="${tools_dir}/bedtools/2.25.0/bin/bedtools"

# For merging VCF files
bcftools="${jchien_bin_dir}/bcftools-1.3.1/bcftools"

# For annotating VCF files
table_annovar="${jchien_bin_dir}/annovar/table_annovar.pl"



#-------------------------------------------------------------------------------
# END OF CONFIG - DON'T EDIT BELOW THIS LINE (derived variables & validation)
#-------------------------------------------------------------------------------

function exit_because_path {
    local path="$1"
    local reason="$2"
    echo "ERROR - $reason:"
    echo "$path"
    exit 1
}

function exit_if_missing_dir {
    local path="$1"
    local name="$2"
    if [ ! -d "$path" ]; then
        exit_because_path "$path" "$name doesn't exist"
    fi
}

function exit_if_missing_file {
    local path="$1"
    local name="$2"
    if [ ! -e "$path" ]; then
        exit_because_path "$path" "$name doesn't exist"
    fi
}

function exit_if_empty {
    local path="$1"
    local name="$2"
    local line_count=$(wc -l < "$path")
    if [ $line_count -eq 0 ]; then
        exit_because_path "$path" "$name is empty"
    fi
}

exit_if_missing_dir "$dataset_dir" "Dataset directory"
exit_if_missing_file "$dataset_xml" "Dataset XML file"
exit_if_empty "$dataset_xml" "Dataset XML file"

# These variables are used throughout the pipeline
query_dataset_script="$PBS_O_WORKDIR/query_dataset.py"
sample_dir_list=$("$query_dataset_script" sampledirs "$dataset_xml")
sample_list=$("$query_dataset_script" samples "$dataset_xml")

sample_dir_count=$(echo "$sample_dir_list" | wc -l)
sample_count=$(echo "$sample_list" | wc -l)
if [ ! $PBS_ARRAYID ]; then
    PBS_ARRAYID=1
fi
if [ $PBS_ARRAYID -gt $sample_count ]; then
    echo "ERROR - Job array ID ($PBS_ARRAYID) exceeds the number of samples ($sample_count)"
    exit 1
fi
