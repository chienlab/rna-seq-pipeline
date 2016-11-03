#!/bin/bash

input_vcf=$1
output_file=$2
quality_filter=$3

awk_script='{
    OFS = "\t"
    split($10, genotype_fields, ":")
    split(genotype_fields[2], allele_depths, ",")

    ref_depth = allele_depths[1]
    alt_depth = allele_depths[2]

    if (ref_depth != 0 || alt_depth != 0) {
        total_depth = (ref_depth + alt_depth)

        depths_field = total_depth","alt_depth
        alt_fraction = (alt_depth / total_depth)

        print $1, $2, depths_field, $4, $5, alt_fraction
    }
}'

grep -v '^#' $input_vcf \
    | awk -v qual=$quality_filter '$6>=qual' \
    | awk "$awk_script" \
    > $output_file
