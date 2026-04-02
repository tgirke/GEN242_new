###################################################
## Exercises for Common Bioinformatics Use Cases ##
###################################################

## Log in to a node with srun
srun --x11 --partition=short --mem=2gb --cpus-per-task 4 --ntasks 1 --time 1:00:00 --pty bash -l

## Download Halobacterium proteome and inspect it
wget https://ftp.ncbi.nlm.nih.gov/genomes/genbank/archaea/Halobacterium_salinarum/all_assembly_versions/GCA_004799605.1_ASM479960v1/GCA_004799605.1_ASM479960v1_protein.faa.gz
gunzip GCA_004799605.1_ASM479960v1_protein.faa.gz
mv GCA_004799605.1_ASM479960v1_protein.faa halobacterium.faa

# less halobacterium.faa # press q to quit

## How many protein sequences are stored in the downloaded file?
grep '>' halobacterium.faa | wc
grep '^>' halobacterium.faa --count

## How many proteins contain the pattern "WxHxxH" or "WxHxxHH"?
egrep 'W.H..H{1,2}' halobacterium.faa --count

## Use less to find IDs for pattern matches or use awk
awk --posix -v RS='>' '/W.H..(H){1,2}/ { print ">" $0;}' halobacterium.faa | less
awk --posix -v RS='>' '/W.H..(H){1,2}/ { print ">" $0;}' halobacterium.faa | grep '^>' | cut -c 2- | cut -f 1 -d\ > myIDs

## Create a BLASTable database with formatdb
module load ncbi-blast/2.2.31+ 
makeblastdb -in halobacterium.faa -out halobacterium.faa -dbtype prot -hash_index -parse_seqids

## Query BLASTable database by IDs stored in a file (e.g. myIDs)
blastdbcmd -db halobacterium.faa -dbtype prot -entry_batch myIDs -get_dups -out myseq.fasta

## Run BLAST search for sequences stored in myseq.fasta
blastp -query myseq.fasta -db halobacterium.faa -outfmt 0 -evalue 1e-6 -out blastp.out
blastp -query myseq.fasta -db halobacterium.faa -outfmt 6 -evalue 1e-6 -out blastp.tab

## Return system time and host name
date
hostname

## More exercises in Linux Manual 
## https://hpcc.ucr.edu/manuals_linux-basics_shell.html

## Submit job to queuing system of cluster

## (i) Create submission script as outlined here: https://bit.ly/2O9qMJm
    
## (ii) Submit script to cluster as follows
    ## sbatch script_name.sh


