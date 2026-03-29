# MixPERIGEE build and mixed-case notes

## Required config file

The viscoelasticity example CMake file includes:

- `../../conf/basic_variable_log.cmake`
- `../../conf/system_lib_loading.cmake`

That means the user-specific dependency configuration file
`~/MixPERIGEE/conf/system_lib_loading.cmake` must exist before configuration can succeed.

## Example source directory

The requested configure target is:

- `~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood`

This example builds drivers such as:

- `preprocess3d`
- `preprocess3d_init`
- `mixed_ga_driver`
- `reanalysis_proj_driver`
- `prepostproc`
- `vis_3d_mixed`

## Build directory convention

The user's requested build directory is:

- `~/build_MixPG`

Treat that as an out-of-source build tree. If it already exists, cleaning it is destructive and should be confirmed before execution.

## Post-build staging

After a successful build, copy the contents of:

- `~/MixPERIGEE/examples/viscoelasticity_NURBS_TaylorHood/input/creep`

into `~/build_MixPG` so the executables can read the case files from the current working directory.
