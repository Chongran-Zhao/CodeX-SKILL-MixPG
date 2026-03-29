---
name: mixpg-case-runner
description: Prepare and run MixPERIGEE or MixPG viscoelasticity example builds and executions. Use this skill whenever the user wants to automate MixPG setup on their machine, verify `MixPERIGEE/conf/system_lib_loading.cmake`, recreate `~/build_MixPG`, run CMake for `examples/viscoelasticity_NURBS_TaylorHood`, compile with `make -j`, stage the `input/creep` files into the build directory, or edit `paras_preprocessor.yml`, `paras_preprocessor_init.yml`, `paras_driver.yml`, `LoadData.hpp`, and `MaterialModelData.hpp` for mesh, loading, time stepping, constitutive-model setup, MPI driver execution, and postprocessing.
---

# MixPG Case Runner

Use this skill as a task-friendly execution guide. Do not simulate a separate product-level task system inside the skill. Instead:

- keep progress updates short
- use simple stage labels
- make checkpoints explicit
- stop immediately on blocking failures

Good progress labels:

- `Build Setup`
- `Input Setup`
- `Material And Load Setup`
- `Preprocess`
- `Driver`
- `Postprocess`

At each checkpoint, briefly report:

- what changed
- what command ran
- what files or outputs now exist
- what the next step is

## Core Defaults

Use these defaults unless the user overrides them:

- `cpu_size: 6`
- `initial_time: 0.0`
- `initial_step: 0.01`
- `final_time: 1.0`
- default constitutive model: keep the currently integrated model in `MaterialModelData.hpp`

Compute postprocess step index with:

`time_end = (final_time - initial_time) / initial_step`

Example:

- `initial_time = 0.0`
- `initial_step = 0.01`
- `final_time = 1.0`
- therefore `time_end = 100`

If this is not an integer, stop and ask the user to reconcile `final_time` and `initial_step`.

## Build Setup

Check:

- `~/MixPERIGEE/conf/system_lib_loading.cmake`
- `~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood`
- `~/build_MixPG`

Build flow:

```bash
cmake ~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood -DCMAKE_BUILD_TYPE=Release
make -j
cp -R ~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood/input/creep/. ~/build_MixPG/
```

Rules:

- if `~/build_MixPG` exists, do not silently clear it
- ask before destructive cleanup
- stop on CMake or compile errors
- warnings are allowed but should be summarized

## Input Setup

Files you may need to edit:

- `paras_preprocessor.yml`
- `paras_preprocessor_init.yml`
- `paras_driver.yml`
- `LoadData.hpp`
- `MaterialModelData.hpp`

### Geometry path rule

`geo_file_base` is sensitive and must be validated before preprocessing.

Rules:

- if the user gives an absolute path, use it exactly as given
- do not prepend `HOME` or any other root to an absolute path
- if the user gives a relative path, resolve it explicitly and report the resolved absolute path
- before running preprocessing, verify that `geo_file_base + "0.yml"` exists

Example:

- correct base: `/Users/chongran/build_MixPG/patch`
- expected file: [`/Users/chongran/build_MixPG/patch0.yml`](/Users/chongran/build_MixPG/patch0.yml)

Do not generate broken paths like:

- `/Users/chongran/Users/chongran/build_MixPG/patch0.yml`

### Mesh rule

For single-patch cases:

- `num_inserted_x: [n]` means `n + 1` elements in x
- `num_inserted_y: [n]` means `n + 1` elements in y
- `num_inserted_z: [n]` means `n + 1` elements in z

### Boundary rule

- `Dirichlet_velo_x`, `Dirichlet_velo_y`, `Dirichlet_velo_z` define displacement constraints by direction and face
- `EBC` defines traction faces only

### Loading mode rule

Pick exactly one primary loading mode unless the user explicitly asks for coupling:

- traction
- displacement
- body force
- initial velocity

Keep unrelated loads at zero in `LoadData.hpp`.

### Traction rule

If traction loading:

- edit only `paras_preprocessor.yml`
- do not edit `paras_preprocessor_init.yml`
- put the loaded face in `EBC`
- encode the actual traction vector and time law in `surface_traction(...)`
- later run `preprocess3d` only

### Displacement rule

If displacement loading:

- edit `paras_preprocessor.yml`
- edit `paras_preprocessor_init.yml`
- edit `examples/viscoelasticity_NURBS_TaylorHood/src/PNonlinear_Solver.cpp` if the loaded direction changes
- in `paras_preprocessor.yml`, keep the full runtime boundary setup
- in `paras_preprocessor_init.yml`, keep only the unique loaded direction-face entry
- encode the displacement time law in `disp_loading(...)`
- encode its derivative in `velo_loading(...)`
- in `PNonlinear_Solver.cpp`, make sure the imposed basis vector matches the requested direction:
  use `base_x` for x displacement, `base_y` for y displacement, and `base_z` for z displacement
- if the case is uniaxial displacement tension, constrain the other two directions on the loaded face to zero in `paras_preprocessor.yml`
- later run `preprocess3d` then `preprocess3d_init`

Example for bottom fixed, top z displacement:

`paras_preprocessor.yml`

```yml
Dirichlet_velo_x:
  0: [ 0, bot ]

Dirichlet_velo_y:
  0: [ 0, bot ]

Dirichlet_velo_z:
  0: [ 0, bot ]
  1: [ 0, top ]
```

`paras_preprocessor_init.yml`

```yml
Dirichlet_velo_x:

Dirichlet_velo_y:

Dirichlet_velo_z:
  0: [ 0, top ]
```

For uniaxial z-tension on the top face, the runtime file should also lock the other two directions on the top face:

```yml
Dirichlet_velo_x:
  0: [ 0, bot ]
  1: [ 0, top ]

Dirichlet_velo_y:
  0: [ 0, bot ]
  1: [ 0, top ]

Dirichlet_velo_z:
  0: [ 0, bot ]
  1: [ 0, top ]
```

## Material And Load Setup

Use:

- `examples/viscoelasticity_NURBS_TaylorHood/include/MaterialModelData.hpp`
- `examples/viscoelasticity_NURBS_TaylorHood/include/LoadData.hpp`

Material rule:

- if the user only names a model, search `~/MixPERIGEE/include`
- choose the closest compatible model already supported by the current factory structure
- preserve current parameter scale unless the user asks otherwise
- report the defaults you assumed

Load rule:

- traction case: make `surface_traction(...)` nonzero and keep other load modes zero
- displacement case: make `disp_loading(...)` and `velo_loading(...)` nonzero and keep other load modes zero
- body-force case: make `body_force(...)` nonzero and keep other load modes zero

Consistency checks:

- displacement-loaded face must not also appear in `EBC`
- traction-loaded face must be declared in `EBC`
- requested displacement direction must match the edited `Dirichlet_velo_*` block
- requested displacement direction must also match the `base_*` vector used in `PNonlinear_Solver.cpp`
- for uniaxial displacement tension, the loaded face must also be constrained to zero in the other two directions
- requested load duration must match the time law and `paras_driver.yml`

## Driver Time Setup

Use `paras_driver.yml` to control physical time:

- `initial_time`
- `initial_step`
- `final_time`

Default if unspecified:

```yml
initial_time: 0.0
initial_step: 0.01
final_time: 1.0
```

Do not accidentally keep sample defaults such as `0.1` and `200.0`.

Check:

- `initial_step > 0`
- `initial_time <= final_time`
- computed `time_end` is integral

## Preprocess

Use the same `cpu_size` everywhere. Default is `6`.

Rules:

- if traction loading:
  run `./preprocess3d`
- if displacement loading:
  run `./preprocess3d`
  then run `./preprocess3d_init`

Before running, make sure:

- `geo_file_base` resolves to a valid file base on the current machine
- `cpu_size` in the preprocessor file matches the intended MPI size

## Driver

Choose the executable by loading type:

- non-displacement-driven case: `./mixed_ga_driver`
- displacement-driven case: `./mixed_ga_driver_displacement`

Run with:

```bash
mpirun -np <cpu_size> <driver_executable> | tee driver_log.txt
```

Rules:

- `-np` must match preprocessor `cpu_size`
- default `cpu_size` is `6`
- always save output to `driver_log.txt`

## Postprocess

Use the actual built names:

- `./reanalysis_proj_driver`
- `./prepostproc`
- `./vis_3d_mixed`
- `./post_surface_force`
- `./divV_calculator`

Standard order:

1. `mpirun -np <cpu_size> ./reanalysis_proj_driver -time_end <time_end>`
2. `mpirun -np <cpu_size> ./post_surface_force`
3. `./prepostproc`
4. whichever downstream tool the user wants, for example:
   `mpirun -np <cpu_size> ./vis_3d_mixed -time_end <time_end>`

Rules:

- the driver and all postprocess executables have strict data dependencies and must be run serially
- do not start `reanalysis_proj_driver`, `post_surface_force`, `prepostproc`, or `vis_3d_mixed` before the driver has finished successfully
- do not run postprocess executables in parallel with each other
- `reanalysis_proj_driver` must use the same MPI size as preprocessing and driver
- `post_surface_force` should be run before `vis_3d_mixed`
- use `prepostproc`, not the old `prepost` name
- `-time_end` is a step index, not physical time
- before running `vis_3d_mixed`, update `paras_pos_vis.yml` so `time_start`, `time_step`, and `time_end` match the finished run

### Surface-force postprocess rule

If `post_surface_force` is requested or part of the default postprocess chain:

- edit `examples/viscoelasticity_NURBS_TaylorHood/post_surface_traction.cpp`
- update `target_surface_list.emplace_back(...)` so the selected patch id and face match the current loading boundary condition
- if the case uses multiple loaded faces or patches, add one entry per target surface
- update the output record so the reported displacement and force components match the loaded direction
- synchronize the post-surface-force time range with the finished run so it processes the full intended index range, for example `time_end = 100` for `1.0 / 0.01`

Direction mapping for the output record:

- x loading: write `sum_dispx/sum_area` and `sum_Fx/sum_area`
- y loading: write `sum_dispy/sum_area` and `sum_Fy/sum_area`
- z loading: write `sum_dispz/sum_area` and `sum_Fz/sum_area`

Consistency checks:

- the target face in `post_surface_traction.cpp` must match the traction or displacement loading face
- the recorded component in `Force_disp_record.txt` must match the requested loading direction
- the time range used by `post_surface_force` must match the computed run range instead of stopping at the example default

## Failure Policy

Stop immediately and explain the issue if you see any of these:

- bad geometry path expansion
- non-integral `time_end`
- inconsistent `cpu_size`
- compile errors
- load setup contradicts YAML boundary setup
- requested driver executable does not match loading type

## References

Read these only when needed:

- `references/mixperigee-mixed-workflows.md`
- `references/preprocessor-yaml-rules.md`
- `references/material-model-notes.md`
