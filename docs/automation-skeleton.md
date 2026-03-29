# MixPG Automation Skeleton

## Scope

This document defines the minimal automation skeleton for MixPG case setup.
At this stage, automation only covers safe preparation tasks and explicitly
does not run build, preprocess, solver, or postprocess commands.

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
- prepare the build directory conservatively
- copy required example input files into the build directory
- write or update the machine-readable state file
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

The current executor only updates the safe preparation stage, but the format
should already be able to hold later results from:

- build
- preprocess
- driver
- postprocess

## Current Stage Boundary

Implemented now:

- path validation
- build directory preparation
- input staging
- state file writing

Explicitly deferred:

- CMake or build
- preprocess executables
- driver execution
- postprocess execution
- retry or resume orchestration
- automatic failure recovery

## Guardrails

- the planner must not perform filesystem changes
- the executor must not infer permission for destructive cleanup; `--clean` stays opt-in
- the executor must not invoke CMake, MPI, preprocessors, drivers, or postprocess tools
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

The current script is only a safe preparation step. A successful run means the
build directory is ready for later stages, not that MixPG has been built or run.
