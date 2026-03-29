#!/usr/bin/env bash
set -euo pipefail

repo_root="${HOME}/MixPERIGEE"
build_dir="${HOME}/build_MixPG"
state_file="state/state.json"
clean_build="false"

example_dir=""
config_file=""
input_dir=""
build_action="unknown"
copy_status="pending"

usage() {
  cat <<'EOF'
Usage:
  mixpg_executor.sh [--repo-root DIR] [--build-dir DIR] [--state-file FILE] [--clean]

Safe tasks only:
  - verify required paths
  - prepare or validate the build directory
  - copy required input files
  - write/update a state file
EOF
}

resolve_paths() {
  example_dir="${repo_root}/examples/viscoelasticity_NURBS_TaylorHood"
  config_file="${repo_root}/conf/system_lib_loading.cmake"
  input_dir="${example_dir}/input/creep"
}

write_state() {
  local state_dir
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir"

  cat > "$state_file" <<EOF
{
  "version": 1,
  "workflow": "mixpg-safe-prepare",
  "stage": "executor_safe_prepare",
  "status": "ready",
  "paths": {
    "repo_root": "$repo_root",
    "example_dir": "$example_dir",
    "config_file": "$config_file",
    "input_dir": "$input_dir",
    "build_dir": "$build_dir"
  },
  "actions": {
    "build_dir": "$build_action",
    "input_copy": "$copy_status"
  }
}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      repo_root="$2"
      shift 2
      ;;
    --build-dir)
      build_dir="$2"
      shift 2
      ;;
    --state-file)
      state_file="$2"
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

resolve_paths

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
    build_action="cleaned"
  else
    build_action="reused"
  fi
else
  mkdir -p "$build_dir"
  build_action="created"
fi

cp -R "$input_dir"/. "$build_dir"/
copy_status="copied"

write_state

echo "[mixpg] safe prepare complete"
echo "[mixpg] state file: $state_file"
