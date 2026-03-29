# gTA-workflow

This repository contains two main parts related to generalized turnstile rotations.

## Part 1: `gTA-cli`

[`gTA-cli`](./gTA-cli/README.md) is the core rotation tool in this repository.

It reads a JSON configuration, identifies one or more turnstiles, applies the requested generalized turnstile-angle rotations, and writes rotated structures as XYZ files.

Documentation:

- English: [`gTA-cli/README.md`](./gTA-cli/README.md)
- 中文: [`gTA-cli/README_zh.md`](./gTA-cli/README_zh.md)

## Part 2: Workflow Examples Built On `gTA-cli`

The repository also contains two example iterative scan-and-optimization workflows built on top of `gTA-cli`.

### ORCA-Based Workflow

[`gTA-orca-workflow`](./gTA-orca-workflow/sf4/README.md) shows how to combine `gTA-cli` with constrained ORCA geometry optimization in an iterative scan workflow.

Documentation:

- English: [`gTA-orca-workflow/sf4/README.md`](./gTA-orca-workflow/sf4/README.md)
- 中文: [`gTA-orca-workflow/sf4/README_zh.md`](./gTA-orca-workflow/sf4/README_zh.md)

### xTB-Based Workflow

[`gTA-xtb-workflow`](./gTA-xtb-workflow/sf4/README.md) shows how to combine `gTA-cli` with constrained `xtb` optimization in an iterative scan workflow.

Documentation:

- English: [`gTA-xtb-workflow/sf4/README.md`](./gTA-xtb-workflow/sf4/README.md)
- 中文: [`gTA-xtb-workflow/sf4/README_zh.md`](./gTA-xtb-workflow/sf4/README_zh.md)

## Repository Structure

- `gTA-cli/`: standalone rotation tool and examples
- `gTA-orca-workflow/`: ORCA-based iterative workflow example
- `gTA-xtb-workflow/`: xTB-based iterative workflow example

## Suggested Reading Order

1. Start with [`gTA-cli/README.md`](./gTA-cli/README.md) to understand the rotation tool itself.
2. Then read either workflow README depending on your target engine:
   [`gTA-orca-workflow/sf4/README.md`](./gTA-orca-workflow/sf4/README.md) or
   [`gTA-xtb-workflow/sf4/README.md`](./gTA-xtb-workflow/sf4/README.md).


## Reference

 *Generalized Turnstile Rotation: Formulation, Visualization, Workflow Implementation, and Application for Modeling Polytopal Rearrangements.* ChemRxiv. 15 February 2026. DOI: https://doi.org/10.26434/chemrxiv.15000069/v1
