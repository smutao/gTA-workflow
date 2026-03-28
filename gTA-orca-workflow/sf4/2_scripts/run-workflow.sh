#!/bin/bash

# ==============================================================================
#  Molecular Structure Iterative Optimization Workflow (ORCA)
#  Features:
#  - gTA rotation + ORCA constrained geometry optimization iterations
#  - Initial-geometry single-point energy (iteration 0)
#  - Record absolute/relative energies to energy_log.csv
#  - Append trajectory to scan-traj.xyz (initial geometry + each IXXX_FixedOpt.xyz)
# ==============================================================================

set -e
set -o pipefail

usage() {
  cat <<'EOF'
Usage:
  run-workflow.sh [-m max_iter] [-a angle] [-c anchor_atom] [-r arm_atomids] \
                  [-q charge] [-u mult] [-f opt_fix_atomids] [-i initial_geom] [-n max_cycle] [-k orca_cmd]

Options:
  -m  Number of iterations, mapped to MAX_ITERATIONS
  -a  gTA rotation angle (integer, can be negative, e.g. '-5' or '10'), mapped to angle:[GTA_ANGLE]
  -c  gTA central atom id, mapped to anchor_atom:[GTA_ANCHOR_ATOM]
  -r  gTA arm atom ids, supports "1,2-4,7", mapped to arm_atoms:[GTA_ARM_ATOMS]
  -q  Molecular charge CHARGE
  -u  Molecular spin multiplicity MULT
  -f  Fixed atom ids for optimization, supports "1,2-4,7-9" expansion to (1 2 3 4 7 8 9)
  -i  Initial geometry file path, mapped to INITIAL_XYZ_FILE
  -n  ORCA geometry optimization MaxIter (integer). If set, use maxcycle template and replace GEOM_MAX_CYCLE
  -k  Override ORCA execution command (full command string, e.g. "singularity exec ... orca")
  -h  Show help
EOF
}

expand_atom_id_list() {
  local spec="$1"
  local -a out=()
  local -a parts=()

  spec="${spec// /}"
  if [ -z "$spec" ]; then
    echo ""
    return 0
  fi

  IFS=',' read -r -a parts <<< "$spec"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^[0-9]+$ ]]; then
      if [ "$part" -lt 1 ]; then
        echo "Error: atom id must be >= 1: $part" >&2
        return 1
      fi
      out+=("$part")
    elif [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      local i
      if [ "$start" -lt 1 ] || [ "$end" -lt 1 ]; then
        echo "Error: atom id must be >= 1: $part" >&2
        return 1
      fi
      if [ "$start" -gt "$end" ]; then
        echo "Error: range start is greater than range end: $part" >&2
        return 1
      fi
      for ((i=start; i<=end; i++)); do
        out+=("$i")
      done
    else
      echo "Error: cannot parse atom id list: $part" >&2
      return 1
    fi
  done

  echo "${out[*]}"
}

join_by_comma_space() {
  local first=1
  local out=""
  local x
  for x in "$@"; do
    if [ "$first" -eq 1 ]; then
      out="$x"
      first=0
    else
      out="$out, $x"
    fi
  done
  echo "$out"
}

# Resolve script directory and project root
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# ---------------- Default parameters ----------------
MAX_ITERATIONS=24
CHARGE=0
MULT=1
INITIAL_XYZ_FILE="$PROJECT_ROOT/1_inputs/opted_sf4.xyz"
FIXED_ATOMS_1BASED=(2 3 4 5)

GTA_ANGLE="5"
GTA_ANCHOR_ATOM=1
GTA_ARM_ATOMS_SPEC="2,4,5"
FIXED_ATOMS_SPEC=""
MAX_CYCLE=""

# ---------------- Path configuration ----------------
GTA_SCRIPT_FILE="$PROJECT_ROOT/2_scripts/gTA-cli.py"
GTA_JSON_TEMPLATE="$PROJECT_ROOT/1_inputs/gta-cli_input-template.json"
SP_TEMPLATE="$PROJECT_ROOT/0_orca_templates/orca-sp-energy-template.txt"
ORCA_TEMPLATE_NOMAX="$PROJECT_ROOT/0_orca_templates/orca-fixed-opt-template_nomaxcycle.txt"
ORCA_TEMPLATE_MAX="$PROJECT_ROOT/0_orca_templates/orca-fixed-opt-template_maxcycle.txt"
ORCA_OPT_TEMPLATE="$ORCA_TEMPLATE_NOMAX"
WORKSPACE_DIR="$PROJECT_ROOT/4_workspace"
ORCA_PATH="/path/to/orca"

# ---------------- Argument parsing ----------------
while getopts ":m:a:c:r:q:u:f:i:n:k:h" opt; do
  case "$opt" in
    m)
      MAX_ITERATIONS="$OPTARG"
      ;;
    a)
      GTA_ANGLE="$OPTARG"
      ;;
    c)
      GTA_ANCHOR_ATOM="$OPTARG"
      ;;
    r)
      GTA_ARM_ATOMS_SPEC="$OPTARG"
      ;;
    q)
      CHARGE="$OPTARG"
      ;;
    u)
      MULT="$OPTARG"
      ;;
    f)
      FIXED_ATOMS_SPEC="$OPTARG"
      ;;
    i)
      INITIAL_XYZ_FILE="$OPTARG"
      ;;
    n)
      MAX_CYCLE="$OPTARG"
      ;;
    k)
      ORCA_PATH="$OPTARG"
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Error: option -$OPTARG requires an argument" >&2
      usage
      exit 1
      ;;
    \?)
      echo "Error: unknown option -$OPTARG" >&2
      usage
      exit 1
      ;;
  esac
done

# ---------------- Argument validation ----------------
if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || [ "$MAX_ITERATIONS" -lt 1 ]; then
  echo "Error: -m must be a positive integer" >&2
  exit 1
fi

if [[ ! "$GTA_ANGLE" =~ ^-?[0-9]+$ ]]; then
  echo "Error: -a must be an integer (can be negative)" >&2
  exit 1
fi

if [[ ! "$GTA_ANCHOR_ATOM" =~ ^[0-9]+$ ]] || [ "$GTA_ANCHOR_ATOM" -lt 1 ]; then
  echo "Error: -c must be a positive integer" >&2
  exit 1
fi

if [[ ! "$CHARGE" =~ ^-?[0-9]+$ ]]; then
  echo "Error: -q must be an integer" >&2
  exit 1
fi

if [[ ! "$MULT" =~ ^[0-9]+$ ]] || [ "$MULT" -lt 1 ]; then
  echo "Error: -u must be a positive integer" >&2
  exit 1
fi

if [ -z "$ORCA_PATH" ]; then
  echo "Error: ORCA command from -k cannot be empty" >&2
  exit 1
fi

if [ -n "$MAX_CYCLE" ]; then
  if [[ ! "$MAX_CYCLE" =~ ^[0-9]+$ ]] || [ "$MAX_CYCLE" -lt 1 ]; then
    echo "Error: -n must be a positive integer" >&2
    exit 1
  fi
  ORCA_OPT_TEMPLATE="$ORCA_TEMPLATE_MAX"
else
  ORCA_OPT_TEMPLATE="$ORCA_TEMPLATE_NOMAX"
fi

# Normalize initial geometry path (if relative, resolve against current invocation directory)
if [[ "$INITIAL_XYZ_FILE" != /* ]]; then
  INITIAL_XYZ_FILE="$PWD/$INITIAL_XYZ_FILE"
fi

# Parse arm atom ids
ARM_IDS_EXPANDED=$(expand_atom_id_list "$GTA_ARM_ATOMS_SPEC") || exit 1
if [ -z "$ARM_IDS_EXPANDED" ]; then
  echo "Error: parsed result of -r is empty" >&2
  exit 1
fi
read -r -a GTA_ARM_ATOMS_ARRAY <<< "$ARM_IDS_EXPANDED"
GTA_ARM_ATOMS_JSON=$(join_by_comma_space "${GTA_ARM_ATOMS_ARRAY[@]}")

# Parse fixed atom ids
if [ -n "$FIXED_ATOMS_SPEC" ]; then
  FIXED_IDS_EXPANDED=$(expand_atom_id_list "$FIXED_ATOMS_SPEC") || exit 1
  if [ -z "$FIXED_IDS_EXPANDED" ]; then
    echo "Error: parsed result of -f is empty" >&2
    exit 1
  fi
  read -r -a FIXED_ATOMS_1BASED <<< "$FIXED_IDS_EXPANDED"
fi

echo "================================================="
echo "===   Molecular Iterative Optimization Workflow (ORCA)   ==="
echo "================================================="
echo "Parameter summary:"
echo "  MAX_ITERATIONS = $MAX_ITERATIONS"
echo "  CHARGE/MULT    = $CHARGE / $MULT"
echo "  INITIAL_XYZ    = $INITIAL_XYZ_FILE"
echo "  GTA angle      = $GTA_ANGLE"
echo "  GTA anchor     = $GTA_ANCHOR_ATOM"
echo "  GTA arm atoms  = [$GTA_ARM_ATOMS_JSON]"
echo "  FIXED atoms    = (${FIXED_ATOMS_1BASED[*]})"
echo "  ORCA command   = $ORCA_PATH"
if [ -n "$MAX_CYCLE" ]; then
  echo "  ORCA template  = maxcycle (MaxIter=$MAX_CYCLE)"
else
  echo "  ORCA template  = nomaxcycle"
fi
echo

# ---------------- 1. Initialization ----------------
echo "--- Step 1: Environment initialization ---"

for f in "$INITIAL_XYZ_FILE" "$GTA_SCRIPT_FILE" "$GTA_JSON_TEMPLATE" "$SP_TEMPLATE" "$ORCA_OPT_TEMPLATE"; do
  if [ ! -f "$f" ]; then
    echo "Error: required file not found: $f" >&2
    exit 1
  fi
done
echo "All required input files found."

mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
echo "Working directory set to: $WORKSPACE_DIR"

mkdir -p orca orca_sav

ENERGY_LOG="energy_log.csv"
REL_FACTOR=627.509
echo "Iteration,Energy(Eh),Relative Energy (kcal/mol)" > "$ENERGY_LOG"
echo "Created energy log file: $ENERGY_LOG"

SCAN_TRAJ="scan-traj.xyz"

cp "$INITIAL_XYZ_FILE" ./orcaopt.xyz
echo "Copied initial geometry to ./orcaopt.xyz"

cp "$INITIAL_XYZ_FILE" ./starting_geom.xyz
echo "Saved initial geometry snapshot to: ./starting_geom.xyz"

cp ./starting_geom.xyz "$SCAN_TRAJ"
echo "Initialized scan trajectory: $SCAN_TRAJ (frame 1 is the initial geometry)"

# Generate runtime gTA input.json
sed \
  -e "s/GTA_ANCHOR_ATOM/$GTA_ANCHOR_ATOM/g" \
  -e "s/GTA_ARM_ATOMS/$GTA_ARM_ATOMS_JSON/g" \
  -e "s/GTA_ANGLE/$GTA_ANGLE/g" \
  "$GTA_JSON_TEMPLATE" > ./input.json
echo "Generated gTA config: ./input.json"

TARGET_GTA_OUTPUT_SUFFIX=$(
  python3 - "$PWD/input.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p, "r") as f:
    cfg = json.load(f)
t = cfg["transformations"][0]
print(f"{t['alias']}_{t['angle'][0]}deg")
PY
)
if [ -z "$TARGET_GTA_OUTPUT_SUFFIX" ]; then
  echo "Error: cannot derive gTA output suffix from input.json" >&2
  exit 1
fi
echo "gTA output suffix: $TARGET_GTA_OUTPUT_SUFFIX"
echo

# ---------------- 1.5 Initial single-point energy ----------------
echo "--- Step 1.5: Initial-geometry single-point energy ---"
ORCA_RUN_DIR="orca"
SP_IN="$ORCA_RUN_DIR/SP0.txt"
SP_OUT="$ORCA_RUN_DIR/SP0.out.txt"

rm -rf "$ORCA_RUN_DIR"/*

XYZ_LINES=$(tail -n +3 ./starting_geom.xyz)
{
  while IFS= read -r line; do
    if [[ "$line" == *"XYZ_LINES"* ]]; then
      printf "%s\n" "$XYZ_LINES"
      continue
    fi
    line=${line/CHAR/$CHARGE}
    line=${line/MULT/$MULT}
    printf "%s\n" "$line"
  done < "$SP_TEMPLATE"
} > "$SP_IN"

( cd "$ORCA_RUN_DIR" && $ORCA_PATH SP0.txt > SP0.out.txt ) || true

if grep -q "TOTAL RUN TIME" "$SP_OUT" 2>/dev/null; then
  echo "Initial ORCA single-point run finished"
else
  echo "Warning: initial ORCA single-point run may be incomplete (TOTAL RUN TIME not found)"
fi

SP_ENERGY=$(awk '/FINAL SINGLE POINT ENERGY/{e=$NF} END{print e}' "$SP_OUT" 2>/dev/null)
[ -z "$SP_ENERGY" ] && SP_ENERGY=NA
if [ "$SP_ENERGY" != "NA" ]; then
  REF_ENERGY="$SP_ENERGY"
  SP_REL_ENERGY="0.000000"
else
  REF_ENERGY=""
  SP_REL_ENERGY="NA"
fi
echo "0,$SP_ENERGY,$SP_REL_ENERGY" >> "$ENERGY_LOG"
echo "Iteration 0 (initial geometry) energy: $SP_ENERGY Eh, relative energy: $SP_REL_ENERGY kcal/mol"
echo

# ---------------- 2. Main loop ----------------
for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo "------------------ Starting iteration $i / $MAX_ITERATIONS ------------------"

  # A) gTA rotation
  echo "[Step A] Rotating geometry with gTA..."
  python3 "$GTA_SCRIPT_FILE" ./input.json
  ROTATED_DIR="orcaopt"
  ROTATED_FILE="${ROTATED_DIR}/orcaopt_${TARGET_GTA_OUTPUT_SUFFIX}.xyz"
  if [ ! -f "$ROTATED_FILE" ]; then
    echo "Error: gTA did not generate rotated file '$ROTATED_FILE'" >&2
    exit 1
  fi
  echo "Rotation complete: $ROTATED_FILE"

  # B) ORCA constrained optimization
  echo "[Step B] Running ORCA constrained optimization..."
  ORCA_RUN_DIR="orca"
  ORCA_SAVE_DIR="orca_sav"
  mkdir -p "$ORCA_RUN_DIR" "$ORCA_SAVE_DIR"
  rm -rf "$ORCA_RUN_DIR"/*

  FIXED_LINES=$(
    for a in "${FIXED_ATOMS_1BASED[@]}"; do
      printf '        {C %d C}\n' "$((a-1))"
    done
  )

  XYZ_LINES=$(tail -n +3 "$ROTATED_FILE")
  ORCA_IN="$ORCA_RUN_DIR/FixedOpt.txt"
  {
    while IFS= read -r line; do
      if [[ "$line" == *"FIXED_ATOM_LINES"* ]]; then
        printf "%s\n" "$FIXED_LINES"
        continue
      fi
      if [[ "$line" == *"XYZ_LINES"* ]]; then
        printf "%s\n" "$XYZ_LINES"
        continue
      fi
      line=${line/CHAR/$CHARGE}
      line=${line/MULT/$MULT}
      if [ -n "$MAX_CYCLE" ]; then
        line=${line/GEOM_MAX_CYCLE/$MAX_CYCLE}
      fi
      printf "%s\n" "$line"
    done < "$ORCA_OPT_TEMPLATE"
  } > "$ORCA_IN"

  ( cd "$ORCA_RUN_DIR" && $ORCA_PATH FixedOpt.txt > FixedOpt.out.txt ) || true

  if grep -q "TOTAL RUN TIME" "$ORCA_RUN_DIR/FixedOpt.out.txt" 2>/dev/null; then
    echo "ORCA finished normally"
  else
    echo "Warning: ORCA may be incomplete (TOTAL RUN TIME not found)"
  fi

  ITER_TAG=$(printf "I%03d" "$i")
  for f in FixedOpt.txt FixedOpt.out.txt FixedOpt_trj.xyz FixedOpt.xyz; do
    if [ -f "$ORCA_RUN_DIR/$f" ]; then
      cp -f "$ORCA_RUN_DIR/$f" "$ORCA_SAVE_DIR/${ITER_TAG}_$f"
    fi
  done

  SAVED_OPT_XYZ="$ORCA_SAVE_DIR/${ITER_TAG}_FixedOpt.xyz"
  if [ -f "$SAVED_OPT_XYZ" ]; then
    cat "$SAVED_OPT_XYZ" >> "$SCAN_TRAJ"
    echo "Appended trajectory frame: $SAVED_OPT_XYZ -> $SCAN_TRAJ"
  else
    echo "Warning: $SAVED_OPT_XYZ not found, skipping trajectory append for this iteration"
  fi

  if [ -f "$ORCA_RUN_DIR/FixedOpt.xyz" ]; then
    cp -f "$ORCA_RUN_DIR/FixedOpt.xyz" ./orcaopt.xyz
    echo "Updated next-iteration input: ./orcaopt.xyz"
  else
    echo "Warning: ORCA optimized geometry FixedOpt.xyz not found, keeping previous orcaopt.xyz"
  fi

  # C) Record energy
  echo "[Step C] Recording energy..."
  if [ -f "$ORCA_RUN_DIR/FixedOpt.xyz" ]; then
    ENERGY_VALUE=$(sed -n '2p' "$ORCA_RUN_DIR/FixedOpt.xyz" | awk '{print $NF}')
    [ -z "$ENERGY_VALUE" ] && ENERGY_VALUE=NA
  else
    ENERGY_VALUE=NA
  fi

  if [ "$ENERGY_VALUE" != "NA" ] && [ -n "$REF_ENERGY" ]; then
    REL_ENERGY=$(awk -v e="$ENERGY_VALUE" -v ref="$REF_ENERGY" -v fac="$REL_FACTOR" 'BEGIN {printf "%.6f", (e-ref)*fac}')
  else
    REL_ENERGY=NA
  fi
  echo "$i,$ENERGY_VALUE,$REL_ENERGY" >> "$ENERGY_LOG"
  echo "Iteration $i energy: $ENERGY_VALUE Eh, relative energy: $REL_ENERGY kcal/mol"
  echo
done

# ---------------- 3. Finish ----------------
echo "------------------ Workflow completed ------------------"
if [ -f ./orcaopt.xyz ]; then
  cp -f ./orcaopt.xyz ./final_optimized.xyz
  echo "Final optimized geometry saved to: $WORKSPACE_DIR/final_optimized.xyz"
else
  echo "Warning: orcaopt.xyz not found, final geometry export skipped"
fi
echo "Energy log saved to: $WORKSPACE_DIR/energy_log.csv"
echo "Trajectory file saved to: $WORKSPACE_DIR/scan-traj.xyz"
echo "================================================="
