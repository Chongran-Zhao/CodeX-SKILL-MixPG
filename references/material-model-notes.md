# Material model, driver, and postprocess notes for viscoelasticity_NURBS_TaylorHood

## Central switchboards

Use:

- `examples/viscoelasticity_NURBS_TaylorHood/include/MaterialModelData.hpp`
- `examples/viscoelasticity_NURBS_TaylorHood/input/creep/paras_driver.yml`

as the main places to change constitutive setup and driver time-stepping.

## Driver defaults

If the user does not specify time-step size or total simulated duration:

- use `initial_time: 0.0`
- use `initial_step: 0.01`
- use `final_time: 1.0`

If the user does not specify processor count:

- use `cpu_size: 6`
- keep preprocessing `cpu_size` and `mpirun -np` identical

Choose the executable by loading type:

- non-displacement-driven case: `./mixed_ga_driver`
- displacement-driven case: `./mixed_ga_driver_disp`

Run the solver with log capture:

```bash
mpirun -np <cpu_size> <driver_executable> | tee driver_log.txt
```

## Postprocess executable names

Use the real built names:

- `./reanalysis_proj_driver`
- `./prepostproc`
- `./vis_3d_mixed`
- `./post_surface_force`
- `./divV_calculator`

Do not keep the older `prepost` name in new instructions.

## Postprocess order

Standard order:

1. `mpirun -np <cpu_size> ./reanalysis_proj_driver -time_end <time_end>`
2. `./prepostproc`
3. chosen downstream tools such as visualization or derived-quantity postprocessing

`reanalysis_proj_driver`, `vis_3d_mixed`, `post_surface_force`, and `divV_calculator` support `-time_end`.

## Current integrated material paths

`MaterialModelData.hpp` already centralizes factories for:

- volumetric incompressibility model
- isochoric elastic model
- EM isochoric elastic model
- Maxwell-type viscoelastic branch model
- EM Maxwell model
- GKV model
- mixed GKV wrapper
- mixed GM wrapper
- mixed EM GM wrapper

## Available candidate headers

The repository `~/MixPERIGEE/include` contains many related models, including:

- `MaterialModel_ich_NeoHookean.hpp`
- `MaterialModel_ich_Ogden.hpp`
- `MaterialModel_ich_em_Ogden.hpp`
- `MaterialModel_ich_Hill.hpp`
- `MaterialModel_ich_AB.hpp`
- `MaterialModel_ich_GOH06.hpp`
- `MaterialModel_ich_GOH14.hpp`
- `MaterialModel_GKV_Hill.hpp`
- `MaterialModel_GKV_AB.hpp`
- `MaterialModel_Mixed_Viscoelasticity_GKV.hpp`
- `MaterialModel_Mixed_Viscoelasticity_GM.hpp`

## Default selection guidance

If the user only says "test model X" and does not specify full parameters:

- prefer a model already close to the current integrated factory style
- preserve density unless asked otherwise
- preserve parameter scale near the current example when possible
- preserve branch count unless the chosen model clearly requires a different one
- choose a minimal compile-safe integration path

## What to report back

When you make default constitutive or driver choices, tell the user:

- which header or model class you selected
- which factory function in `MaterialModelData.hpp` you changed
- which key defaults you assumed
- what driver time-step, final time, and cpu size you used if they were not user-specified
- which driver executable you used
- which postprocess executable names and `time_end` you used
- any likely limitations of that default mapping
