#!/usr/bin/perl
use lib qw(../);

use strict;
use warnings;
use diagnostics;
use Getopt::Long;

################################################################################
################################################################################
# $Revision: $
# Authors: Robert Piskol ( piskol@stanford.edu ), Gokul Ramaswami ( gokulr@stanford.edu )
# Last modification $Author: piskol $
# script used to filter out variants called due to intronic alignment of RNA-SEQ reads
my ($INPUT_FILE, $OUTPUT_FILE, $GENE_FILE);
my $SPLICE_DIST = 4;

parse_command_line();

sub parse_command_line {
	my $help;
	
	usage() if (scalar @ARGV == 0);

	&GetOptions(
		"infile=s" => \$INPUT_FILE,
		"outfile=s" => \$OUTPUT_FILE,
		"genefile=s" => \$GENE_FILE,
		"splicedist=s" => \$SPLICE_DIST,
		"help" => \$help
		);
	
	usage() if ($help);
	   
	if (!$INPUT_FILE or !$OUTPUT_FILE or !$GENE_FILE) {
		usage();
	}
}

# Open all files up-front, because we don't want to waste time loading the gene
# hash into memory, only to fail due to an IO error
open(my $VARIANT_INPUT, $INPUT_FILE) or die "error opening input variant list: $!\n";  # Open file of candidate variants
open(my $GENE_INPUT, $GENE_FILE) or die "error opening gene annotation file: $!\n";
open(my $OUTPUT, ">", $OUTPUT_FILE) or die "error opening output file: $!\n";
open(my $FAILED_OUTPUT, ">", $OUTPUT_FILE . '_failed') or die "error opening output file: $!\n";

my %gene_hash;  # Key: Chromosome identifier, Value: Gene annotation array

print STDERR "reading gene annotation file...\n";
while (<$GENE_INPUT>) {
	chomp;
	my $gene_line = $_;
	my @gene_fields = split;
	my $gene_chrom = $gene_fields[2];
	push(@{$gene_hash{$gene_chrom}}, $gene_line);  # Add a gene to the appropriate chromosome's gene array
}
close $GENE_INPUT;

print STDERR "removing variants within $SPLICE_DIST bp of splicing junctions...\n";
while (<$VARIANT_INPUT>) {
	chomp;
	my $variant_line = $_;
	my @variant_fields = split(/\t/);
	my $variant_chrom = $variant_fields[0];
	my $variant_pos = int($variant_fields[1]);
	my $variant_chrom_genes_ref = $gene_hash{$variant_chrom};
	
	if (not defined $variant_chrom_genes_ref) {
		print STDERR "Variant chromosome $variant_chrom doesn't match any gene annotation chromosome!\n";
		next;
	}
	
	my @variant_chrom_genes = @{ $variant_chrom_genes_ref };
	
	# If variant is within any exon and not within any intronic near splice junction, print it out
	if (!is_variant_in_intronic_splice_region($variant_pos, @variant_chrom_genes)) {
		print $OUTPUT "$variant_line\n";
	} else {
		print $FAILED_OUTPUT "$variant_line\n";
	}
}
close $VARIANT_INPUT;
close $OUTPUT;
close $FAILED_OUTPUT;

#================================================================

sub is_variant_in_intronic_splice_region {
	my ($variant_pos, @variant_chrom_genes) = @_;
	
	# For each variant, loop through its chromosome's gene annotations
	# & check if variant is in intronic region near a splice junction
	for my $gene_line (@variant_chrom_genes) {
		my @gene_fields = split(/\t/, $gene_line);
		my $gene_start = int($gene_fields[4]);
		my $gene_end = int($gene_fields[5]);
		
		if ($variant_pos < $gene_start) {
			last;  # We already know this variant precedes all remaining genes
		}
		
		my $is_in_gene = ($gene_start <= $variant_pos and $variant_pos <= $gene_end);
		if (!$is_in_gene) {
			next;
		}
		
		my $exon_count = int($gene_fields[8]);
		my @exon_starts = split(/,/, $gene_fields[9]);
		my @exon_ends = split(/,/, $gene_fields[10]);
		
		for (my $i = 0; $i < $exon_count; ++$i) {
			my $exon_start = int($exon_starts[$i]);
			my $start_intronic_offset = $exon_start - $SPLICE_DIST;
			
			if ($variant_pos < $start_intronic_offset) {
				last;  # We already know this variant precedes all remaining exons in this gene
			}
			
			my $exon_end = int($exon_ends[$i]);
			my $end_intronic_offset = $exon_end + $SPLICE_DIST;
			
			my $is_in_start_intronic_region = ($start_intronic_offset < $variant_pos and $variant_pos <= $exon_start);
			my $is_in_end_intronic_region = ($exon_end < $variant_pos and $variant_pos <= $end_intronic_offset);
			
			# Check if variant is within SPLICE_DIST bp to intronic side of 
			# a splice junction, either at start or end of this exon
			if ($is_in_start_intronic_region or $is_in_end_intronic_region) {
				return 1;
			}
		}
	}
	
	return 0;
}

sub usage() {
print<<EOF;

Filter for intronic variants close to splicing junctions, by Robert Piskol (piskol\@stanford.edu) 
							   & Gokul Ramaswami (gokulr\@stanford.edu) 07/25/2013

This program takes a variant file and a gene annotation file in UCSC text format
and filters all variants that are in intronic regions in a distance closer than a user selected value.

usage: $0 -infile FILE -outfile FILE -GENE_FILE FILE [-splicedist N] 


Arguments:
-infile FILE	- File containing a list of variants to be filtered
-outfile FILE	- Output file for filtered variants
-genefile FILE	- File in UCSC txt format (sorted by chomosome and position - i.e. 'sort -k3,3 -5,5n')
-splicedist N	- Maximum filter distance from splicing junction for variants (default: 4)
-help		- Show this help screen


EOF

exit 1;
}