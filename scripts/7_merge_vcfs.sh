#!/bin/bash

set -e  # Enable flag to exit when any command fails

# Show help if any arguments are given
if [[ $# -gt 0 ]]; then
    echo \
"DESCRIPTION:
  Copies each workflow's sample VCFs to a centralized directory, then uses the
  patient-sample mapping in the dataset XML file to merge all samples per
  patient & workflow.
  This step is done once for an entire dataset of samples.
TOOLS:
  BCFtools
INPUT:
  Config file at <current directory>/CONFIG.sh
  VCF files at
    <dataset_dir>/<sample dir>/haplotypecaller/<sample>.hc.snpir.filtered.vcf
    <dataset_dir>/<sample dir>/unifiedgenotyper/snpir/<sample>.ug.snpir.filtered.vcf
    <dataset_dir>/<sample dir>/unifiedgenotyper/rvboost/<sample>.ug.rvboost.filtered.vcf
OUTPUT:
  VCF files in
    <sample_vcf_dir>/gatk   <sample_vcf_dir>/snpir   <sample_vcf_dir>/rvboost
    <patient_vcf_dir>/gatk  <patient_vcf_dir>/snpir  <patient_vcf_dir>/rvboost
    <workflow_vcf_dir>"

    # Exit with error code if unrecognized arg is given
    if [[ $1 == "--help" ]] || [[ $1 == "-h" ]]; then exit 0; else exit 1; fi
fi

echo "Loading config variables"
if [ ! "$PBS_O_WORKDIR" ]; then     # If not run via qsub,
    PBS_O_WORKDIR="$(dirname $0)"   # get this script's parent dir
fi
source "$PBS_O_WORKDIR/CONFIG.sh"

echo "Sample VCF Output Directory:  $sample_vcf_dir"
echo "Patient VCF Output Directory:  $patient_vcf_dir"
echo "Workflow VCF Output Directory:  $workflow_vcf_dir"

workflows_lowercase="gatk snpir rvboost"
for workflow_name in $workflows_lowercase; do
    mkdir -p \
        "$sample_vcf_dir/$workflow_name" \
        "$patient_vcf_dir/$workflow_name"
done
mkdir -p "$workflow_vcf_dir"

# ------------------------------------------------------------------------------
# Copy sample VCFs
# ------------------------------------------------------------------------------

gatk_sample_vcf_dir="$sample_vcf_dir/gatk"
snpir_sample_vcf_dir="$sample_vcf_dir/snpir"
rvboost_sample_vcf_dir="$sample_vcf_dir/rvboost"

echo "Copying each workflow's sample VCFs"
for i in $(seq 1 $sample_count); do
    sample_dir=$(echo "$sample_dir_list" | head -$i | tail -1)
    sample_id=$(echo "$sample_list" | head -$i | tail -1)

    gatk_path="$dataset_dir/$sample_dir/haplotypecaller/$sample_id.hc.snpir.filtered.vcf"
    snpir_path="$dataset_dir/$sample_dir/unifiedgenotyper/snpir/$sample_id.ug.snpir.filtered.vcf"
    rvboost_path="$dataset_dir/$sample_dir/unifiedgenotyper/rvboost/$sample_id.ug.rvboost.filtered.vcf"

    cp "$gatk_path" "$gatk_sample_vcf_dir/$sample_id.vcf"
    cp "$snpir_path" "$snpir_sample_vcf_dir/$sample_id.vcf"
    cp "$rvboost_path" "$rvboost_sample_vcf_dir/$sample_id.vcf"
done

# ------------------------------------------------------------------------------
# Generic VCF merging function
# ------------------------------------------------------------------------------

function merge_vcfs {
    local vcf_paths=$1
    local vcf_group=$2
    local merge_output_dir=$3
    local merge_output_file=$4

    echo "-----------------------------------------------"
    echo "Processing VCFs for $vcf_group"

    if [ ! "$vcf_paths" ]; then
        echo "Error - No VCFs found for $vcf_group"
        exit 1
    fi
    if [ $(echo "$vcf_paths" | wc -w) -eq 1 ]; then
        echo "Error - Only 1 VCF found for $vcf_group merge"
        exit 1
    fi

    #-----------------------------------------------------------------------
    echo "  Compressing & indexing VCFs:"
    gz_list_file="$merge_output_dir/gz_list.tmp"
    rm -f "$gz_list_file"

    for vcf_path in $vcf_paths; do
        echo "    $vcf_path"

        vcf_name=$(basename "$vcf_path")
        gz_path="$merge_output_dir/$vcf_name.gz"
        echo "$gz_path" >> "$gz_list_file"

        "$bcftools" convert -O z "$vcf_path" \
            > "$gz_path"

        "$bcftools" index --csi "$gz_path"
    done

    gz_file_count=$(wc -l < "$gz_list_file")
    echo "  VCF.GZ file count: $gz_file_count"

    #-----------------------------------------------------------------------
    echo "  Merging compressed & indexed VCFs to file:"
    echo "    $merge_output_dir/$merge_output_file"
    "$bcftools" merge \
        --file-list "$gz_list_file" \
        -o "$merge_output_dir/$merge_output_file"

    #-----------------------------------------------------------------------
    echo "  Removing temporary files"
    rm -f "$gz_list_file" \
          $merge_output_dir/*.vcf.gz \
          $merge_output_dir/*.vcf.gz.csi
}

# ------------------------------------------------------------------------------
# Loop through workflows & patients, pass them to generic merge function
# ------------------------------------------------------------------------------

patient_ids=$("$query_dataset_script" patients "$dataset_xml")
if [ ! "$patient_ids" ]; then
    echo "Error - No patients found in the dataset XML file"
    exit 1
fi

echo "Starting to merge samples by patient & patients by workflow"
mkdir -p "$workflow_vcf_dir"
workflow_names="GATK SNPiR RVboost"

for workflow_name in $workflow_names; do
    workflow_lowercase=$(echo $workflow_name | tr '[A-Z]' '[a-z]')
    sample_vcf_workflow_dir="$sample_vcf_dir/$workflow_lowercase"
    patient_vcf_workflow_dir="$patient_vcf_dir/$workflow_lowercase"

    sample_vcfs=$(ls -1 $sample_vcf_workflow_dir/*.vcf)

    if [ ! "$sample_vcfs" ]; then
        echo "Error - No $workflow_name sample VCFs found"
        exit 1
    fi

    patient_vcfs_for_workflow=""  # Clear previous workflow's list of VCFs

    for patient_id in $patient_ids; do
        sample_ids_for_patient=$("$query_dataset_script" samples "$patient_id" "$dataset_xml")

        sample_vcfs_for_patient=""  # Clear previous patient's list of VCFs

        for sample_id in $sample_ids_for_patient; do
            sample_vcfs_for_patient+=" $sample_vcf_workflow_dir/$sample_id.vcf"
        done

        patient_vcf="$patient_id.merged.vcf"

        merge_vcfs \
            "$sample_vcfs_for_patient" \
            "$workflow_name Patient $patient_id" \
            "$patient_vcf_dir/$workflow_lowercase" \
            "$patient_vcf"

        patient_vcfs_for_workflow+=" $patient_vcf_workflow_dir/$patient_vcf"
    done

    merge_vcfs \
        "$patient_vcfs_for_workflow" \
        "$workflow_name Workflow" \
        "$workflow_vcf_dir" \
        "$workflow_lowercase.merged.vcf"
done
