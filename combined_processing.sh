#!/bin/bash
# Combined script for processing raw data.
# It runs:
#   1) Typemap generation (from make_typemap_raw.sh)
#   2) Raw active learning processing (from make_raw_activelearning.sh)
#   3) Conversion of raw files into final sets (from raw_to_set.sh)
#
# Usage: ./combined_processing.sh file.xyz [nline_per_set]
#   - file.xyz is the only mandatory argument.
#   - nline_per_set (optional) overrides the default 2000 lines per set.
#
# The script reads the number of atoms from the first line of file.xyz.

#------------------------------------------------------------------------------
# Step 0: Check input and read number of atoms
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 file.xyz [nline_per_set]"
    exit 1
fi

xyz_file="$1"
if [ ! -f "$xyz_file" ]; then
    echo "Error: File '$xyz_file' not found!"
    exit 1
fi

# Read the number of atoms from the first line of the xyz file.
num_atoms=$(head -n 1 "$xyz_file")
echo "Number of atoms (from $xyz_file): $num_atoms"

# Optionally, allow a custom number of lines per set (default: 2000)
nline_per_set=${2:-2000}

#------------------------------------------------------------------------------
# Step 1: Typemap Generation (make_typemap_raw.sh functionality)
echo "Running typemap generation..."
# Extract atomic species (lines 3 to N+2) and generate type files.
species_list=$(awk 'NR > 2 { print $1 }' "$xyz_file" | head -n "$num_atoms")
echo "$species_list" | awk '!seen[$1]++' > type_map.raw
echo "$species_list" | awk 'BEGIN { count = 0 } !($1 in map) { map[$1] = count++ } { print map[$1] }' > type.raw
echo "Files 'type.raw' and 'type_map.raw' have been generated."

#------------------------------------------------------------------------------
# Step 2: Raw Active Learning Processing (make_raw_activelearning.sh functionality)
echo "Running raw active learning processing..."

# Automatically detect the active learning folders (assumed to be named with four digits)
folders_active=( $(ls -d [0-9][0-9][0-9][0-9] 2>/dev/null | sort) )
if [ ${#folders_active[@]} -eq 0 ]; then
    echo "No active learning folders (named 0000, 0001, etc.) found."
    exit 1
fi
# Set N1 as the first folder and N2 as the last folder
N1=${folders_active[0]}
N2=${folders_active[${#folders_active[@]}-1]}
echo "Detected active learning folders from $N1 to $N2."

# Define additional variables used by the active learning script.
OUTPUT=sp.out
name_force=cvt-forces-1_0.xyz   # Name of force file in each folder.
name_xyz=geom.xyz              # Name of xyz file in each folder.
Natm=$num_atoms                # Use the number of atoms read from the .xyz file.

#########################################################
# Process FORCE
#########################################################
echo "Gathering force..."
end=$((Natm + 4))
for i in $(seq -w $N1 $N2); do
    awk -v Natm="$Natm" -v end="$end" 'BEGIN {print Natm; print " " }
         NR>=5 && NR<=end {print $3, $4, $5, $6}' "$i"/"$name_force" > "$i"/force.xyz
done
mkdir -p force
for i in $(seq -w $N1 $N2); do
    cp "$i"/force.xyz force/"$i".xyz
done

cd force
for i in $(ls); do
    awk 'NR > 2 { printf( "%f %f %f ", $2*51.422083418608956, $3*51.422083418608956, $4*51.422083418608956 ); } END { printf( "\n" ); }' "$i" >> ../force.raw
done
cd ..

#########################################################
# Process XYZ
#########################################################
echo "Gathering xyz..."
mkdir -p xyz
for i in $(seq -w $N1 $N2); do
    cp "$i"/"$name_xyz" xyz/"$i".xyz
done

cd xyz
for i in $(ls); do
    awk 'NR > 2 { printf( "%f %f %f ", $2, $3, $4 ); } END { printf( "\n" ); }' "$i" >> ../coord.raw
done
cd ..

#########################################################
# Process ENERGY
#########################################################
echo "Gathering energy..."
for i in $(seq -w $N1 $N2); do 
    grep 'ENERGY| Total FORCE_EVAL' "$i"/"$OUTPUT" | tail -1 >> energy_tempt.dat
done
awk '{printf "%6.12f\n", $9*27.211396641308}' energy_tempt.dat > energy.raw
rm energy_tempt.dat

#########################################################
# Process BOX
#########################################################
echo "Gathering box..."
> box.raw  # Clear any existing box.raw
for i in $(seq -w $N1 $N2); do 
    echo '20.850061 0.0 0.0 0.0 24.07534 0.0 0.0 0.0 55.7796' >> box.raw
done

#------------------------------------------------------------------------------
# Step 3: Convert Raw Files into Final Sets (raw_to_set.sh functionality)
echo "Converting raw data to final sets..."

module load cray-python

rm -fr set.*
echo "Total number of frames in box.raw: $(wc -l < box.raw)"
echo "Number of lines per set: $nline_per_set"

split box.raw    -l $nline_per_set -d -a 3 box.raw
split coord.raw  -l $nline_per_set -d -a 3 coord.raw
test -f energy.raw && split energy.raw -l $nline_per_set -d -a 3 energy.raw
test -f force.raw  && split force.raw  -l $nline_per_set -d -a 3 force.raw
test -f virial.raw && split virial.raw -l $nline_per_set -d -a 3 virial.raw
test -f atom_ener.raw && split atom_ener.raw -l $nline_per_set -d -a 3 atom_ener.raw
test -f fparam.raw && split fparam.raw -l $nline_per_set -d -a 3 fparam.raw

nset=$(ls | grep 'box.raw[0-9]' | wc -l)
echo "Will create $nset sets."

for ii in $(seq 0 $((nset-1))); do
  echo "Making set $ii ..."
  pi=$(printf "%03d" $ii)
  mkdir set.$pi
  mv box.raw$pi         set.$pi/box.raw
  mv coord.raw$pi       set.$pi/coord.raw
  test -f energy.raw$pi && mv energy.raw$pi set.$pi/energy.raw
  test -f force.raw$pi  && mv force.raw$pi  set.$pi/force.raw
  test -f virial.raw$pi && mv virial.raw$pi set.$pi/virial.raw
  test -f atom_ener.raw$pi && mv atom_ener.raw$pi set.$pi/atom_ener.raw
  test -f fparam.raw$pi && mv fparam.raw$pi set.$pi/fparam.raw

  cd set.$pi
  python -c 'import numpy as np; data = np.loadtxt("box.raw", ndmin=2); data = data.astype(np.float32); np.save("box", data)'
  python -c 'import numpy as np; data = np.loadtxt("coord.raw", ndmin=2); data = data.astype(np.float32); np.save("coord", data)'
  python -c "import numpy as np; import os; 
if os.path.isfile('energy.raw'):
   data = np.loadtxt('energy.raw');
   data = data.astype(np.float32);
   np.save('energy', data)"
  python -c "import numpy as np; import os; 
if os.path.isfile('force.raw'):
   data = np.loadtxt('force.raw', ndmin=2);
   data = data.astype(np.float32);
   np.save('force', data)"
  python -c "import numpy as np; import os; 
if os.path.isfile('virial.raw'):
   data = np.loadtxt('virial.raw', ndmin=2);
   data = data.astype(np.float32);
   np.save('virial', data)"
  python -c "import numpy as np; import os; 
if os.path.isfile('atom_ener.raw'):
   data = np.loadtxt('atom_ener.raw', ndmin=2);
   data = data.astype(np.float32);
   np.save('atom_ener', data)"
  python -c "import numpy as np; import os; 
if os.path.isfile('fparam.raw'):
   data = np.loadtxt('fparam.raw', ndmin=2);
   data = data.astype(np.float32);
   np.save('fparam', data)"
  rm *.raw
  cd ..
done

echo "Combined processing complete."

