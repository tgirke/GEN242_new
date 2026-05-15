##########################################
## Solution for HW5 - NGS Analysis Basics
##########################################

library(ShortRead)
library(Biostrings)
library(GenomicRanges)
library(rtracklayer)

## Part A: Demultiplexing with Quality Trimming 
## The trimTails() function trims bases from the 3' end where quality
## drops below the cutoff. The cutoff (Phred score) is converted to the
## corresponding ASCII quality character using rawToChar(as.raw(cutoff+33)).
## k=2 means at least 2 consecutive bases must be below the threshold
## before trimming begins.

demultiplex_trim <- function(x, barcode, nreads, cutoff = 20) {
    f <- FastqStreamer(x, nreads)
    while(length(fq <- yield(f))) {
        for(i in barcode) {
            pattern <- paste("^", i, sep = "")
            fqsub <- fq[grepl(pattern, sread(fq))]
            if(length(fqsub) > 0) {
                ## Trim low-quality 3' tails before writing
                fqsub <- trimTails(fqsub, k = 2,
                                   a = rawToChar(as.raw(cutoff + 33)),
                                   successive = FALSE)
                writeFastq(fqsub, paste(x, i, sep = "_"),
                           mode = "a", compress = FALSE)
            }
        }
    }
    close(f)
}

## Usage example — uses ShortRead package test FASTQ files (no download needed)
fastq <- dir(system.file("extdata", package = "ShortRead"),
             pattern = "fastq$", full.names = TRUE)
demultiplex_trim(x = fastq[1], barcode = c("TT", "AA", "GG"),
                 nreads = 50, cutoff = 20)

## Part B: Sequence Parsing from GFF and Genome

dir.create("data", showWarnings = FALSE)

## Download Halobacterium sp. GFF annotation and genome FASTA
download.file(
    "https://ftp.ncbi.nlm.nih.gov/genomes/archive/old_genbank/Bacteria/Halobacterium_sp_uid217/AE004437.gff",
    "data/AE004437.gff"
)
download.file(
    "https://ftp.ncbi.nlm.nih.gov/genomes/archive/old_genbank/Bacteria/Halobacterium_sp_uid217/AE004437.fna",
    "data/AE004437.fna"
)

## Import genome sequence and GFF annotation
chr <- readDNAStringSet("data/AE004437.fna")
gff <- import("data/AE004437.gff")

## ── Task B1: Extract gene sequences and translate to protein ──

## Filter GFF to gene features only
gffgene <- gff[values(gff)[, "type"] == "gene"]

## Extract gene sequences from genome using coordinate ranges
gene <- DNAStringSet(Views(chr[[1]], IRanges(start(gffgene), end(gffgene))))
names(gene) <- values(gffgene)[, "locus_tag"]

## Translate + strand genes directly
pos <- values(gffgene[strand(gffgene) == "+"])[, "locus_tag"]
p1  <- translate(gene[names(gene) %in% pos])
names(p1) <- names(gene[names(gene) %in% pos])

## Translate - strand genes (reverse complement first)
neg <- values(gffgene[strand(gffgene) == "-"])[, "locus_tag"]
p2  <- translate(reverseComplement(gene[names(gene) %in% neg]))
names(p2) <- names(gene[names(gene) %in% neg])

## Write combined protein sequences to FASTA file
writeXStringSet(c(p1, p2), "data/mypep.fasta")

## Task B2: Reduce overlapping gene ranges 

## Collapse overlapping ranges to non-redundant single ranges
## ignore.strand=TRUE is appropriate here since we are looking at
## genomic coverage regardless of strand (useful for bacterial genomes
## with dense, overlapping genes on both strands)
gffgene_reduced <- reduce(gffgene, ignore.strand = TRUE)

## Parse sequences for the reduced (non-overlapping) ranges
gene_reduced <- DNAStringSet(Views(chr[[1]],
                    IRanges(start(gffgene_reduced), end(gffgene_reduced))))

## Task B3: Generate intergenic ranges and parse sequences 

## Compute gaps between reduced gene ranges = intergenic regions
intergenic <- gaps(gffgene_reduced)

## Parse intergenic sequences from genome
gene_intergenic <- DNAStringSet(Views(chr[[1]],
                       IRanges(start(intergenic), end(intergenic))))
