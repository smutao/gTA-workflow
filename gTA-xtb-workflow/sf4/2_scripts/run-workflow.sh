#!/bin/bash

# ==============================================================================
#  generalized Turnstile Rotation scan+constrained optimization workflow for xtb   
#
#  Features:
#  1. Read runtime settings from short getopts flags
#  2. Generate fix-input-local.txt and input.json from templates
#  3. Run gTA rotation + xtb geometry optimization in a fixed iteration loop
#  4. Record absolute/relative energies and save per-iteration snapshots/trajectory
#
# ==============================================================================

# --- Shell behavior ---
# Exit immediately if a command fails
set -e
# Treat any failure in a pipeline as failure
set -o pipefail


# Resolve script directory and project root
# This allows running the script safely from any location
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
INVOCATION_DIR=$(pwd)


# --- Default parameters ---
MAX_ITERATIONS=25
GTA_ANGLE=5
GTA_ANCHOR_ATOM=1
GTA_ARM_ATOMS="2,3,5"
FIXED_ATOMS_1BASED="2-5"
CHARGE=0
UNPAIR=0
GFN_LEVEL=2

INITIAL_XYZ_FILE="$PROJECT_ROOT/1_inputs/sf4-stable.xyz"
XTB_EXEC_PATH="/home/user/packages/xtb-dist/bin/xtb"

FIX_INPUT_TEMPLATE="$PROJECT_ROOT/1_inputs/fix-input-template.txt"
GTA_SCRIPT_FILE="$PROJECT_ROOT/2_scripts/gTA-cli.py"
GTA_JSON_TEMPLATE="$PROJECT_ROOT/1_inputs/gta-cli_input-template.json"
WORKSPACE_DIR="$PROJECT_ROOT/4_workspace"
TARGET_GTA_OUTPUT_SUFFIX=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]
  -m <int>      MAX_ITERATIONS (default: $MAX_ITERATIONS)
  -a <number>   GTA angle in degree, e.g. -5 or 10 (default: $GTA_ANGLE)
  -c <int>      GTA anchor atom id (1-based, default: $GTA_ANCHOR_ATOM)
  -r <list>     GTA arm atom ids, comma separated, e.g. 2,3,5 (default: $GTA_ARM_ATOMS)
  -q <int>      CHARGE (default: $CHARGE)
  -u <int>      UNPAIR (default: $UNPAIR)
  -f <expr>     fixed atoms for xtb opt, e.g. 1,2-4,7-9 (default: $FIXED_ATOMS_1BASED)
  -i <path>     initial xyz file path (default: $INITIAL_XYZ_FILE)
  -x <path/cmd> xtb executable path or command (default: $XTB_EXEC_PATH)
  -g <int>      gfn level for xtb --gfn (default: $GFN_LEVEL)
  -h            show help
EOF
}

while getopts ":m:a:c:r:q:u:f:i:x:g:h" opt; do
    case "$opt" in
        m) MAX_ITERATIONS="$OPTARG" ;;
        a) GTA_ANGLE="$OPTARG" ;;
        c) GTA_ANCHOR_ATOM="$OPTARG" ;;
        r) GTA_ARM_ATOMS="$OPTARG" ;;
        q) CHARGE="$OPTARG" ;;
        u) UNPAIR="$OPTARG" ;;
        f) FIXED_ATOMS_1BASED="$OPTARG" ;;
        i) INITIAL_XYZ_FILE="$OPTARG" ;;
        x) XTB_EXEC_PATH="$OPTARG" ;;
        g) GFN_LEVEL="$OPTARG" ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "Error: option -$OPTARG requires an argument" >&2
            usage >&2
            exit 1
            ;;
        \?)
            echo "Error: unsupported option -$OPTARG" >&2
            usage >&2
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

if [ "$#" -ne 0 ]; then
    echo "Error: unrecognized positional arguments: $*" >&2
    usage >&2
    exit 1
fi

# Normalize and validate arguments
GTA_ARM_ATOMS=$(echo "$GTA_ARM_ATOMS" | tr -d '[:space:]')
FIXED_ATOMS_1BASED=$(echo "$FIXED_ATOMS_1BASED" | tr -d '[:space:]')

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [ "$MAX_ITERATIONS" -le 0 ]; then
    echo "Error: -m must be a positive integer" >&2
    exit 1
fi
if ! [[ "$GTA_ANGLE" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "Error: -a must be numeric (supports negative and decimal values)" >&2
    exit 1
fi
if ! [[ "$GTA_ANCHOR_ATOM" =~ ^[0-9]+$ ]] || [ "$GTA_ANCHOR_ATOM" -le 0 ]; then
    echo "Error: -c must be a positive integer (1-based atom index)" >&2
    exit 1
fi
if ! [[ "$GTA_ARM_ATOMS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo "Error: -r must be a comma-separated atom index list, e.g. 2,3,5" >&2
    exit 1
fi
if ! [[ "$CHARGE" =~ ^-?[0-9]+$ ]]; then
    echo "Error: -q must be an integer" >&2
    exit 1
fi
if ! [[ "$UNPAIR" =~ ^[0-9]+$ ]]; then
    echo "Error: -u must be a non-negative integer" >&2
    exit 1
fi
if ! [[ "$FIXED_ATOMS_1BASED" =~ ^[0-9,-]+$ ]]; then
    echo "Error: -f format is invalid, expected something like 1,2-4,7-9" >&2
    exit 1
fi
if ! [[ "$GFN_LEVEL" =~ ^[0-9]+$ ]] || [ "$GFN_LEVEL" -le 0 ]; then
    echo "Error: -g must be a positive integer" >&2
    exit 1
fi

if [[ "$INITIAL_XYZ_FILE" != /* ]]; then
    INITIAL_XYZ_FILE="$INVOCATION_DIR/$INITIAL_XYZ_FILE"
fi

if [[ "$XTB_EXEC_PATH" == */* ]]; then
    if [ ! -x "$XTB_EXEC_PATH" ]; then
        echo "Error: xtb executable does not exist or is not executable: $XTB_EXEC_PATH" >&2
        exit 1
    fi
else
    if ! command -v "$XTB_EXEC_PATH" >/dev/null 2>&1; then
        echo "Error: xtb command not found in PATH: $XTB_EXEC_PATH" >&2
        exit 1
    fi
    XTB_EXEC_PATH=$(command -v "$XTB_EXEC_PATH")
fi

escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[&|]/\\&/g'
}


# ==============================================================================
# --- Workflow starts (normally no edits required below) ---
# ==============================================================================

echo "================================================="
echo "===   Molecular Iterative Optimization Workflow Started   ==="
echo "================================================="
echo "Parameters: -m $MAX_ITERATIONS -a $GTA_ANGLE -c $GTA_ANCHOR_ATOM -r $GTA_ARM_ATOMS -q $CHARGE -u $UNPAIR -f $FIXED_ATOMS_1BASED -g $GFN_LEVEL"
echo "Initial geometry: $INITIAL_XYZ_FILE"
echo "xtb executable: $XTB_EXEC_PATH"
echo

# --- 1. Initialization ---
echo "--- Step 1: Environment initialization ---"

# Create and enter workspace; all following operations run here
mkdir -p "$WORKSPACE_DIR"
# Prepare directory for per-iteration xtb outputs
mkdir -p "$WORKSPACE_DIR/xtb_sav"
cd "$WORKSPACE_DIR"
echo "Workspace set to: $WORKSPACE_DIR"



# Check required input files
for f in "$INITIAL_XYZ_FILE" "$FIX_INPUT_TEMPLATE" "$GTA_SCRIPT_FILE" "$GTA_JSON_TEMPLATE"; do
    if [ ! -f "$f" ]; then
        echo "Error: required file not found: $f" >&2
        exit 1
    fi
done
echo "All required input files are present."

# Initialize energy log
ENERGY_LOG="energy_log.csv"
echo "Iteration,Energy(Eh),Relative Energy (kcal/mol)" > "$ENERGY_LOG"
echo "Created energy log file: $ENERGY_LOG"

# Copy initial geometry as the first loop input
cp "$INITIAL_XYZ_FILE" ./xtbopt.xyz
echo "Copied initial geometry to ./xtbopt.xyz"

# Save a copy of the user-provided starting geometry and initialize scan trajectory
cp "$INITIAL_XYZ_FILE" ./starting_geom.xyz
SCAN_TRAJ="scan-traj.xyz"
cp ./starting_geom.xyz "./$SCAN_TRAJ"
echo "Saved starting geometry: ./starting_geom.xyz"
echo "Initialized trajectory file: ./$SCAN_TRAJ (frame 0: starting_geom.xyz)"

# Generate local xtb and gTA config files from templates
FIXED_ATOMS_ESCAPED=$(escape_sed_replacement "$FIXED_ATOMS_1BASED")
sed "s|FIXED_ATOMS_1BASED|$FIXED_ATOMS_ESCAPED|g" "$FIX_INPUT_TEMPLATE" > ./fix-input-local.txt

GTA_ANCHOR_ESCAPED=$(escape_sed_replacement "$GTA_ANCHOR_ATOM")
GTA_ARM_ESCAPED=$(escape_sed_replacement "$GTA_ARM_ATOMS")
GTA_ANGLE_ESCAPED=$(escape_sed_replacement "$GTA_ANGLE")
sed \
    -e "s|GTA_ANCHOR_ATOM|$GTA_ANCHOR_ESCAPED|g" \
    -e "s|GTA_ARM_ATOMS|$GTA_ARM_ESCAPED|g" \
    -e "s|GTA_ANGLE|$GTA_ANGLE_ESCAPED|g" \
    "$GTA_JSON_TEMPLATE" > ./input.json

GTA_ALIAS=$(awk -F'"' '/"alias"[[:space:]]*:/ {print $4; exit}' ./input.json)
if [ -z "$GTA_ALIAS" ]; then
    echo "Error: failed to read transformation alias from input.json" >&2
    exit 1
fi
TARGET_GTA_OUTPUT_SUFFIX="${GTA_ALIAS}_${GTA_ANGLE}deg"
echo "Prepared local xtb and gTA config files."
echo "Expected gTA output suffix for this run: $TARGET_GTA_OUTPUT_SUFFIX"
echo

# --- 1.5 Initial single-point energy ---
echo "--- Step 1.5: Initial single-point energy calculation ---"
SP_LOG="./xtb_sav/I000_xtbopt.out.txt"
if ! $XTB_EXEC_PATH --gfn "$GFN_LEVEL" --verbose -c "$CHARGE" -u "$UNPAIR" ./xtbopt.xyz > "$SP_LOG" 2>&1; then
    echo "Error: initial single-point calculation failed; see output: $SP_LOG" >&2
    exit 1
fi
echo "Initial single-point output written to: $SP_LOG"

INITIAL_ENERGY=$(grep 'TOTAL ENERGY' "$SP_LOG" | tail -n 1 | awk '{print $4}')
if [ -z "$INITIAL_ENERGY" ]; then
    echo "Error: failed to extract initial single-point energy from '$SP_LOG'" >&2
    exit 1
fi
REFERENCE_ENERGY="$INITIAL_ENERGY"
echo "0,$INITIAL_ENERGY,0.000000" >> "$ENERGY_LOG"
echo "Initial energy (iteration 0): $INITIAL_ENERGY Eh (relative: 0.000000 kcal/mol)"
echo

# --- 2. Main loop ---
for i in $(seq 1 $MAX_ITERATIONS)
do
    echo "------------------ Starting iteration $i / $MAX_ITERATIONS ------------------"
    SAV_DIR="./xtb_sav"
    IDX=$(printf "%03d" "$i")
    SAVE_PREFIX="I${IDX}_xtbopt"
    XTB_STDOUT_FILE="$SAV_DIR/${SAVE_PREFIX}.out.txt"

    # --- Step A: gTA rotation ---
    echo "[Step A] Running gTA rotation..."
    python3 "$GTA_SCRIPT_FILE" ./input.json
    #ROTATED_FILE="xtbopt/xtbopt_rotated_5deg.xyz"
    ROTATED_FILE="xtbopt/xtbopt_${TARGET_GTA_OUTPUT_SUFFIX}.xyz"
    if [ ! -f "$ROTATED_FILE" ]; then
        echo "Error: gTA did not generate rotated file '$ROTATED_FILE'" >&2
        exit 1
    fi
    echo "Rotation completed, output file: $ROTATED_FILE"

    # --- Step B: xtb geometry optimization ---
    echo "[Step B] Running xtb geometry optimization..."
    rm -rf xtbopt.log xtbopt.xyz 
    if ! $XTB_EXEC_PATH --gfn "$GFN_LEVEL" "$ROTATED_FILE" --verbose -c "$CHARGE" -u "$UNPAIR" --input ./fix-input-local.txt --opt > "$XTB_STDOUT_FILE" 2>&1; then
        echo "Error: xtb run failed; see output: $XTB_STDOUT_FILE" >&2
        exit 1
    fi
    if [ ! -f "xtbopt.xyz" ]; then
        echo "Error: xtb did not generate optimized file 'xtbopt.xyz'" >&2
        exit 1
    fi
    echo "Geometry optimization completed, output file: xtbopt.xyz"
    echo "xtb stdout written to: $XTB_STDOUT_FILE"

    # --- Save this iteration's xtb snapshots ---
    # Copy log/structure with a 3-digit iteration prefix
    cp -f xtbopt.log "$SAV_DIR/${SAVE_PREFIX}.log" || echo "Warning: xtbopt.log not found, skipping save" >&2
    cp -f xtbopt.xyz "$SAV_DIR/${SAVE_PREFIX}.xyz" || echo "Warning: xtbopt.xyz not found, skipping save" >&2
    echo "Saved iteration ${i} snapshot to: $SAV_DIR/${SAVE_PREFIX}.(log|xyz)"

    # Append this iteration's final structure to scan trajectory
    SNAPSHOT_XYZ="$SAV_DIR/${SAVE_PREFIX}.xyz"
    if [ -f "$SNAPSHOT_XYZ" ]; then
        cat "$SNAPSHOT_XYZ" >> "$SCAN_TRAJ"
        echo "Appended iteration ${i} structure to trajectory: ./$SCAN_TRAJ"
    else
        echo "Warning: '$SNAPSHOT_XYZ' not found, skipping trajectory append" >&2
    fi

    # --- Step C: Record energy ---
    echo "[Step C] Recording energy..."
    ENERGY_VALUE=$(sed -n '2p' xtbopt.xyz | awk '{print $2}')
    if [ -z "$ENERGY_VALUE" ]; then
        echo "Warning: failed to extract energy value from xtbopt.xyz" >&2
    else
        RELATIVE_ENERGY=$(awk -v e="$ENERGY_VALUE" -v e0="$REFERENCE_ENERGY" 'BEGIN {printf "%.6f", (e - e0) * 627.509}')
        echo "$i,$ENERGY_VALUE,$RELATIVE_ENERGY" >> "$ENERGY_LOG"
        echo "Iteration $i energy: $ENERGY_VALUE Eh (relative: $RELATIVE_ENERGY kcal/mol)"
    fi
    # Clean up xtb temporary files
    rm -rf wbo charges xtbtopo.mol xtbrestart 
    echo
done

# --- 3. Finish ---
echo "------------------ Workflow completed ------------------"
mv xtbopt.xyz final_optimized.xyz

echo "Final optimized structure saved to: $WORKSPACE_DIR/final_optimized.xyz"
echo "Energy log saved to: $WORKSPACE_DIR/energy_log.csv"
echo "Starting geometry copy saved to: $WORKSPACE_DIR/starting_geom.xyz"
echo "Scan trajectory saved to: $WORKSPACE_DIR/scan-traj.xyz"
echo "================================================="
