#!/bin/bash
# This script extracts frames from a trajectory file and (optionally) copies a specified file into each frame folder.

# Parse command-line options using getopt
OPTS=$(getopt -o c:e: --long copy:,extract: -n 'extract_frames.sh' -- "$@")
if [ $? != 0 ]; then
    echo "Failed parsing options." >&2
    exit 1
fi
eval set -- "$OPTS"

COPYFILE=""
TRAJ_FILE=""

while true; do
    case "$1" in
        -c | --copy )
            COPYFILE="$2"
            shift 2 ;;
        -e | --extract )
            TRAJ_FILE="$2"
            shift 2 ;;
        -- )
            shift; break ;;
        * )
            break ;;
    esac
done

# Check that the trajectory file is provided and exists.
if [ -z "$TRAJ_FILE" ]; then
    echo "Error: Please specify a trajectory file using the -e or --extract flag."
    exit 1
fi

if [ ! -f "$TRAJ_FILE" ]; then
    echo "Trajectory file '$TRAJ_FILE' not found!"
    exit 1
fi

# If a copy file was specified, check that it exists.
if [ -n "$COPYFILE" ] && [ ! -f "$COPYFILE" ]; then
    echo "File to copy '$COPYFILE' not found!"
    exit 1
fi

# Read from the trajectory file.
exec < "$TRAJ_FILE"

# The first frame's first line gives the number of atoms; we assume this remains constant.
N_ATOMS=""

while read -r atoms_line; do
    # On the first frame, set N_ATOMS.
    if [ -z "$N_ATOMS" ]; then
        N_ATOMS=$atoms_line
    fi
    
    # Read the comment line (should include "Frame <number>")
    read -r COMMENT_LINE
    FRAME_NUM=$(echo "$COMMENT_LINE" | grep -oP 'Frame \K\d+')
    FRAME_DIR=$(printf "%04d" "$FRAME_NUM")
    
    # Create the directory for the frame.
    mkdir -p "$FRAME_DIR"
    
    # Write the frame's header (atom count and comment) to geom.xyz.
    {
        echo "$atoms_line"
        echo "$COMMENT_LINE"
    } > "$FRAME_DIR/geom.xyz"
    
    # If a file to copy was specified, copy it into the frame folder.
    if [ -n "$COPYFILE" ]; then
        cp "$COPYFILE" "$FRAME_DIR/"
    fi
    
    # Append the atomic coordinate lines to geom.xyz.
    for (( i = 0; i < N_ATOMS; i++ )); do
        read -r LINE
        echo "$LINE" >> "$FRAME_DIR/geom.xyz"
    done
done

