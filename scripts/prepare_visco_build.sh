#!/usr/bin/env bash
set -euo pipefail

home_dir="${HOME}"
repo_root="${home_dir}/MixPERIGEE"
build_dir="${home_dir}/build_MixPG"
example_dir="${repo_root}/examples/viscoelasticity_NURBS_TaylorHood"
config_file="${repo_root}/conf/system_lib_loading.cmake"
input_dir="${example_dir}/input/creep"
clean_build="false"

usage() {
  cat <<'EOF'
Usage:
  prepare_visco_build.sh [--repo-root DIR] [--build-dir DIR] [--clean]

Options:
  --repo-root DIR   MixPERIGEE repository root (default: ~/MixPERIGEE)
  --build-dir DIR   Build directory (default: ~/build_MixPG)
  --clean           Clear existing build directory contents before configuring
  --help            Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="$2"
      example_dir="${repo_root}/examples/viscoelasticity_NURBS_TaylorHood"
      config_file="${repo_root}/conf/system_lib_loading.cmake"
      input_dir="${example_dir}/input/creep"
      shift 2
      ;;
    --build-dir)
      build_dir="$2"
      shift 2
      ;;
    --clean)
      clean_build="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "$config_file" ]]; then
  echo "Required config file not found: $config_file" >&2
  exit 1
fi

if [[ ! -d "$example_dir" ]]; then
  echo "Example directory not found: $example_dir" >&2
  exit 1
fi

if [[ ! -d "$input_dir" ]]; then
  echo "Input directory not found: $input_dir" >&2
  exit 1
fi

if [[ -d "$build_dir" ]]; then
  if [[ "$clean_build" == "true" ]]; then
    find "$build_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  else
    echo "Build directory already exists: $build_dir" >&2
    echo "Re-run with --clean if you want to clear it before configuring." >&2
    exit 2
  fi
else
  mkdir -p "$build_dir"
fi

echo "[mixpg] config file: $config_file"
echo "[mixpg] example dir: $example_dir"
echo "[mixpg] build dir: $build_dir"
echo "[mixpg] input dir: $input_dir"

cd "$build_dir"
cmake "$example_dir" -DCMAKE_BUILD_TYPE=Release

if ! make -j; then
  echo "[mixpg] build failed during make -j" >&2
  exit 3
fi

cp -R "$input_dir"/. "$build_dir"/
