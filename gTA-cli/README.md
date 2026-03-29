# gTA-cli

[中文文档](./README_zh.md)

`gTA-cli` is a small command-line tool for applying generalized turnstile-angle rotations to molecular geometries and exporting the resulting structures as XYZ files.

It supports:

- `SDF` input, with connectivity-aware fragment selection through `RDKit`
- `XYZ` input, with explicit atom selection for first-coordination-sphere rotations
- single transformation scans over multiple angles
- multiple transformation groups with Cartesian-product combination generation

## Dependency

The code is written for Python 3 and depends on:

- `numpy`
- `scipy`
- `rdkit`

Practical note:

- `numpy` is required for all modes.
- `scipy` is required for the circle-center optimization step.
- `rdkit` is required when using `input_sdf`.
- If you only use `input_xyz` together with `first_coord_sphere_only = true`, the practical Python requirements are `numpy` and `scipy`.

Example installation:

```bash
pip install numpy scipy
```

For `rdkit`, use a package source appropriate for your environment, for example `conda-forge`.

## Repository Layout

- `code/gTA-cli.py`: main CLI entry point
- `code/utils.py`: geometry, rotation, and connectivity utilities
- `examples/g1/`: single-transformation/turnstile example using `SDF`
- `examples/g2/`: multi-transformation/turnstile example using `XYZ`

## How To Run

Run the script by passing a JSON configuration file:

```bash
python3 code/gTA-cli.py path/to/input.json
```

If no argument is provided, the script falls back to its internal default path. In practice, you should pass the JSON file explicitly.

Example from the `gTA-cli/` directory:

```bash
python3 code/gTA-cli.py examples/g1/g1-babel-1.json
python3 code/gTA-cli.py examples/g2/g2-co-2.json
```

## What The Script Does

For each transformation definition, `gTA-cli`:

1. reads the input structure from `SDF` or `XYZ`
2. extracts the `anchor_atom` and `arm_atoms`
3. computes a rotation axis from the anchor point and an optimized circle center
4. selects the atoms to rotate
5. rotates the selected atoms by the requested angle or angles
6. writes one or more output XYZ files

For multiple transformation groups (i.e. turnstiles), the tool generates all angle combinations across groups and writes one XYZ file per combination. In other words, this tool can rotate multiple turnstiles simultaneously.

## JSON Configuration

The input file is a JSON object with top-level settings plus a `transformations` list collecting all turnstiles that need to be rotated.

### Top-Level Fields

- `input_sdf`: path to an SDF file, relative to the JSON file location
- `input_xyz`: path to an XYZ file, relative to the JSON file location
- `index_start_from`: atom index convention, usually `1`
- `first_coord_sphere_only`: optional boolean, whether or not to rotate the first coordination sphere atoms only, default `false`
- `transformations`: list of transformation objects (i.e. turnstiles)

Rules:

- You must provide exactly one of `input_sdf` or `input_xyz`.
- If `input_xyz` is used, `first_coord_sphere_only` must be `true`.
- Paths are resolved relative to the JSON file directory, not the current shell directory.

### Transformation Object

Each item in `transformations` must contain:

- `alias`: short name used in output filenames
- `anchor_atom`: central atom index
- `arm_atoms`: list of arm atom indices
- `angle`: list of rotation angles in degrees

### Example: SDF Mode

```json
{
  "input_sdf": "g1-babel.sdf",
  "index_start_from": 1,
  "transformations": [
    {
      "alias": "arm_1",
      "anchor_atom": 1,
      "arm_atoms": [2, 5],
      "angle": [20]
    }
  ]
}
```

### Example: XYZ Mode

```json
{
  "input_xyz": "g2-co.xyz",
  "index_start_from": 1,
  "first_coord_sphere_only": true,
  "transformations": [
    {
      "alias": "arm_x",
      "anchor_atom": 1,
      "arm_atoms": [3, 4],
      "angle": [10, 20, 30]
    },
    {
      "alias": "arm_y",
      "anchor_atom": 1,
      "arm_atoms": [2, 7],
      "angle": [10, 20, 30]
    }
  ]
}
```

## Atom Selection Behavior

The rotated atom set depends on the input mode.

### SDF Mode

When `input_sdf` is used and `first_coord_sphere_only` is `false`, the script:

- builds a molecular adjacency matrix with `RDKit`
- breaks the bonds between `anchor_atom` and each atom in `arm_atoms`
- finds the connected fragment starting from the arm atoms
- rotates that whole fragment

This is the connectivity-aware mode.

### XYZ Mode

When `input_xyz` is used, the script cannot infer bonding. In that case:

- `first_coord_sphere_only` must be `true`
- only the atoms listed in `arm_atoms` are rotated

## Single vs Multiple Transformations

If the JSON contains one transformation group:

- the script writes one XYZ file per angle in that group

If the JSON contains multiple transformation groups:

- the script generates the Cartesian product of all angle lists
- the script writes one XYZ file for each full combination
- the script also generates per-group debug outputs

## Output Files

Outputs are created in a directory next to the input structure:

- main output directory: `<input_stem>/`
- debug directory: `<input_stem>/debug/`

Typical filenames:

- single transformation: `<input_stem>_<alias>_<angle>deg.xyz`
- multiple transformations: `<input_stem>_<alias1>_<angle1>deg_<alias2>_<angle2>deg.xyz`

The debug directory may contain helper XYZ files used to inspect the derived circle center and reference geometry.

## Validation Rules

The script validates several common configuration errors before processing:

- missing input file
- using both `input_sdf` and `input_xyz`
- using neither `input_sdf` nor `input_xyz`
- invalid extension for the declared input type
- duplicate transformation aliases
- overlapping rotated fragments across transformation groups in connectivity-aware SDF mode

## Notes And Limitations

- Atom indices can be interpreted as 1-based or 0-based through `index_start_from`, but current examples use `1`.
- `XYZ` mode is intentionally restricted because plain XYZ files do not contain bonding information.
- The main script imports `RDKit` at module import time, so environments without `rdkit` may still fail even if you intend to run XYZ-only inputs. If you want strict optional dependency behavior, that should be refactored in code.
- The tool is currently a script-based utility, not a packaged Python module with an installer.
