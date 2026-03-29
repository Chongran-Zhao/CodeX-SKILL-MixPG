# MixPG Automation Skeleton

## Scope

This document defines the minimal automation skeleton for MixPG case setup.
At this stage, automation only covers safe preparation tasks and explicitly
does not run build, preprocess, solver, or postprocess commands.

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
