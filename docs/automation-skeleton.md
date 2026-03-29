# MixPG Automation Skeleton

## Scope

This document defines the minimal automation skeleton for MixPG case setup.
At this stage, automation supports the build, preprocess, driver, and
postprocess stages.

The goal of this skeleton is to make later stages easy to add without mixing
planning, filesystem preparation, and execution responsibilities.

## Responsibilities

### Planner

- decide the requested repo root, build directory, input directory, and state file
- decide whether the run should validate an existing build directory or create one
- choose safe flags such as `--clean` only when explicitly requested
- hand a fully resolved plan to the executor without performing side effects

### Executor

- verify required paths exist before doing any file operations
- call the repository build preparation flow through `scripts/prepare_visco_build.sh`
- determine preprocess case type conservatively from the documented YAML rules
- run `./preprocess3d` or `./preprocess3d` then `./preprocess3d_init` as required
- read the recorded preprocess case type from state before selecting a driver
- run the documented driver command with `mpirun -np <cpu_size>`
- run the documented postprocess sequence after successful driver completion
- record build-stage logs and results in the machine-readable state file
- record preprocess-stage logs and results in the machine-readable state file
- record driver-stage logs and results in the machine-readable state file
- record postprocess-stage logs and results in the machine-readable state file
- stop immediately on validation or filesystem errors

### State Tracking

- store the current stage and result of the safe preparation workflow
- record resolved paths used by the executor
- record whether the build directory was created, reused, or cleaned
- record copied input source and destination
- provide a stable handoff point for future build and run stages
- reserve explicit placeholders for future build, preprocess, driver, and postprocess stages
- reserve a failure object even when no failure handling logic is implemented yet

## State Contract

The state file should be machine-readable and stable across later stages.

Minimal required sections:

- top-level metadata: `version`, `workflow`, `current_stage`, `status`
- resolved `paths`
- requested options such as `clean_build`
- `stages` object with one entry per workflow stage
- `failure` object or `null`
- `next_step` hint for the next automation layer

The current executor updates the build stage and records the build-stage log,
but the format should already be able to hold later results from:

- build
- preprocess
- driver
- postprocess

## Current Stage Boundary

Implemented now:

- path validation
- build-stage execution through the repository build preparation script
- build log capture
- preprocess input validation
- conservative case detection from `EBC` and `paras_preprocessor_init.yml`
- preprocess command execution and log capture
- driver selection from recorded preprocess case type
- driver command execution and log capture
- postprocess input validation
- documented postprocess command execution and log capture
- state file writing

Explicitly deferred:

- retry or resume orchestration
- automatic failure recovery

## Guardrails

- the planner must not perform filesystem changes
- the executor must not infer permission for destructive cleanup; `--clean` stays opt-in
- the executor may invoke only the repository build preparation flow for this stage
- the executor may invoke only documented preprocess commands after successful build
- the executor must fail if case type cannot be determined safely from current YAML files
- the executor must fail if driver selection is ambiguous under current documentation
- the executor may invoke only the documented driver command after successful preprocess
- the executor may invoke only the common documented postprocess order shared by the references
- the executor must fail if `time_end` cannot be derived safely from `paras_driver.yml`
- the state file should describe what happened, not invent results for unimplemented stages

## Minimal Usage

Run the executor with explicit paths when needed:

```bash
scripts/mixpg_executor.sh \
  --repo-root ~/MixPERIGEE \
  --build-dir ~/build_MixPG \
  --state-file state/state.json
```

Optional safe cleanup:

```bash
scripts/mixpg_executor.sh --clean
```

The current script now runs build, preprocess, driver, and the minimal
documented postprocess sequence. A successful run means the case reached the
end of the implemented workflow.

## Usage Notes

- the executor writes a build log next to the state file under `logs/build-stage.log`
- the executor writes a preprocess log next to the state file under `logs/preprocess-stage.log`
- the executor writes a driver log next to the state file under `logs/driver-stage.log`
- the executor writes a postprocess log next to the state file under `logs/postprocess-stage.log`
- if the build directory already exists, the run fails unless `--clean` is provided
- on success, the state file marks `build.status` as `completed`
- case detection is conservative:
  traction requires non-empty `EBC` and no init-YAML displacement entry
  displacement requires empty `EBC` and exactly one non-empty init-YAML `Dirichlet_velo_*` block
- the state file also records the build script path, executed command, log file, and exit code
- for preprocess, the state file records case type, detection reason, commands, log file, resolved `geo_file_base`, and exit codes
- driver selection uses the already recorded `preprocess.case_type` from state instead of re-detecting case type
- traction uses `./mixed_ga_driver`
- displacement is only accepted when exactly one documented executable is present: `./mixed_ga_driver_displacement` or `./mixed_ga_driver_disp`
- for driver, the state file records the selected executable, `cpu_size`, command, log file, and exit code
- postprocess uses the conservative shared sequence from the references:
  `mpirun -np <cpu_size> ./reanalysis_proj_driver -time_end <time_end>`
  then `./prepostproc`
- optional or conditional downstream tools such as `post_surface_force` and `vis_3d_mixed` are not auto-run in this step
- for postprocess, the state file records the chosen sequence, `cpu_size`, derived `time_end`, log file, and exit codes
- on failure, the state file records the exit code and log file path under `failure`
