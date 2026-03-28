# ORCA-Based gTA Scan Workflow

[中文文档](README_zh.md)

## Overview

This repository contains a small workflow for iterative molecular scanning and constrained optimization:

1. Start from an input XYZ geometry.
2. Apply a turnstile-like rotation with `gTA-cli.py`.
3. Run an ORCA constrained geometry optimization on the rotated structure.
4. Repeat for a user-defined number of iterations.
5. Record the initial single-point energy and all subsequent optimized energies.

This README only covers the files and directories that are actively used by the current workflow:

- `0_orca_templates/`
- `1_inputs/`
- `2_scripts/`


## Repository Layout

- `0_orca_templates/`
  ORCA input templates used by the workflow.
  Key files:
  - `orca-sp-energy-template.txt`
  - `orca-fixed-opt-template_nomaxcycle.txt`
  - `orca-fixed-opt-template_maxcycle.txt`

- `1_inputs/`
  Input files for the workflow.
  Key files:
  - `opted_sf4.xyz`
  - `gta-cli_input-template.json`

- `2_scripts/`
  Scripts used by the workflow.
  Key files:
  - `run-workflow.sh`
  - `gTA-cli.py`
  - `utils.py`


## Dependencies

The current workflow requires:

- Python 3
- `numpy`
- `scipy`
- ORCA 6.0 or newer

Notes:

- `run-workflow.sh` is a Bash script.
- The ORCA executable can be called directly or through a wrapper command such as `singularity exec ... orca`.
- The workflow is currently driven by XYZ input, so only the actively used Python dependencies are listed here.


## Workflow Inputs

The workflow expects the following inputs:

- An initial XYZ geometry, by default `1_inputs/opted_sf4.xyz`
- A gTA JSON template, `1_inputs/gta-cli_input-template.json`
- ORCA templates in `0_orca_templates/`

The runtime script generates a concrete `input.json` for gTA from the JSON template by replacing:

- `GTA_ANCHOR_ATOM`
- `GTA_ARM_ATOMS`
- `GTA_ANGLE`


## Usage

Run the workflow from the repository root:

```bash
cd 2_scripts/
bash ./run-workflow.sh [options]
```

Main options:

- `-m`
  Number of scan/optimization iterations, it decides how many turnstile rotation steps to scan

- `-a`
  gTA rotation angle (in degree) for each scan step as an integer, for example `5` or `"-5"`

- `-c`
  Central atom id used as `anchor_atom`

- `-r`
  Arm atom ids used as `arm_atoms`
  Format example: `"2,4,5"` or `"2-4,7"`

- `-q`
  Molecular charge

- `-u`
  Molecular spin multiplicity

- `-f`
  Fixed atom ids for ORCA constrained optimization
  Format example: `"1,2-4,7-9"`

- `-i`
  Initial XYZ geometry path

- `-n`
  Maximum ORCA geometry optimization cycles in each scan step
  If provided, the workflow uses `orca-fixed-opt-template_maxcycle.txt` and replaces `GEOM_MAX_CYCLE`

- `-k`
  Full ORCA execution command
  This is useful if ORCA is launched through a container wrapper


## Example

```bash
./2_scripts/run-workflow.sh \
  -m 24 \
  -a "5" \
  -c 1 \
  -r "2,4,5" \
  -q 0 \
  -u 1 \
  -f "2-5" \
  -n 50 \
  -i 1_inputs/opted_sf4.xyz \
  -k "/path/to/orca"
```


## What The Script Does

`2_scripts/run-workflow.sh` performs the following steps:

1. Validate required files and parameters.
2. Copy the starting XYZ structure into the runtime workspace.
3. Build a runtime `input.json` from `1_inputs/gta-cli_input-template.json`.
4. Run a single-point ORCA energy calculation for the starting geometry.
5. Enter the iterative loop:
   - rotate the structure with gTA
   - run ORCA constrained optimization
   - update the current structure for the next iteration
   - append energies to the log


## Useful Notes

- If the default ORCA command in `run-workflow.sh` is not valid on your machine, pass your own command with `-k`.
- For negative rotation angles, quoting is recommended, for example `-a "-5"`.
- The `-f` and `-r` options support compact atom-range syntax such as `"1,2-4,7"`.

