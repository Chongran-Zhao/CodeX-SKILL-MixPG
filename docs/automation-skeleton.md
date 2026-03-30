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
- requested options such as `clean_build`, `start_from`, `retry_stage`, and `mpi_launcher`
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

- automatic failure recovery

## Guardrails

- the planner must not perform filesystem changes
- the executor must not infer permission for destructive cleanup; `--clean` stays opt-in
- the executor may invoke only the repository build preparation flow for this stage
- the executor may invoke only documented preprocess commands after successful build
- the executor must fail if case type cannot be determined safely from current YAML files
- the executor must reject absolute `geo_file_base` values when they are unsafe under the documented HOME-prefix preprocess behavior
- the executor must fail if driver selection is ambiguous under current documentation
- the executor may invoke only the documented driver command after successful preprocess
- the executor may invoke only the common documented postprocess order shared by the references
- the executor must fail if `time_end` cannot be derived safely from `paras_driver.yml`
- later-stage resume must be explicit through `--start-from`
- later-stage resume must be rejected unless recorded state and basic artifacts establish a complete dependency chain
- retry must remain explicit, bounded, and stage-level
- retry must reuse the existing rerun/resume path instead of inventing a separate execution flow
- MPI launcher selection must not rely on whichever `mpirun` or `mpiexec` appears first in `PATH`
- driver and MPI-using postprocess stages must use either an explicitly configured launcher or a launcher derived from the executable's linked MPI installation
- if the launcher path and linked MPI installation do not match, the workflow must fail clearly
- the state file should describe what happened, not invent results for unimplemented stages
- the current executor is intentionally still a single script, but stage-local helpers should keep shared failure and logging behavior consistent until a later retry/resume refactor

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

Explicit conservative resume:

```bash
scripts/mixpg_executor.sh --start-from preprocess
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
- before preprocess, the executor removes only known generated preprocess and partition artifacts so they are regenerated consistently
- driver selection uses the already recorded `preprocess.case_type` from state instead of re-detecting case type
- traction uses `./mixed_ga_driver`
- displacement is only accepted when exactly one documented executable is present: `./mixed_ga_driver_displacement` or `./mixed_ga_driver_disp`
- for driver, the state file records the selected executable, `cpu_size`, explicit MPI launcher choice, linked MPI installation, command, log file, and exit code
- postprocess uses the conservative shared sequence from the references:
  `mpirun -np <cpu_size> ./reanalysis_proj_driver -time_end <time_end>`
  then `./prepostproc`
- optional or conditional downstream tools such as `post_surface_force` and `vis_3d_mixed` are not auto-run in this step
- for postprocess, the state file records the chosen sequence, `cpu_size`, derived `time_end`, explicit MPI launcher choice, linked MPI installation, log file, and exit codes
- on failure, the state file records the exit code and log file path under `failure`
- the current script is already fairly long, so maintenance should prefer small shared helpers and stage-local functions instead of adding more inline branching

## Preprocess Guardrails

- `geo_file_base` is treated conservatively because the documented preprocessor behavior may prepend `HOME`
- relative `geo_file_base` values are resolved under the build directory and must satisfy `geo_file_base + "0.yml"`
- absolute `geo_file_base` values are rejected with a clear failure instead of proceeding unsafely

## Targeted Preprocess Cleanup

Before preprocess, the executor removes only known generated files that are safe
to regenerate:

- `patch*.yml`
- `epart.h5`
- `npart.h5`
- `node_mapping.h5`
- `node_mapping_p.h5`
- `node_mapping_v.h5`
- `part_p*.h5`
- `epart_init.h5`
- `npart_init.h5`
- `part_init_p*.h5`

These files are cleaned because they are generated preprocess or partition
artifacts. The executor does not remove source files, YAML inputs, compiled
executables, solver outputs, or the whole build directory unless `--clean` is
explicitly requested for the build stage.

## Resume Contract

Allowed paths:

- default run or `--start-from build`: rerun from the beginning
- `--start-from safe_prepare`: treated as a rerun from the beginning
- `--start-from preprocess`: allowed only if build is recorded as completed and preprocess artifacts still exist
- `--start-from driver`: allowed only if build and preprocess are recorded as completed and required input files still exist
- `--start-from postprocess`: allowed only if build, preprocess, and driver are recorded as completed and required postprocess executables still exist

Rejected paths:

- any later-stage resume without an existing state file
- any later-stage resume when required predecessor stages are not recorded as `completed`
- any later-stage resume when required inputs or executables are missing
- any ambiguous or unsupported `--start-from` value

The executor records both the resume intent and the effective decision in the state file under `resume`.
The original user request is also preserved under `requested.start_from`.

## Retry Contract

Implemented conservative retry policy:

- `build`: supported with at most one retry beyond the first attempt

Not implemented as automatic retry:

- `preprocess`
- `driver`
- `postprocess`

Build retry is allowed only when all of the following are true:

- the user explicitly requests `--retry-stage build`
- the previous state records `build.status` as `failed`
- the previous state records `safe_prepare.build_dir_action` as `blocked_existing_dir`
- the current request explicitly includes `--clean`
- the blocked build directory still exists
- the recorded build attempt count is still below the configured maximum

This means the only supported automatic retry case is the operational case where
the earlier build was blocked because the build directory already existed, and
the retry is now meaningfully different because the user explicitly approved
cleanup with `--clean`.

Rejected retry cases:

- any retry request for `preprocess`, `driver`, or `postprocess`
- any retry without a prior state file
- any retry after the configured maximum attempts has been reached
- any retry that would repeat the same blocked build action without `--clean`
- any retry for build failures that are not the blocked-existing-directory case

Retry intent, policy, and decision are recorded under `retry` in the state
file, while the original retry request is preserved under `requested.retry_stage`
and per-stage attempt counters are stored with each stage record.

## MPI Launcher Rule

The workflow now treats MPI launcher choice as an explicit safety decision.

- If `--mpi-launcher PATH` is provided, that exact launcher is used only if it matches the MPI installation linked by the target executable.
- If no launcher is configured, the workflow derives a launcher from the linked MPI installation prefix, for example `<linked-prefix>/bin/mpirun`.
- The workflow must not proceed with a launcher from a different MPI prefix, even if that launcher is first in `PATH`.
