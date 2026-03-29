#!/usr/bin/env bash
set -euo pipefail

repo_root="${HOME}/MixPERIGEE"
build_dir="${HOME}/build_MixPG"
state_file="state/state.json"
clean_build="false"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_script="${script_dir}/prepare_visco_build.sh"
log_dir=""
build_log=""
preprocess_log=""
driver_log=""
postprocess_log=""

example_dir=""
config_file=""
input_dir=""
preprocessor_file=""
preprocessor_init_file=""
driver_file="${build_dir}/paras_driver.yml"
build_dir_action="unknown"
input_copy_status="pending"
build_status="not_started"
build_exit_code="null"
preprocess_status="not_started"
preprocess_case_type="unknown"
preprocess_reason="not_determined"
preprocess_command_display="[]"
preprocess_exit_codes_json="[]"
preprocess_geo_file_base=""
preprocess_geo_file_resolved=""
preprocess_runtime_yaml_present="false"
preprocess_init_yaml_present="false"
driver_status="not_started"
driver_case_type="unknown"
driver_reason="not_determined"
driver_executable=""
driver_command_display=""
driver_exit_code="null"
driver_cpu_size="unknown"
driver_file_present="false"
postprocess_status="not_started"
postprocess_reason="not_determined"
postprocess_cpu_size="unknown"
postprocess_time_end="unknown"
postprocess_command_display="[]"
postprocess_exit_codes_json="[]"
top_level_status="pending"
next_step="build_pending"
failure_json="null"
build_dir_exists_before="false"
build_command_display=""
current_stage="build"

usage() {
  cat <<'EOF'
Usage:
  mixpg_executor.sh [--repo-root DIR] [--build-dir DIR] [--state-file FILE] [--clean]

Implemented stages:
  - build
  - preprocess
  - driver
  - postprocess

Build/preprocess/driver/postprocess tasks only:
  - validate build prerequisites
  - run the repository build preparation flow
  - detect preprocess case type conservatively
  - run the required preprocess command(s)
  - read the recorded preprocess case type from state
  - run the required driver command
  - run the documented postprocess command sequence
  - write/update a state file
  - capture stage logs

Guardrails:
  - only build, preprocess, driver, and postprocess-stage support are implemented
  - only removes build directory contents when --clean is explicitly provided
EOF
}

resolve_paths() {
  example_dir="${repo_root}/examples/viscoelasticity_NURBS_TaylorHood"
  config_file="${repo_root}/conf/system_lib_loading.cmake"
  input_dir="${example_dir}/input/creep"
  preprocessor_file="${build_dir}/paras_preprocessor.yml"
  preprocessor_init_file="${build_dir}/paras_preprocessor_init.yml"
  driver_file="${build_dir}/paras_driver.yml"
  log_dir="$(dirname "$state_file")/logs"
  build_log="${log_dir}/build-stage.log"
  preprocess_log="${log_dir}/preprocess-stage.log"
  driver_log="${log_dir}/driver-stage.log"
  postprocess_log="${log_dir}/postprocess-stage.log"
}

json_bool() {
  if [[ "$1" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

record_failure() {
  local stage="$current_stage"
  local log_file="$build_log"
  local message="$1"
  local exit_code="$2"
  if [[ "$stage" == "preprocess" ]]; then
    log_file="$preprocess_log"
  elif [[ "$stage" == "driver" ]]; then
    log_file="$driver_log"
  elif [[ "$stage" == "postprocess" ]]; then
    log_file="$postprocess_log"
  fi
  failure_json=$(cat <<EOF
{
  "stage": "$stage",
  "message": "$message",
  "exit_code": $exit_code,
  "log_file": "$log_file"
}
EOF
)
}

set_stage_failed() {
  local stage="$1"
  case "$stage" in
    build)
      build_status="failed"
      ;;
    preprocess)
      preprocess_status="failed"
      ;;
    driver)
      driver_status="failed"
      ;;
    postprocess)
      postprocess_status="failed"
      ;;
  esac
  top_level_status="failed"
}

fail_and_exit() {
  local stage="$1"
  local message="$2"
  local exit_code="$3"
  local next="$4"
  current_stage="$stage"
  set_stage_failed "$stage"
  next_step="$next"
  record_failure "$message" "$exit_code"
  write_state
  exit 1
}

json_array_from_values() {
  if [[ "$#" -eq 0 ]]; then
    echo "[]"
    return 0
  fi

  local result="["
  local value
  for value in "$@"; do
    result="${result}${value}, "
  done
  result="${result%, }]"
  echo "$result"
}

extract_state_string() {
  local stage="$1"
  local key="$2"
  awk -v stage="$stage" -v key="$key" '
    $0 ~ "^[[:space:]]*\"" stage "\":[[:space:]]*\\{" {
      instage=1
      next
    }
    instage && $0 ~ "^[[:space:]]*}" {
      instage=0
    }
    instage && $0 ~ "^[[:space:]]*\"" key "\":" {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      sub(/,[[:space:]]*$/, "", $0)
      gsub(/^"/, "", $0)
      gsub(/"$/, "", $0)
      print $0
      exit
    }
  ' "$state_file"
}

validate_prerequisites() {
  if [[ ! -x "$build_script" ]]; then
    echo "Build script is missing or not executable: $build_script" >&2
    fail_and_exit "build" "build script is missing or not executable" 1 "inspect_build_log"
  fi

  if ! command -v cmake >/dev/null 2>&1; then
    echo "Required command not found: cmake" >&2
    fail_and_exit "build" "required command not found: cmake" 1 "inspect_build_log"
  fi

  if ! command -v make >/dev/null 2>&1; then
    echo "Required command not found: make" >&2
    fail_and_exit "build" "required command not found: make" 1 "inspect_build_log"
  fi
}

extract_cpu_size() {
  local source_file="$1"
  awk '
    /^[[:space:]]*cpu_size[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*#.*/, "", $0)
      gsub(/[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$source_file"
}

extract_yaml_scalar() {
  local source_file="$1"
  local key="$2"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      sub(/[[:space:]]*#.*/, "", $0)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      print $0
      exit
    }
  ' "$source_file"
}

compute_time_end() {
  local initial_time="$1"
  local initial_step="$2"
  local final_time="$3"
  awk -v initial_time="$initial_time" -v initial_step="$initial_step" -v final_time="$final_time" '
    BEGIN {
      if (initial_step <= 0 || initial_time > final_time) exit 1
      value = (final_time - initial_time) / initial_step
      rounded = sprintf("%.0f", value)
      if (value - rounded > 1e-9 || rounded - value > 1e-9) exit 1
      print rounded
    }
  '
}

yaml_block_has_entries() {
  local file="$1"
  local block="$2"
  awk -v block="$block" '
    $0 ~ "^" block ":" {
      inblock=1
      next
    }
    inblock {
      if ($0 ~ /^[^[:space:]].*:/) {
        exit found ? 0 : 1
      }
      if ($0 ~ /^[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*#/) next
      found=1
    }
    END {
      if (inblock && found) exit 0
      exit 1
    }
  ' "$file"
}

resolve_geo_file_base() {
  local raw_value
  raw_value="$(awk '
    /^[[:space:]]*geo_file_base[[:space:]]*:/ {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      print $0
      exit
    }
  ' "$preprocessor_file")"

  if [[ -z "$raw_value" ]]; then
    return 1
  fi

  raw_value="${raw_value#"${raw_value%%[![:space:]]*}"}"
  raw_value="${raw_value%"${raw_value##*[![:space:]]}"}"

  if [[ "$raw_value" == \"*\" && "$raw_value" == *\" ]]; then
    raw_value="${raw_value:1:-1}"
  fi
  if [[ "$raw_value" == \'*\' && "$raw_value" == *\' ]]; then
    raw_value="${raw_value:1:-1}"
  fi

  preprocess_geo_file_base="$raw_value"

  if [[ "$raw_value" == /* ]]; then
    preprocess_geo_file_resolved="$raw_value"
  else
    preprocess_geo_file_resolved="${build_dir}/${raw_value}"
  fi

  [[ -f "${preprocess_geo_file_resolved}0.yml" ]]
}

detect_preprocess_case_type() {
  local ebc_has_entries="false"
  local init_count=0
  local dir_block=""

  if yaml_block_has_entries "$preprocessor_file" "EBC"; then
    ebc_has_entries="true"
  fi

  if [[ -f "$preprocessor_init_file" ]]; then
    preprocess_init_yaml_present="true"
    for dir_block in Dirichlet_velo_x Dirichlet_velo_y Dirichlet_velo_z; do
      if yaml_block_has_entries "$preprocessor_init_file" "$dir_block"; then
        init_count=$((init_count + 1))
      fi
    done
  else
    preprocess_init_yaml_present="false"
  fi

  if [[ "$ebc_has_entries" == "true" && "$init_count" -eq 0 ]]; then
    preprocess_case_type="traction"
    preprocess_reason="runtime EBC has entries and init YAML has no displacement-specific Dirichlet entries"
    preprocess_command_display="[\"./preprocess3d\"]"
    return 0
  fi

  if [[ "$ebc_has_entries" == "false" && "$init_count" -eq 1 ]]; then
    preprocess_case_type="displacement"
    preprocess_reason="runtime EBC is empty and init YAML has exactly one displacement-specific Dirichlet block"
    preprocess_command_display="[\"./preprocess3d\", \"./preprocess3d_init\"]"
    return 0
  fi

  preprocess_case_type="unknown"
  preprocess_reason="unable to determine case type safely from EBC and paras_preprocessor_init.yml"
  return 1
}

validate_preprocess_inputs() {
  if [[ ! -f "$preprocessor_file" ]]; then
    echo "Required preprocess file not found: $preprocessor_file" >&2
    fail_and_exit "preprocess" "required preprocess file not found" 1 "inspect_preprocess_log"
  fi

  preprocess_runtime_yaml_present="true"

  if ! resolve_geo_file_base; then
    echo "Invalid or unresolved geo_file_base in: $preprocessor_file" >&2
    fail_and_exit "preprocess" "invalid or unresolved geo_file_base" 1 "inspect_preprocess_log"
  fi

  if ! detect_preprocess_case_type; then
    echo "Case type could not be determined safely from preprocess YAML files." >&2
    fail_and_exit "preprocess" "case type could not be determined safely" 1 "inspect_preprocess_log"
  fi

  if [[ ! -x "${build_dir}/preprocess3d" ]]; then
    echo "Required preprocess executable not found: ${build_dir}/preprocess3d" >&2
    fail_and_exit "preprocess" "required preprocess executable not found: preprocess3d" 1 "inspect_preprocess_log"
  fi

  if [[ "$preprocess_case_type" == "displacement" && ! -x "${build_dir}/preprocess3d_init" ]]; then
    echo "Required preprocess executable not found: ${build_dir}/preprocess3d_init" >&2
    fail_and_exit "preprocess" "required preprocess executable not found: preprocess3d_init" 1 "inspect_preprocess_log"
  fi
}

run_preprocess_stage() {
  local -a preprocess_commands
  local -a preprocess_exit_codes=()
  local command_exit_code=0

  preprocess_status="running"
  current_stage="preprocess"
  top_level_status="running"
  next_step="preprocess_running"
  write_state

  {
    printf '[mixpg] preprocess case type: %s\n' "$preprocess_case_type"
    printf '[mixpg] preprocess reason: %s\n' "$preprocess_reason"
    printf '[mixpg] preprocess runtime yaml: %s\n' "$preprocessor_file"
    printf '[mixpg] preprocess init yaml present: %s\n' "$preprocess_init_yaml_present"
    printf '[mixpg] geo_file_base: %s\n' "$preprocess_geo_file_base"
    printf '[mixpg] geo_file_base resolved: %s\n' "$preprocess_geo_file_resolved"
  } >"$preprocess_log"

  preprocess_commands=( "./preprocess3d" )
  if [[ "$preprocess_case_type" == "displacement" ]]; then
    preprocess_commands+=( "./preprocess3d_init" )
  fi

  for preprocess_command in "${preprocess_commands[@]}"; do
    {
      printf '[mixpg] preprocess command: %s\n' "$preprocess_command"
      printf '[mixpg] preprocess cwd: %s\n' "$build_dir"
    } >>"$preprocess_log"

    (
      cd "$build_dir"
      "$preprocess_command"
    ) >>"$preprocess_log" 2>&1 || command_exit_code=$?

    preprocess_exit_codes+=( "$command_exit_code" )
    if [[ "$command_exit_code" -ne 0 ]]; then
      preprocess_exit_codes_json="$(json_array_from_values "${preprocess_exit_codes[@]}")"
      set_stage_failed "preprocess"
      next_step="inspect_preprocess_log"
      current_stage="preprocess"
      record_failure "preprocess stage failed" "$command_exit_code"
      write_state
      return 1
    fi
    command_exit_code=0
  done

  preprocess_exit_codes_json="$(json_array_from_values "${preprocess_exit_codes[@]}")"

  preprocess_status="completed"
  top_level_status="ready"
  next_step="driver_not_implemented"
  current_stage="preprocess"
  failure_json="null"
  write_state
}

validate_driver_inputs() {
  local recorded_preprocess_status=""
  local displacement_candidates=()

  if [[ ! -f "$state_file" ]]; then
    echo "State file not found for driver stage: $state_file" >&2
    fail_and_exit "driver" "state file not found for driver stage" 1 "inspect_driver_log"
  fi

  recorded_preprocess_status="$(extract_state_string "preprocess" "status")"
  driver_case_type="$(extract_state_string "preprocess" "case_type")"

  if [[ "$recorded_preprocess_status" != "completed" ]]; then
    echo "Preprocess stage is not recorded as completed in state." >&2
    fail_and_exit "driver" "preprocess stage is not recorded as completed in state" 1 "inspect_driver_log"
  fi

  if [[ "$driver_case_type" != "traction" && "$driver_case_type" != "displacement" ]]; then
    echo "Recorded preprocess case type is missing or unsupported: $driver_case_type" >&2
    fail_and_exit "driver" "recorded preprocess case type is missing or unsupported" 1 "inspect_driver_log"
  fi

  if [[ ! -f "$driver_file" ]]; then
    echo "Required driver file not found: $driver_file" >&2
    fail_and_exit "driver" "required driver file not found" 1 "inspect_driver_log"
  fi
  driver_file_present="true"

  driver_cpu_size="$(extract_cpu_size "$preprocessor_file")"
  if [[ -z "$driver_cpu_size" ]]; then
    driver_cpu_size="$(extract_cpu_size "$driver_file")"
  fi
  if [[ -z "$driver_cpu_size" ]]; then
    echo "cpu_size could not be determined from preprocess or driver inputs." >&2
    fail_and_exit "driver" "cpu_size could not be determined from inputs" 1 "inspect_driver_log"
  fi

  if ! command -v mpirun >/dev/null 2>&1; then
    echo "Required command not found: mpirun" >&2
    fail_and_exit "driver" "required command not found: mpirun" 1 "inspect_driver_log"
  fi

  if [[ "$driver_case_type" == "traction" ]]; then
    driver_executable="${build_dir}/mixed_ga_driver"
    driver_reason="recorded preprocess case type is traction, so use the non-displacement driver"
    if [[ ! -x "$driver_executable" ]]; then
      echo "Required driver executable not found: $driver_executable" >&2
      fail_and_exit "driver" "required driver executable not found: mixed_ga_driver" 1 "inspect_driver_log"
    fi
  else
    if [[ -x "${build_dir}/mixed_ga_driver_displacement" ]]; then
      displacement_candidates+=( "${build_dir}/mixed_ga_driver_displacement" )
    fi
    if [[ -x "${build_dir}/mixed_ga_driver_disp" ]]; then
      displacement_candidates+=( "${build_dir}/mixed_ga_driver_disp" )
    fi

    if [[ "${#displacement_candidates[@]}" -ne 1 ]]; then
      echo "Displacement driver could not be determined safely from documented workflow." >&2
      fail_and_exit "driver" "displacement driver could not be determined safely from documented workflow" 1 "inspect_driver_log"
    fi

    driver_executable="${displacement_candidates[0]}"
    driver_reason="recorded preprocess case type is displacement, and exactly one documented displacement driver executable is present"
  fi
}

run_driver_stage() {
  driver_status="running"
  current_stage="driver"
  top_level_status="running"
  next_step="driver_running"
  driver_command_display="mpirun -np ${driver_cpu_size} ${driver_executable} | tee driver_log.txt"
  write_state

  {
    printf '[mixpg] driver case type from state: %s\n' "$driver_case_type"
    printf '[mixpg] driver reason: %s\n' "$driver_reason"
    printf '[mixpg] driver file: %s\n' "$driver_file"
    printf '[mixpg] driver cpu_size: %s\n' "$driver_cpu_size"
    printf '[mixpg] driver executable: %s\n' "$driver_executable"
    printf '[mixpg] driver command: %s\n' "$driver_command_display"
  } >"$driver_log"

  if (
    cd "$build_dir"
    mpirun -np "$driver_cpu_size" "$driver_executable" | tee driver_log.txt
  ) >>"$driver_log" 2>&1; then
    driver_status="completed"
    driver_exit_code=0
    top_level_status="ready"
    next_step="postprocess_not_implemented"
    failure_json="null"
  else
    driver_exit_code=$?
    set_stage_failed "driver"
    next_step="inspect_driver_log"
    current_stage="driver"
    record_failure "driver stage failed" "$driver_exit_code"
  fi

  write_state
}

validate_postprocess_inputs() {
  local recorded_driver_status=""
  local recorded_driver_cpu_size=""
  local initial_time=""
  local initial_step=""
  local final_time=""

  if [[ ! -f "$state_file" ]]; then
    echo "State file not found for postprocess stage: $state_file" >&2
    fail_and_exit "postprocess" "state file not found for postprocess stage" 1 "inspect_postprocess_log"
  fi

  recorded_driver_status="$(extract_state_string "driver" "status")"
  recorded_driver_cpu_size="$(extract_state_string "driver" "cpu_size")"

  if [[ "$recorded_driver_status" != "completed" ]]; then
    echo "Driver stage is not recorded as completed in state." >&2
    fail_and_exit "postprocess" "driver stage is not recorded as completed in state" 1 "inspect_postprocess_log"
  fi

  if [[ ! -f "$driver_file" ]]; then
    echo "Required driver file not found for postprocess: $driver_file" >&2
    fail_and_exit "postprocess" "required driver file not found for postprocess" 1 "inspect_postprocess_log"
  fi

  postprocess_cpu_size="$recorded_driver_cpu_size"
  if [[ -z "$postprocess_cpu_size" || "$postprocess_cpu_size" == "unknown" ]]; then
    postprocess_cpu_size="$(extract_cpu_size "$preprocessor_file")"
  fi
  if [[ -z "$postprocess_cpu_size" || "$postprocess_cpu_size" == "unknown" ]]; then
    postprocess_cpu_size="$(extract_cpu_size "$driver_file")"
  fi
  if [[ -z "$postprocess_cpu_size" || "$postprocess_cpu_size" == "unknown" ]]; then
    echo "Postprocess cpu_size could not be determined safely." >&2
    fail_and_exit "postprocess" "postprocess cpu_size could not be determined safely" 1 "inspect_postprocess_log"
  fi

  initial_time="$(extract_yaml_scalar "$driver_file" "initial_time")"
  initial_step="$(extract_yaml_scalar "$driver_file" "initial_step")"
  final_time="$(extract_yaml_scalar "$driver_file" "final_time")"
  if [[ -z "$initial_time" || -z "$initial_step" || -z "$final_time" ]]; then
    echo "Driver time settings are missing in: $driver_file" >&2
    fail_and_exit "postprocess" "driver time settings are missing" 1 "inspect_postprocess_log"
  fi

  if ! postprocess_time_end="$(compute_time_end "$initial_time" "$initial_step" "$final_time")"; then
    echo "time_end could not be determined safely from driver settings." >&2
    fail_and_exit "postprocess" "time_end could not be determined safely from driver settings" 1 "inspect_postprocess_log"
  fi

  if ! command -v mpirun >/dev/null 2>&1; then
    echo "Required command not found: mpirun" >&2
    fail_and_exit "postprocess" "required command not found: mpirun" 1 "inspect_postprocess_log"
  fi

  if [[ ! -x "${build_dir}/reanalysis_proj_driver" ]]; then
    echo "Required postprocess executable not found: ${build_dir}/reanalysis_proj_driver" >&2
    fail_and_exit "postprocess" "required postprocess executable not found: reanalysis_proj_driver" 1 "inspect_postprocess_log"
  fi

  if [[ ! -x "${build_dir}/prepostproc" ]]; then
    echo "Required postprocess executable not found: ${build_dir}/prepostproc" >&2
    fail_and_exit "postprocess" "required postprocess executable not found: prepostproc" 1 "inspect_postprocess_log"
  fi

  postprocess_reason="using the common documented standard order shared by the references: reanalysis_proj_driver then prepostproc"
  postprocess_command_display="[\"mpirun -np ${postprocess_cpu_size} ./reanalysis_proj_driver -time_end ${postprocess_time_end}\", \"./prepostproc\"]"
}

run_postprocess_stage() {
  local -a postprocess_exit_codes=()
  local command_exit_code=0

  postprocess_status="running"
  current_stage="postprocess"
  top_level_status="running"
  next_step="postprocess_running"
  write_state

  {
    printf '[mixpg] postprocess reason: %s\n' "$postprocess_reason"
    printf '[mixpg] postprocess cpu_size: %s\n' "$postprocess_cpu_size"
    printf '[mixpg] postprocess time_end: %s\n' "$postprocess_time_end"
    printf '[mixpg] postprocess command 1: mpirun -np %s ./reanalysis_proj_driver -time_end %s\n' "$postprocess_cpu_size" "$postprocess_time_end"
    printf '[mixpg] postprocess command 2: ./prepostproc\n'
  } >"$postprocess_log"

  (
    cd "$build_dir"
    mpirun -np "$postprocess_cpu_size" ./reanalysis_proj_driver -time_end "$postprocess_time_end"
  ) >>"$postprocess_log" 2>&1 || command_exit_code=$?
  postprocess_exit_codes+=( "$command_exit_code" )
  if [[ "$command_exit_code" -ne 0 ]]; then
    postprocess_exit_codes_json="$(json_array_from_values "${postprocess_exit_codes[@]}")"
    set_stage_failed "postprocess"
    next_step="inspect_postprocess_log"
    current_stage="postprocess"
    record_failure "postprocess stage failed during reanalysis_proj_driver" "$command_exit_code"
    write_state
    return 1
  fi

  command_exit_code=0
  (
    cd "$build_dir"
    ./prepostproc
  ) >>"$postprocess_log" 2>&1 || command_exit_code=$?
  postprocess_exit_codes+=( "$command_exit_code" )
  if [[ "$command_exit_code" -ne 0 ]]; then
    postprocess_exit_codes_json="$(json_array_from_values "${postprocess_exit_codes[@]}")"
    set_stage_failed "postprocess"
    next_step="inspect_postprocess_log"
    current_stage="postprocess"
    record_failure "postprocess stage failed during prepostproc" "$command_exit_code"
    write_state
    return 1
  fi

  postprocess_exit_codes_json="$(json_array_from_values "${postprocess_exit_codes[@]}")"
  postprocess_status="completed"
  top_level_status="ready"
  next_step="workflow_completed"
  current_stage="postprocess"
  failure_json="null"
  write_state
}

write_state() {
  local state_dir
  state_dir="$(dirname "$state_file")"
  mkdir -p "$state_dir"

  cat > "$state_file" <<EOF
{
  "version": 1,
  "workflow": "mixpg-build-preprocess-driver-postprocess",
  "current_stage": "$current_stage",
  "status": "$top_level_status",
  "requested": {
    "clean_build": $(json_bool "$clean_build")
  },
  "paths": {
    "repo_root": "$repo_root",
    "example_dir": "$example_dir",
    "config_file": "$config_file",
    "input_dir": "$input_dir",
    "build_dir": "$build_dir"
  },
  "stages": {
    "safe_prepare": {
      "status": "$([[ "$build_status" == "completed" ]] && echo "completed" || echo "delegated_to_build")",
      "build_dir_action": "$build_dir_action",
      "input_copy": "$input_copy_status"
    },
    "build": {
      "status": "$build_status",
      "script": "$build_script",
      "command": "$build_command_display",
      "log_file": "$build_log",
      "build_dir_exists_before": $(json_bool "$build_dir_exists_before"),
      "exit_code": $build_exit_code
    },
    "preprocess": {
      "status": "$preprocess_status",
      "case_type": "$preprocess_case_type",
      "reason": "$preprocess_reason",
      "runtime_yaml": "$preprocessor_file",
      "runtime_yaml_present": $(json_bool "$preprocess_runtime_yaml_present"),
      "init_yaml": "$preprocessor_init_file",
      "init_yaml_present": $(json_bool "$preprocess_init_yaml_present"),
      "geo_file_base": "$preprocess_geo_file_base",
      "geo_file_base_resolved": "$preprocess_geo_file_resolved",
      "commands": $preprocess_command_display,
      "log_file": "$preprocess_log",
      "exit_codes": $preprocess_exit_codes_json
    },
    "driver": {
      "status": "$driver_status",
      "case_type": "$driver_case_type",
      "reason": "$driver_reason",
      "driver_file": "$driver_file",
      "driver_file_present": $(json_bool "$driver_file_present"),
      "cpu_size": "$driver_cpu_size",
      "executable": "$driver_executable",
      "command": "$driver_command_display",
      "log_file": "$driver_log",
      "exit_code": $driver_exit_code
    },
    "postprocess": {
      "status": "$postprocess_status",
      "reason": "$postprocess_reason",
      "cpu_size": "$postprocess_cpu_size",
      "time_end": "$postprocess_time_end",
      "commands": $postprocess_command_display,
      "log_file": "$postprocess_log",
      "exit_codes": $postprocess_exit_codes_json
    }
  },
  "failure": $failure_json,
  "next_step": "$next_step"
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
mkdir -p "$log_dir"

if [[ -d "$build_dir" ]]; then
  build_dir_exists_before="true"
  if [[ "$clean_build" == "true" ]]; then
    build_dir_action="cleaned"
  else
    build_dir_action="blocked_existing_dir"
  fi
else
  build_dir_action="created"
fi

if [[ ! -f "$config_file" ]]; then
  echo "Required config file not found: $config_file" >&2
  fail_and_exit "build" "required config file not found" 1 "inspect_build_log"
fi

if [[ ! -d "$example_dir" ]]; then
  echo "Example directory not found: $example_dir" >&2
  fail_and_exit "build" "example directory not found" 1 "inspect_build_log"
fi

if [[ ! -d "$input_dir" ]]; then
  echo "Input directory not found: $input_dir" >&2
  fail_and_exit "build" "input directory not found" 1 "inspect_build_log"
fi

validate_prerequisites

build_status="running"
top_level_status="running"
next_step="build_running"
write_state

build_command=( "$build_script" "--repo-root" "$repo_root" "--build-dir" "$build_dir" )
if [[ "$clean_build" == "true" ]]; then
  build_command+=( "--clean" )
fi
printf -v build_command_display '%q ' "${build_command[@]}"
build_command_display="${build_command_display% }"

{
  printf '[mixpg] build script: %s\n' "$build_script"
  printf '[mixpg] build command:'
  printf ' %q' "${build_command[@]}"
  printf '\n'
} >"$build_log"

if "${build_command[@]}" >>"$build_log" 2>&1; then
  build_status="completed"
  build_exit_code=0
  input_copy_status="copied"
  top_level_status="running"
  next_step="preprocess_pending"
  failure_json="null"
else
  build_exit_code=$?
  build_status="failed"
  input_copy_status="unknown"
  top_level_status="failed"
  next_step="inspect_build_log"
  record_failure "build stage failed" "$build_exit_code"
fi

write_state

if [[ "$build_status" == "completed" ]]; then
  validate_preprocess_inputs
  run_preprocess_stage
fi

if [[ "$preprocess_status" == "completed" ]]; then
  validate_driver_inputs
  run_driver_stage
fi

if [[ "$driver_status" == "completed" ]]; then
  validate_postprocess_inputs
  run_postprocess_stage
fi

echo "[mixpg] build stage status: $build_status"
echo "[mixpg] preprocess stage status: $preprocess_status"
echo "[mixpg] driver stage status: $driver_status"
echo "[mixpg] postprocess stage status: $postprocess_status"
echo "[mixpg] state file: $state_file"
echo "[mixpg] build log: $build_log"
echo "[mixpg] preprocess log: $preprocess_log"
echo "[mixpg] driver log: $driver_log"
echo "[mixpg] postprocess log: $postprocess_log"
