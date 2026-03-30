#!/usr/bin/env bash
set -euo pipefail

repo_root="${HOME}/MixPERIGEE"
build_dir="${HOME}/build_MixPG"
state_file="state/state.json"
clean_build="false"
start_from="build"
retry_stage=""
mpi_launcher=""

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
safe_prepare_status="not_started"
build_status="not_started"
build_exit_code="null"
build_attempt_count="0"
build_max_attempts="2"
preprocess_status="not_started"
preprocess_case_type="unknown"
preprocess_reason="not_determined"
preprocess_command_display="[]"
preprocess_exit_codes_json="[]"
preprocess_geo_file_base=""
preprocess_geo_file_resolved=""
preprocess_geo_file_mode="unknown"
preprocess_geo_guardrail="pending"
preprocess_geo_guardrail_reason="not_checked"
preprocess_runtime_yaml_present="false"
preprocess_init_yaml_present="false"
preprocess_cleanup_status="not_run"
preprocess_cleanup_reason="not_needed"
preprocess_cleanup_patterns_json="[]"
preprocess_cleanup_removed_json="[]"
preprocess_attempt_count="0"
preprocess_max_attempts="1"
driver_status="not_started"
driver_case_type="unknown"
driver_reason="not_determined"
driver_executable=""
driver_command_display=""
driver_exit_code="null"
driver_cpu_size="unknown"
driver_file_present="false"
driver_mpi_launcher=""
driver_mpi_linked_prefix=""
driver_mpi_linked_family="unknown"
driver_attempt_count="0"
driver_max_attempts="1"
postprocess_status="not_started"
postprocess_reason="not_determined"
postprocess_cpu_size="unknown"
postprocess_time_end="unknown"
postprocess_command_display="[]"
postprocess_exit_codes_json="[]"
postprocess_dependency_guardrail="pending"
postprocess_dependency_guardrail_reason="not_checked"
postprocess_dependency_patterns_json='["postpart_p*.h5"]'
postprocess_dependency_found_json="[]"
postprocess_mpi_launcher=""
postprocess_mpi_linked_prefix=""
postprocess_mpi_linked_family="unknown"
postprocess_attempt_count="0"
postprocess_max_attempts="1"
top_level_status="pending"
next_step="build_pending"
failure_json="null"
build_dir_exists_before="false"
build_command_display=""
current_stage="build"
resume_requested="false"
resume_mode="rerun"
resume_allowed="true"
resume_requested_start_from="build"
resume_effective_start_from="build"
resume_reason="default full rerun from beginning"
retry_requested="false"
retry_requested_stage=""
retry_allowed="true"
retry_reason="no retry requested"
retry_policy_mode="stage_level_conservative"

usage() {
  cat <<'EOF'
Usage:
  mixpg_executor.sh [--repo-root DIR] [--build-dir DIR] [--state-file FILE] [--clean] [--start-from STAGE] [--retry-stage STAGE] [--mpi-launcher PATH]

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
  - support conservative explicit resume with --start-from
  - support conservative explicit retry with --retry-stage
  - select an MPI launcher explicitly or derive it from executable linkage
  - write/update a state file
  - capture stage logs

Guardrails:
  - only build, preprocess, driver, and postprocess-stage support are implemented
  - only removes build directory contents when --clean is explicitly provided
  - later-stage resume is allowed only when recorded state and basic artifact checks agree
  - retry is stage-level, bounded, and only enabled where the policy explicitly allows it
  - MPI launcher selection must not rely on PATH-first mpirun/mpiexec resolution
  - unsafe absolute geo_file_base values are rejected when they conflict with the documented HOME-prefix behavior
  - preprocess cleanup removes only known generated preprocess and partition artifacts
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

extract_state_raw() {
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
      print $0
      exit
    }
  ' "$state_file"
}

normalize_start_from() {
  case "$1" in
    safe_prepare|build)
      echo "build"
      ;;
    preprocess|driver|postprocess)
      echo "$1"
      ;;
    *)
      return 1
      ;;
  esac
}

load_state_for_resume() {
  safe_prepare_status="$(extract_state_string "safe_prepare" "status")"
  build_dir_action="$(extract_state_string "safe_prepare" "build_dir_action")"
  input_copy_status="$(extract_state_string "safe_prepare" "input_copy")"
  build_attempt_count="$(extract_state_raw "safe_prepare" "attempts")"
  if [[ -z "$build_attempt_count" ]]; then
    build_attempt_count="$(extract_state_raw "build" "attempts")"
  fi
  if [[ -z "$build_attempt_count" ]]; then
    build_attempt_count="0"
  fi

  build_status="$(extract_state_string "build" "status")"
  build_command_display="$(extract_state_string "build" "command")"
  build_log="$(extract_state_string "build" "log_file")"
  build_exit_code="$(extract_state_raw "build" "exit_code")"

  preprocess_status="$(extract_state_string "preprocess" "status")"
  preprocess_case_type="$(extract_state_string "preprocess" "case_type")"
  preprocess_reason="$(extract_state_string "preprocess" "reason")"
  preprocess_geo_file_base="$(extract_state_string "preprocess" "geo_file_base")"
  preprocess_geo_file_resolved="$(extract_state_string "preprocess" "geo_file_base_resolved")"
  preprocess_geo_file_mode="$(extract_state_string "preprocess" "geo_file_base_mode")"
  preprocess_geo_guardrail="$(extract_state_string "preprocess" "geo_guardrail")"
  preprocess_geo_guardrail_reason="$(extract_state_string "preprocess" "geo_guardrail_reason")"
  preprocess_command_display="$(extract_state_raw "preprocess" "commands")"
  preprocess_log="$(extract_state_string "preprocess" "log_file")"
  preprocess_exit_codes_json="$(extract_state_raw "preprocess" "exit_codes")"
  preprocess_cleanup_status="$(extract_state_string "preprocess" "cleanup_status")"
  preprocess_cleanup_reason="$(extract_state_string "preprocess" "cleanup_reason")"
  preprocess_cleanup_patterns_json="$(extract_state_raw "preprocess" "cleanup_patterns")"
  preprocess_cleanup_removed_json="$(extract_state_raw "preprocess" "cleanup_removed")"
  preprocess_attempt_count="$(extract_state_raw "preprocess" "attempts")"
  if [[ -z "$preprocess_attempt_count" ]]; then
    preprocess_attempt_count="0"
  fi
  if [[ "$(extract_state_raw "preprocess" "runtime_yaml_present")" == "true" ]]; then
    preprocess_runtime_yaml_present="true"
  fi
  if [[ "$(extract_state_raw "preprocess" "init_yaml_present")" == "true" ]]; then
    preprocess_init_yaml_present="true"
  fi

  driver_status="$(extract_state_string "driver" "status")"
  driver_case_type="$(extract_state_string "driver" "case_type")"
  driver_reason="$(extract_state_string "driver" "reason")"
  driver_executable="$(extract_state_string "driver" "executable")"
  driver_command_display="$(extract_state_string "driver" "command")"
  driver_log="$(extract_state_string "driver" "log_file")"
  driver_exit_code="$(extract_state_raw "driver" "exit_code")"
  driver_cpu_size="$(extract_state_string "driver" "cpu_size")"
  driver_attempt_count="$(extract_state_raw "driver" "attempts")"
  if [[ -z "$driver_attempt_count" ]]; then
    driver_attempt_count="0"
  fi
  if [[ "$(extract_state_raw "driver" "driver_file_present")" == "true" ]]; then
    driver_file_present="true"
  fi

  postprocess_status="$(extract_state_string "postprocess" "status")"
  postprocess_reason="$(extract_state_string "postprocess" "reason")"
  postprocess_cpu_size="$(extract_state_string "postprocess" "cpu_size")"
  postprocess_time_end="$(extract_state_string "postprocess" "time_end")"
  postprocess_command_display="$(extract_state_raw "postprocess" "commands")"
  postprocess_log="$(extract_state_string "postprocess" "log_file")"
  postprocess_exit_codes_json="$(extract_state_raw "postprocess" "exit_codes")"
  postprocess_dependency_guardrail="$(extract_state_string "postprocess" "downstream_dependency_guardrail")"
  postprocess_dependency_guardrail_reason="$(extract_state_string "postprocess" "downstream_dependency_guardrail_reason")"
  postprocess_dependency_found_json="$(extract_state_raw "postprocess" "downstream_dependency_found")"
  postprocess_attempt_count="$(extract_state_raw "postprocess" "attempts")"
  if [[ -z "$postprocess_attempt_count" ]]; then
    postprocess_attempt_count="0"
  fi
}

require_completed_stage_for_resume() {
  local stage="$1"
  if [[ "$(extract_state_string "$stage" "status")" != "completed" ]]; then
    return 1
  fi
}

validate_resume_request() {
  if [[ "$resume_effective_start_from" == "build" ]]; then
    return 0
  fi

  if [[ ! -f "$state_file" ]]; then
    resume_allowed="false"
    resume_reason="resume requested for a later stage, but the state file is missing"
    fail_and_exit "$resume_effective_start_from" "resume requested for a later stage, but the state file is missing" 1 "resume_rejected"
  fi

  load_state_for_resume

  case "$resume_effective_start_from" in
    preprocess)
      if ! require_completed_stage_for_resume "build"; then
        resume_allowed="false"
        resume_reason="resume from preprocess requires build to be recorded as completed"
        fail_and_exit "preprocess" "resume from preprocess requires build to be recorded as completed" 1 "resume_rejected"
      fi
      if [[ ! -x "${build_dir}/preprocess3d" ]]; then
        resume_allowed="false"
        resume_reason="resume from preprocess requires existing preprocess executables in the build directory"
        fail_and_exit "preprocess" "resume from preprocess requires existing preprocess executables in the build directory" 1 "resume_rejected"
      fi
      resume_reason="resume from preprocess allowed because build is recorded as completed and preprocess artifacts exist"
      ;;
    driver)
      if ! require_completed_stage_for_resume "build" || ! require_completed_stage_for_resume "preprocess"; then
        resume_allowed="false"
        resume_reason="resume from driver requires build and preprocess to be recorded as completed"
        fail_and_exit "driver" "resume from driver requires build and preprocess to be recorded as completed" 1 "resume_rejected"
      fi
      if [[ ! -f "$preprocessor_file" || ! -f "$driver_file" ]]; then
        resume_allowed="false"
        resume_reason="resume from driver requires preprocess and driver input files to exist"
        fail_and_exit "driver" "resume from driver requires preprocess and driver input files to exist" 1 "resume_rejected"
      fi
      resume_reason="resume from driver allowed because build and preprocess are recorded as completed and required inputs exist"
      ;;
    postprocess)
      if ! require_completed_stage_for_resume "build" || ! require_completed_stage_for_resume "preprocess" || ! require_completed_stage_for_resume "driver"; then
        resume_allowed="false"
        resume_reason="resume from postprocess requires build, preprocess, and driver to be recorded as completed"
        fail_and_exit "postprocess" "resume from postprocess requires build, preprocess, and driver to be recorded as completed" 1 "resume_rejected"
      fi
      if [[ ! -f "$driver_file" || ! -x "${build_dir}/reanalysis_proj_driver" || ! -x "${build_dir}/prepostproc" ]]; then
        resume_allowed="false"
        resume_reason="resume from postprocess requires driver inputs and postprocess executables to exist"
        fail_and_exit "postprocess" "resume from postprocess requires driver inputs and postprocess executables to exist" 1 "resume_rejected"
      fi
      resume_reason="resume from postprocess allowed because build, preprocess, and driver are recorded as completed and postprocess artifacts exist"
      ;;
  esac
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

validate_retry_request() {
  if [[ "$retry_requested" != "true" ]]; then
    return 0
  fi

  if [[ -z "$retry_requested_stage" ]]; then
    retry_allowed="false"
    retry_reason="retry was requested without a stage"
    fail_and_exit "build" "retry was requested without a stage" 1 "retry_rejected"
  fi

  if [[ "$retry_requested_stage" != "build" ]]; then
    retry_allowed="false"
    retry_reason="no automatic retry policy is implemented for the requested stage"
    fail_and_exit "$retry_requested_stage" "no automatic retry policy is implemented for the requested stage" 1 "retry_rejected"
  fi

  if [[ "$resume_effective_start_from" != "build" ]]; then
    retry_allowed="false"
    retry_reason="retry currently reuses the build start path and must start from build"
    fail_and_exit "build" "retry currently reuses the build start path and must start from build" 1 "retry_rejected"
  fi

  if [[ ! -f "$state_file" ]]; then
    retry_allowed="false"
    retry_reason="retry requested, but the state file is missing"
    fail_and_exit "build" "retry requested, but the state file is missing" 1 "retry_rejected"
  fi

  load_state_for_resume

  if [[ "$build_status" != "failed" ]]; then
    retry_allowed="false"
    retry_reason="build retry requires the previous build stage to be recorded as failed"
    fail_and_exit "build" "build retry requires the previous build stage to be recorded as failed" 1 "retry_rejected"
  fi

  if [[ "$build_attempt_count" -ge "$build_max_attempts" ]]; then
    retry_allowed="false"
    retry_reason="build retry limit has already been reached"
    fail_and_exit "build" "build retry limit has already been reached" 1 "retry_rejected"
  fi

  if [[ "$build_dir_action" != "blocked_existing_dir" ]]; then
    retry_allowed="false"
    retry_reason="build retry is only allowed for the existing-build-directory blocking case"
    fail_and_exit "build" "build retry is only allowed for the existing-build-directory blocking case" 1 "retry_rejected"
  fi

  if [[ "$clean_build" != "true" ]]; then
    retry_allowed="false"
    retry_reason="build retry for an existing build directory requires explicit --clean"
    fail_and_exit "build" "build retry for an existing build directory requires explicit --clean" 1 "retry_rejected"
  fi

  if [[ ! -d "$build_dir" ]]; then
    retry_allowed="false"
    retry_reason="build retry requires the blocked build directory to still exist"
    fail_and_exit "build" "build retry requires the blocked build directory to still exist" 1 "retry_rejected"
  fi

  retry_reason="build retry allowed once because the previous failure was a blocked existing build directory and the current request explicitly uses --clean"
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

path_prefix_parent() {
  local path="$1"
  (
    cd "$(dirname "$path")/.." >/dev/null 2>&1 && pwd -P
  )
}

infer_mpi_family_from_text() {
  local text="$1"
  case "$text" in
    *mpich*|*HYDRA*)
      echo "mpich"
      ;;
    *openmpi*|*open-mpi*|*Open\ MPI*)
      echo "openmpi"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

detect_linked_mpi_prefix() {
  local executable="$1"
  local linked_line=""
  linked_line="$(otool -L "$executable" 2>/dev/null | awk '/\/lib\/lib(mpich|mpi|pmpi|mpicxx)[^[:space:]]*/ { print $1; exit }')"
  if [[ -z "$linked_line" ]]; then
    return 1
  fi
  printf '%s\n' "${linked_line%/lib/*}"
}

select_mpi_launcher_for_executable() {
  local executable="$1"
  local stage="$2"
  local linked_prefix=""
  local linked_family="unknown"
  local candidate=""
  local launcher_prefix=""

  if ! linked_prefix="$(detect_linked_mpi_prefix "$executable")"; then
    fail_and_exit "$stage" "could not determine linked MPI installation from executable" 1 "inspect_${stage}_log"
  fi

  linked_family="$(infer_mpi_family_from_text "$linked_prefix")"

  if [[ -n "$mpi_launcher" ]]; then
    if [[ ! -x "$mpi_launcher" ]]; then
      fail_and_exit "$stage" "configured MPI launcher is not executable" 1 "inspect_${stage}_log"
    fi
    candidate="$mpi_launcher"
  else
    if [[ -x "${linked_prefix}/bin/mpirun" ]]; then
      candidate="${linked_prefix}/bin/mpirun"
    elif [[ -x "${linked_prefix}/bin/mpiexec" ]]; then
      candidate="${linked_prefix}/bin/mpiexec"
    else
      fail_and_exit "$stage" "could not derive an MPI launcher from the linked MPI installation" 1 "inspect_${stage}_log"
    fi
  fi

  launcher_prefix="$(path_prefix_parent "$candidate")"
  if [[ "$launcher_prefix" != "$linked_prefix" ]]; then
    fail_and_exit "$stage" "MPI launcher path does not match the MPI installation linked by the executable" 1 "inspect_${stage}_log"
  fi

  if [[ "$stage" == "driver" ]]; then
    driver_mpi_launcher="$candidate"
    driver_mpi_linked_prefix="$linked_prefix"
    driver_mpi_linked_family="$linked_family"
  else
    postprocess_mpi_launcher="$candidate"
    postprocess_mpi_linked_prefix="$linked_prefix"
    postprocess_mpi_linked_family="$linked_family"
  fi
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

verify_postprocess_downstream_dependencies() {
  local -a found_files=()
  local candidate=""

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    found_files+=( "$candidate" )
  done < <(find "$build_dir" -maxdepth 1 -type f -name 'postpart_p*.h5' | sort)

  if [[ "${#found_files[@]}" -eq 0 ]]; then
    postprocess_dependency_guardrail="failed"
    postprocess_dependency_guardrail_reason="prepostproc completed but did not produce postpart_p*.h5, so downstream tools such as post_surface_force or vis_3d_mixed must not run"
    postprocess_dependency_found_json="[]"
    return 1
  fi

  postprocess_dependency_guardrail="passed"
  postprocess_dependency_guardrail_reason="prepostproc produced postpart_p*.h5, so downstream tools would satisfy this dependency check if explicitly implemented later"
  postprocess_dependency_found_json="["
  for candidate in "${found_files[@]}"; do
    postprocess_dependency_found_json="${postprocess_dependency_found_json}\"${candidate}\", "
  done
  postprocess_dependency_found_json="${postprocess_dependency_found_json%, }]"
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
    preprocess_geo_file_mode="absolute"
    preprocess_geo_guardrail="failed"
    preprocess_geo_guardrail_reason="absolute geo_file_base is rejected because the documented preprocessor behavior may prepend HOME and produce an unsafe broken path"
    preprocess_geo_file_resolved="$raw_value"
    return 1
  fi

  preprocess_geo_file_mode="relative"
  preprocess_geo_guardrail="passed"
  preprocess_geo_guardrail_reason="relative geo_file_base is resolved under the build directory and checked before preprocessing"
  preprocess_geo_file_resolved="${build_dir}/${raw_value}"

  [[ -f "${preprocess_geo_file_resolved}0.yml" ]]
}

cleanup_preprocess_generated_artifacts() {
  local -a cleanup_patterns=(
    "patch*.yml"
    "epart.h5"
    "npart.h5"
    "node_mapping.h5"
    "node_mapping_p.h5"
    "node_mapping_v.h5"
    "part_p*.h5"
    "epart_init.h5"
    "npart_init.h5"
    "part_init_p*.h5"
  )
  local -a removed_files=()
  local pattern=""
  local candidate=""

  preprocess_cleanup_patterns_json='["patch*.yml", "epart.h5", "npart.h5", "node_mapping.h5", "node_mapping_p.h5", "node_mapping_v.h5", "part_p*.h5", "epart_init.h5", "npart_init.h5", "part_init_p*.h5"]'
  preprocess_cleanup_reason="remove only known generated preprocess and partition artifacts before regenerating them"
  preprocess_cleanup_status="completed"

  for pattern in "${cleanup_patterns[@]}"; do
    while IFS= read -r candidate; do
      [[ -n "$candidate" ]] || continue
      rm -f "$candidate"
      removed_files+=( "$candidate" )
    done < <(find "$build_dir" -maxdepth 1 -type f -name "$pattern" -print)
  done

  if [[ "${#removed_files[@]}" -eq 0 ]]; then
    preprocess_cleanup_status="no_matches"
    preprocess_cleanup_reason="no known generated preprocess or partition artifacts were present before preprocessing"
    preprocess_cleanup_removed_json="[]"
    return 0
  fi

  preprocess_cleanup_removed_json="["
  for candidate in "${removed_files[@]}"; do
    preprocess_cleanup_removed_json="${preprocess_cleanup_removed_json}\"${candidate}\", "
  done
  preprocess_cleanup_removed_json="${preprocess_cleanup_removed_json%, }]"
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
    if [[ "$preprocess_geo_guardrail" == "failed" ]]; then
      echo "Unsafe absolute geo_file_base detected in: $preprocessor_file" >&2
      fail_and_exit "preprocess" "unsafe absolute geo_file_base conflicts with documented HOME-prefix behavior" 1 "inspect_preprocess_log"
    fi
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
    printf '[mixpg] geo_file_base mode: %s\n' "$preprocess_geo_file_mode"
    printf '[mixpg] geo guardrail: %s\n' "$preprocess_geo_guardrail"
    printf '[mixpg] geo guardrail reason: %s\n' "$preprocess_geo_guardrail_reason"
    printf '[mixpg] geo_file_base resolved: %s\n' "$preprocess_geo_file_resolved"
  } >"$preprocess_log"

  cleanup_preprocess_generated_artifacts
  {
    printf '[mixpg] preprocess cleanup status: %s\n' "$preprocess_cleanup_status"
    printf '[mixpg] preprocess cleanup reason: %s\n' "$preprocess_cleanup_reason"
    printf '[mixpg] preprocess cleanup patterns: %s\n' "$preprocess_cleanup_patterns_json"
    printf '[mixpg] preprocess cleanup removed: %s\n' "$preprocess_cleanup_removed_json"
  } >>"$preprocess_log"

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

  select_mpi_launcher_for_executable "$driver_executable" "driver"
}

run_driver_stage() {
  driver_status="running"
  current_stage="driver"
  top_level_status="running"
  next_step="driver_running"
  driver_command_display="${driver_mpi_launcher} -np ${driver_cpu_size} ${driver_executable} | tee driver_log.txt"
  write_state

  {
    printf '[mixpg] driver case type from state: %s\n' "$driver_case_type"
    printf '[mixpg] driver reason: %s\n' "$driver_reason"
    printf '[mixpg] driver file: %s\n' "$driver_file"
    printf '[mixpg] driver cpu_size: %s\n' "$driver_cpu_size"
    printf '[mixpg] driver executable: %s\n' "$driver_executable"
    printf '[mixpg] driver linked MPI prefix: %s\n' "$driver_mpi_linked_prefix"
    printf '[mixpg] driver linked MPI family: %s\n' "$driver_mpi_linked_family"
    printf '[mixpg] driver MPI launcher: %s\n' "$driver_mpi_launcher"
    printf '[mixpg] driver command: %s\n' "$driver_command_display"
  } >"$driver_log"

  if (
    cd "$build_dir"
    "$driver_mpi_launcher" -np "$driver_cpu_size" "$driver_executable" | tee driver_log.txt
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

  if [[ ! -x "${build_dir}/reanalysis_proj_driver" ]]; then
    echo "Required postprocess executable not found: ${build_dir}/reanalysis_proj_driver" >&2
    fail_and_exit "postprocess" "required postprocess executable not found: reanalysis_proj_driver" 1 "inspect_postprocess_log"
  fi

  if [[ ! -x "${build_dir}/prepostproc" ]]; then
    echo "Required postprocess executable not found: ${build_dir}/prepostproc" >&2
    fail_and_exit "postprocess" "required postprocess executable not found: prepostproc" 1 "inspect_postprocess_log"
  fi

  select_mpi_launcher_for_executable "${build_dir}/reanalysis_proj_driver" "postprocess"
  postprocess_reason="using the common documented standard order shared by the references: reanalysis_proj_driver then prepostproc"
  postprocess_command_display="[\"${postprocess_mpi_launcher} -np ${postprocess_cpu_size} ./reanalysis_proj_driver -time_end ${postprocess_time_end}\", \"./prepostproc\"]"
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
    printf '[mixpg] postprocess linked MPI prefix: %s\n' "$postprocess_mpi_linked_prefix"
    printf '[mixpg] postprocess linked MPI family: %s\n' "$postprocess_mpi_linked_family"
    printf '[mixpg] postprocess MPI launcher: %s\n' "$postprocess_mpi_launcher"
    printf '[mixpg] postprocess command 1: %s -np %s ./reanalysis_proj_driver -time_end %s\n' "$postprocess_mpi_launcher" "$postprocess_cpu_size" "$postprocess_time_end"
    printf '[mixpg] postprocess command 2: ./prepostproc\n'
  } >"$postprocess_log"

  (
    cd "$build_dir"
    "$postprocess_mpi_launcher" -np "$postprocess_cpu_size" ./reanalysis_proj_driver -time_end "$postprocess_time_end"
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

  if ! verify_postprocess_downstream_dependencies; then
    postprocess_exit_codes_json="$(json_array_from_values "${postprocess_exit_codes[@]}")"
    set_stage_failed "postprocess"
    next_step="inspect_postprocess_log"
    current_stage="postprocess"
    {
      printf '[mixpg] downstream dependency guardrail: %s\n' "$postprocess_dependency_guardrail"
      printf '[mixpg] downstream dependency guardrail reason: %s\n' "$postprocess_dependency_guardrail_reason"
      printf '[mixpg] downstream dependency patterns: %s\n' "$postprocess_dependency_patterns_json"
      printf '[mixpg] downstream dependency found: %s\n' "$postprocess_dependency_found_json"
    } >>"$postprocess_log"
    record_failure "postprocess downstream dependency artifacts missing after prepostproc" 1
    write_state
    return 1
  fi

  {
    printf '[mixpg] downstream dependency guardrail: %s\n' "$postprocess_dependency_guardrail"
    printf '[mixpg] downstream dependency guardrail reason: %s\n' "$postprocess_dependency_guardrail_reason"
    printf '[mixpg] downstream dependency patterns: %s\n' "$postprocess_dependency_patterns_json"
    printf '[mixpg] downstream dependency found: %s\n' "$postprocess_dependency_found_json"
  } >>"$postprocess_log"

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
    "clean_build": $(json_bool "$clean_build"),
    "start_from": "$resume_requested_start_from",
    "retry_stage": "$retry_requested_stage",
    "mpi_launcher": "$mpi_launcher"
  },
  "resume": {
    "requested": $(json_bool "$resume_requested"),
    "mode": "$resume_mode",
    "requested_start_from": "$resume_requested_start_from",
    "effective_start_from": "$resume_effective_start_from",
    "allowed": $(json_bool "$resume_allowed"),
    "reason": "$resume_reason"
  },
  "retry": {
    "requested": $(json_bool "$retry_requested"),
    "stage": "$retry_requested_stage",
    "allowed": $(json_bool "$retry_allowed"),
    "reason": "$retry_reason",
    "policy_mode": "$retry_policy_mode",
    "policy": {
      "build": $build_max_attempts,
      "preprocess": $preprocess_max_attempts,
      "driver": $driver_max_attempts,
      "postprocess": $postprocess_max_attempts
    }
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
      "status": "$safe_prepare_status",
      "build_dir_action": "$build_dir_action",
      "input_copy": "$input_copy_status",
      "attempts": $build_attempt_count,
      "max_attempts": $build_max_attempts
    },
    "build": {
      "status": "$build_status",
      "script": "$build_script",
      "command": "$build_command_display",
      "log_file": "$build_log",
      "build_dir_exists_before": $(json_bool "$build_dir_exists_before"),
      "exit_code": $build_exit_code,
      "attempts": $build_attempt_count,
      "max_attempts": $build_max_attempts
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
      "geo_file_base_mode": "$preprocess_geo_file_mode",
      "geo_file_base_resolved": "$preprocess_geo_file_resolved",
      "geo_guardrail": "$preprocess_geo_guardrail",
      "geo_guardrail_reason": "$preprocess_geo_guardrail_reason",
      "cleanup_status": "$preprocess_cleanup_status",
      "cleanup_reason": "$preprocess_cleanup_reason",
      "cleanup_patterns": $preprocess_cleanup_patterns_json,
      "cleanup_removed": $preprocess_cleanup_removed_json,
      "commands": $preprocess_command_display,
      "log_file": "$preprocess_log",
      "exit_codes": $preprocess_exit_codes_json,
      "attempts": $preprocess_attempt_count,
      "max_attempts": $preprocess_max_attempts
    },
    "driver": {
      "status": "$driver_status",
      "case_type": "$driver_case_type",
      "reason": "$driver_reason",
      "driver_file": "$driver_file",
      "driver_file_present": $(json_bool "$driver_file_present"),
      "cpu_size": "$driver_cpu_size",
      "mpi_launcher": "$driver_mpi_launcher",
      "mpi_linked_prefix": "$driver_mpi_linked_prefix",
      "mpi_linked_family": "$driver_mpi_linked_family",
      "executable": "$driver_executable",
      "command": "$driver_command_display",
      "log_file": "$driver_log",
      "exit_code": $driver_exit_code,
      "attempts": $driver_attempt_count,
      "max_attempts": $driver_max_attempts
    },
    "postprocess": {
      "status": "$postprocess_status",
      "reason": "$postprocess_reason",
      "cpu_size": "$postprocess_cpu_size",
      "time_end": "$postprocess_time_end",
      "downstream_dependency_guardrail": "$postprocess_dependency_guardrail",
      "downstream_dependency_guardrail_reason": "$postprocess_dependency_guardrail_reason",
      "downstream_dependency_patterns": $postprocess_dependency_patterns_json,
      "downstream_dependency_found": $postprocess_dependency_found_json,
      "mpi_launcher": "$postprocess_mpi_launcher",
      "mpi_linked_prefix": "$postprocess_mpi_linked_prefix",
      "mpi_linked_family": "$postprocess_mpi_linked_family",
      "commands": $postprocess_command_display,
      "log_file": "$postprocess_log",
      "exit_codes": $postprocess_exit_codes_json,
      "attempts": $postprocess_attempt_count,
      "max_attempts": $postprocess_max_attempts
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
    --start-from)
      start_from="$2"
      shift 2
      ;;
    --retry-stage)
      retry_stage="$2"
      shift 2
      ;;
    --mpi-launcher)
      mpi_launcher="$2"
      shift 2
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

if ! resume_effective_start_from="$(normalize_start_from "$start_from")"; then
  echo "Unsupported --start-from value: $start_from" >&2
  exit 1
fi

resume_requested_start_from="$start_from"
if [[ "$start_from" != "build" ]]; then
  resume_requested="true"
fi
if [[ "$resume_effective_start_from" == "build" ]]; then
  resume_mode="rerun"
  if [[ "$resume_requested" == "true" ]]; then
    resume_reason="explicit rerun from the beginning was requested"
  fi
else
  resume_mode="resume"
  resume_reason="resume requested from a later stage"
fi

retry_requested_stage="$retry_stage"
if [[ -n "$retry_stage" ]]; then
  retry_requested="true"
  if [[ "$start_from" == "build" ]]; then
    start_from="$retry_stage"
    if ! resume_effective_start_from="$(normalize_start_from "$start_from")"; then
      echo "Unsupported --retry-stage value: $retry_stage" >&2
      exit 1
    fi
    resume_requested_start_from="$start_from"
    resume_requested="true"
    resume_mode="resume"
    resume_reason="retry request reuses the stage start path"
  elif [[ "$start_from" != "$retry_stage" ]]; then
    echo "--retry-stage and --start-from must refer to the same stage when both are provided" >&2
    exit 1
  fi
fi

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

validate_retry_request
validate_resume_request

top_level_status="running"
current_stage="$resume_effective_start_from"
next_step="${resume_effective_start_from}_pending"
failure_json="null"
write_state

case "$resume_effective_start_from" in
  build)
    validate_prerequisites

    build_attempt_count=$((build_attempt_count + 1))
    safe_prepare_status="running"
    build_status="running"
    top_level_status="running"
    current_stage="build"
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
      printf '[mixpg] start_from requested: %s\n' "$resume_requested_start_from"
      printf '[mixpg] start_from effective: %s\n' "$resume_effective_start_from"
    } >"$build_log"

    if "${build_command[@]}" >>"$build_log" 2>&1; then
      safe_prepare_status="completed"
      build_status="completed"
      build_exit_code=0
      input_copy_status="copied"
      top_level_status="running"
      next_step="preprocess_pending"
      failure_json="null"
    else
      build_exit_code=$?
      safe_prepare_status="failed"
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
    ;;
  preprocess)
    preprocess_attempt_count=$((preprocess_attempt_count + 1))
    validate_preprocess_inputs
    run_preprocess_stage
    if [[ "$preprocess_status" == "completed" ]]; then
      validate_driver_inputs
      run_driver_stage
    fi
    if [[ "$driver_status" == "completed" ]]; then
      validate_postprocess_inputs
      run_postprocess_stage
    fi
    ;;
  driver)
    driver_attempt_count=$((driver_attempt_count + 1))
    validate_driver_inputs
    run_driver_stage
    if [[ "$driver_status" == "completed" ]]; then
      validate_postprocess_inputs
      run_postprocess_stage
    fi
    ;;
  postprocess)
    postprocess_attempt_count=$((postprocess_attempt_count + 1))
    validate_postprocess_inputs
    run_postprocess_stage
    ;;
esac

echo "[mixpg] build stage status: $build_status"
echo "[mixpg] preprocess stage status: $preprocess_status"
echo "[mixpg] driver stage status: $driver_status"
echo "[mixpg] postprocess stage status: $postprocess_status"
echo "[mixpg] start_from requested: $resume_requested_start_from"
echo "[mixpg] start_from effective: $resume_effective_start_from"
echo "[mixpg] state file: $state_file"
echo "[mixpg] build log: $build_log"
echo "[mixpg] preprocess log: $preprocess_log"
echo "[mixpg] driver log: $driver_log"
echo "[mixpg] postprocess log: $postprocess_log"
