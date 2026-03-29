# xtb-Based gTA Scan Workflow

[中文文档](./README_zh.md)

This repository contains a small workflow for iterative turnstile rotation scans followed by constrained `xtb` geometry optimization.

The workflow is driven by [`2_scripts/run-workflow.sh`](./2_scripts/run-workflow.sh), which:

- builds local input files from templates,
- applies a gTA-based rotation to the current geometry,
- runs a constrained `xtb` optimization after each rotation,
- records absolute and relative energies,
- stores step-by-step structures and a combined XYZ trajectory.

## Dependency

The main dependencies are:

- Python 3
- `numpy`
- `scipy`
- `xtb`


`xtb` must be installed separately and available either:

- by absolute path passed with `-x`, or
- through `PATH` as an executable command.

Notes:

- The current workflow is configured around XYZ input and `first_coord_sphere_only = true`.
- In this mode, the practical external requirements are `numpy`, `scipy`, and `xtb`.

## Repository Layout

Only the directories relevant to this workflow are documented here.

### `1_inputs/`

Input files and templates used by the workflow:

- `sf4-stable.xyz`
  Default starting geometry. 
- `fix-input-template.txt`
  Template for the local `xtb` constrained optimization input. Usually there is no need to change this file.
- `gta-cli_input-template.json`
  Template for the local gTA rotation input. Usually there is no need to change this file if you want to rotate just one turnstile.

### `2_scripts/`

Core workflow scripts:

- `run-workflow.sh`
  Main entry point for the iterative scan + optimization workflow.
- `gTA-cli.py`
  Applies the turnstile rotation defined by the generated JSON input.
- `utils.py`
  Geometry and rotation helper functions used by `gTA-cli.py`.

## Usage

Run the workflow from the repository root:

```bash
bash 2_scripts/run-workflow.sh [options]
```

### Command-line options

- `-m <int>`: number of scan steps, in each scan step we rotate the turnstile by a small angle
- `-a <number>`: rotation angle in degrees for each step
- `-c <int>`: central atom id for the turnstile rotation (1-based)
- `-r <list>`: arm atom ids (1-based) as a comma-separated list, for example `2,3,5` 
- `-q <int>`: molecular charge
- `-u <int>`: number of unpaired electrons
- `-f <expr>`: atom ids (1-based) fixed/constrained during optimization, for example `1,2-4,7-9`
- `-i <path>`: initial XYZ geometry
- `-x <path-or-command>`: `xtb` executable path or command
- `-g <int>`: value passed to `xtb --gfn`
- `-h`: print help

### Example

```bash
cd 2_scripts/
bash ./run-workflow.sh \
  -m 25 \
  -a '-5' \
  -c 1 \
  -r 2,3,5 \
  -q 0 \
  -u 0 \
  -f 2-5 \
  -i 1_inputs/sf4-stable.xyz \
  -x /path/to/xtb \
  -g 2
```

### What the script does

For a typical run, the script will:

1. copy the starting geometry into a workspace,
2. generate local `input.json` and `fix-input-local.txt` from the templates,
3. run a single-point energy calculation for iteration `0`,
4. repeat the rotation + constrained optimization loop for the requested number of iterations,
5. write energy data, per-step snapshots, and an accumulated XYZ trajectory.

## Outputs

The workflow creates a `4_workspace/` directory during execution.

Important output files include:

- `4_workspace/energy_log.csv`
  Energy table with `Iteration`, `Energy(Eh)`, and `Relative Energy (kcal/mol)`.
- `4_workspace/starting_geom.xyz`
  Copy of the initial user-provided structure.
- `4_workspace/scan-traj.xyz`
  Combined multi-frame XYZ trajectory. The first frame is the starting geometry.
- `4_workspace/final_optimized.xyz`
  Final optimized geometry from the last iteration.
- `4_workspace/xtb_sav/I000_xtbopt.out.txt`
  Stdout of the initial single-point calculation.
- `4_workspace/xtb_sav/IXXX_xtbopt.xyz`
  Optimized geometry saved after each iteration.
- `4_workspace/xtb_sav/IXXX_xtbopt.log`
  Native `xtb` log saved after each iteration.
- `4_workspace/xtb_sav/IXXX_xtbopt.out.txt`
  Redirected stdout of each `xtb` optimization step.

## Notes

- Negative angles should be quoted on the command line, for example `-a '-5'`.
- The expected rotated file name is derived automatically from the gTA alias and the chosen angle.
- Relative energies are reported against iteration `0` using a conversion factor of `627.509`.
