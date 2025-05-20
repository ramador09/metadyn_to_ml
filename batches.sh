#!/bin/bash
# Parent script: Generate and submit individual batch submission scripts.
# Usage: ./submit_batches.sh [BATCH_SIZE]
#   If no BATCH_SIZE is provided, it defaults to 25.

#---------------------------
# Global parameter: set the number of folders per batch.
BATCH_SIZE=${1:-25}   # User-specified batch size or default 25.
echo "Using batch size: $BATCH_SIZE"
#---------------------------

# Detect folders in the current directory matching a 4-digit pattern.
folders=( $(ls -d [0-9][0-9][0-9][0-9] 2>/dev/null | sort) )
TOTAL=${#folders[@]}
if [ "$TOTAL" -eq 0 ]; then
    echo "No folders matching the pattern [0-9][0-9][0-9][0-9] were found."
    exit 1
fi

# Calculate the number of batches (ceiling division).
NUM_BATCHES=$(( (TOTAL + BATCH_SIZE - 1) / BATCH_SIZE ))
echo "Found $TOTAL folders. Creating $NUM_BATCHES batch submission scripts."

# Loop over each batch and generate a submission script.
for (( batch=0; batch<NUM_BATCHES; batch++ )); do
    batch_str=$(printf "%02d" $batch)
    script_name="submit_${batch_str}.sh"

    cat > "$script_name" << 'EOF'
#!/bin/bash
#SBATCH --partition=standard-g
#SBATCH --job-name=int_batch
#SBATCH --account=project_465001325
#SBATCH --time=05:59:00
#SBATCH --nodes=12
#SBATCH --exclusive
#SBATCH --gres=gpu:mi250:8
#SBATCH --ntasks-per-node=8
#SBATCH --mem=400G
#SBATCH --hint=nomultithread
#SBATCH --output=submit_%j.out

# Global parameters (placeholders to be replaced by the parent script)
BATCH_SIZE=__BATCH_SIZE__
BATCH_ID=__BATCH_ID__

# Compute a zero-padded version of BATCH_ID for file naming.
BATCH_ID_PADDED=$(printf "%02d" "$BATCH_ID")

# Get the list of folders matching the four-digit pattern.
folders=( $(ls -d [0-9][0-9][0-9][0-9] 2>/dev/null | sort) )
TOTAL=${#folders[@]}

# Calculate start and end indices for this batch.
START=$(( BATCH_ID * BATCH_SIZE ))
END=$(( START + BATCH_SIZE - 1 ))
if [ $END -ge $TOTAL ]; then
    END=$(( TOTAL - 1 ))
fi

echo "Batch ${BATCH_ID_PADDED}: processing folders from index $START to $END (of $TOTAL)."

# Load modules and environment variables as needed.
export MPICH_VERSION_DISPLAY=1
export GTL_VERSION_DISPLAY=1
export OMP_PLACES=cores
export OMP_PROC_BIND=close
export OMP_NUM_THREADS=7
ulimit -s 256000
export OMP_STACKSIZE=256M

export MPICH_OFI_NIC_POLICY=GPU
export MPICH_GPU_SUPPORT_ENABLED=1
export MPICH_GPU_ALLREDUCE_USE_KERNEL=1
export MPICH_GPU_ALLREDUCE_BLK_SIZE=16777216

export COSMA_GPU_MAX_TILE_M=10000
export COSMA_GPU_MAX_TILE_N=10000
export COSMA_GPU_MAX_TILE_K=10000

export DBCSR_MM_DENSE=1
export COSMA_CPU_MEMORY_ALIGNMENT=256

export EBU_USER_PREFIX=$HOME/EasyBuild
module load LUMI/23.09
module load partition/G
module load CP2K/2024.1-cpeGNU-23.09-GPU
module load rocm/5.6.1

EXE=/scratch/project_465000480/amadorra/cp2k/exe/local/cp2k.psmp
INP=sp

CPU_BIND="mask_cpu:fe,fe00"
CPU_BIND="${CPU_BIND},fe0000,fe000000"
CPU_BIND="${CPU_BIND},fe00000000,fe0000000000"
CPU_BIND="${CPU_BIND},fe000000000000,fe00000000000000"

SELECT_GPU=/scratch/project_465000480/brovelli/single_points/select_gpu.sh

# Process each folder in the current batch concurrently.
for (( i=START; i<=END; i++ )); do
    folder=${folders[i]}
    echo "Processing folder: $folder"
    (
       cd "$folder" || { echo "Failed to cd into $folder"; exit 1; }
       srun -u --cpu-bind=${CPU_BIND} ${SELECT_GPU} ${EXE} -i ${INP}.inp -o ${INP}.out && \
           echo "$i $folder" > ../tmp_resume_${BATCH_ID_PADDED}_${i}
    ) &
done
wait

# Aggregate the temporary resume files in order to create the final resume file.
rm -f ../resume_${BATCH_ID_PADDED}
for (( i=START; i<=END; i++ )); do
    if [ -f ../tmp_resume_${BATCH_ID_PADDED}_${i} ]; then
        # Extract the folder name (the second field) and append it.
        cut -d' ' -f2- ../tmp_resume_${BATCH_ID_PADDED}_${i} >> ../resume_${BATCH_ID_PADDED}
        rm ../tmp_resume_${BATCH_ID_PADDED}_${i}
    fi
done
EOF

    # Replace the placeholders with actual values.
    sed -i "s/__BATCH_SIZE__/$BATCH_SIZE/g" "$script_name"
    sed -i "s/__BATCH_ID__/$batch_str/g" "$script_name"

    # Make the generated script executable.
    chmod +x "$script_name"

    # Submit the batch submission script.
    sbatch "$script_name"
done
