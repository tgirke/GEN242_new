#!/bin/bash -l
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1G
#SBATCH --time=00:15:00 # 15 minutes
#SBATCH --mail-user=useremail@address.com
#SBATCH --mail-type=ALL
#SBATCH --job-name="some_test"
#SBATCH --partition="gen242" # Choose alternative partitions from: intel, batch, highmem, gpu, short, ...
#SBATCH --account="gen242" # Same as above

Rscript my_script.R
