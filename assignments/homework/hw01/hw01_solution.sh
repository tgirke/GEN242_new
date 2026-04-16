#!/bin/bash -l

######################################################
## HW02: Linux Basics Using Bioinformatics Examples ##
######################################################
## Author: First Last Name
## Last update: 10-Apr-2026

## Download E. coli (Halobacterium) proteome and inspect it
wget https://ftp.ncbi.nlm.nih.gov/genomes/genbank/bacteria/Escherichia_coli/reference/GCA_000008865.2_ASM886v2/GCA_000008865.2_ASM886v2_protein.faa.gz 
gunzip GCA_000008865.2_ASM886v2_protein.faa.gz
mv GCA_000008865.2_ASM886v2_protein.faa ecoli.faa

# less ecoli.faa # press q to quit

## How many protein sequences are stored in the downloaded file?
grep '>' ecoli.faa | wc
grep '^>' ecoli.faa --count
# Answer: 5,153 protein sequences

## How many proteins contain the pattern "WxHxxH" or "WxHxxHH"?
egrep 'W.H..H{1,2}' ecoli.faa --count
# Answer: 15 matches

## Use less to find IDs for pattern matches or use awk
awk --posix -v RS='>' '/W.H..(H){1,2}/ { print ">" $0;}' ecoli.faa | less
awk --posix -v RS='>' '/W.H..(H){1,2}/ { print ">" $0;}' ecoli.faa | grep '^>' | cut -c 2- | cut -f 1 -d\ > myIDs

## Create a BLASTable database with formatdb
module load ncbi-blast
makeblastdb -in ecoli.faa -out ecoli.faa -dbtype prot -hash_index -parse_seqids

## Query BLASTable database by IDs stored in a file (e.g. myIDs)
blastdbcmd -db ecoli.faa -dbtype prot -entry_batch myIDs -get_dups -out myseq.fasta

## Run BLAST search for sequences stored in myseq.fasta
blastp -query myseq.fasta -db ecoli.faa -outfmt 0 -evalue 1e-6 -out blastp.out
blastp -query myseq.fasta -db ecoli.faa -outfmt 6 -evalue 1e-6 -out myresult.txt
# Answer created file with -outfmt 6 format. 

## Submission of HW02 to GitHub
# As instructed in the assignment, upload the result file generated with '-outfmt 6' 
# option (here myresult.txt) to your homework repos on GitHub under Homework/HW02. The 
# following solution assumes that this is done on the HPCC where you have cloned your
# homework repos. The part between '<...>' needs to replaced by the corresponding
# path where your repos is located on the HPCC.
cp myresult.txt ~/<location_of_github_repos_on_HPCC>/Homework/HW02/HW2.txt
cd ~/<location_of_github_repos_on_HPCC>/Homework/HW02/ 
git pull # optional, just in case there were changes in your repos online
git add HW2.txt # adds new file to repos 
git commit -am "HW02 submission" # commit new changes to repos
git push # upload changes including your HW02 to GitHub, done!

## Return system time and host name
# this is useful to record on which system you have done your work
# and at what time.

date 
hostname 

# Answer: Apr 11 16:25:58 PDT 2026
# Answer: skylark or some other host name of a node on HPCC

