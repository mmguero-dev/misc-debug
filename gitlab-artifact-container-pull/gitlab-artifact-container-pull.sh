#!/usr/bin/env bash
# GitLab Artifacts Download Script
# Simple script to download job artifacts from GitLab
pushd "$(dirname "$(realpath "$0")")" >/dev/null 2>&1
pwd
if [[ -f ./globalenviron ]]; then
    source globalenviron
elif [[ -f ./.envrc ]]; then
    source .envrc
fi
popd >/dev/null 2>&1

# GitLab configuration
GITLAB_ACCESS_TOKEN=${GITLAB_ACCESS_TOKEN:-}
CONTAINER_ENGINE=${CONTAINER_ENGINE:-docker}
DOCKER_IMAGE_TAG=${DOCKER_IMAGE_TAG:-}
GITLAB_URL=${GITLAB_URL:-}
JOB_ID=${JOB_ID:-}
PROJECT_ID=${PROJECT_ID:-}

# Output configuration
OUTPUT_DIR="${OUTPUT_DIR:-./artifacts}"         # default ./artifacts if unset
CLEAN_OUTPUT_DIR="${CLEAN_OUTPUT_DIR:-true}"
EXTRACT_ARTIFACTS="${EXTRACT_ARTIFACTS:-true}"  # default true if unset

# Docker configuration
LOAD_IMAGE="${LOAD_IMAGE:-true}"  # default true if unset

declare -A SERVICE_TO_PROJECT_ID_MAP=(
# Malcolm IB project IDs
  [api]=18631
  [arkime]=18632
  [dashboard_helper]=18633
  [dashboards]=18634
  [dirinit]=18635
  [file_monitor]=18636
  [file_upload]=18637
  [filebeat]=18638
  [filescan]=18796
  [freq]=18639
  [htadmin]=18640
  [keycloak]=18641
  [logstash_oss]=18642
  [netbox]=18643
  [nginx]=18644
  [opensearch]=18645
  [pcap_capture]=18646
  [pcap_monitor]=18647
  [postgresql]=18648
  [redis]=18649
  [strelka_backend]=18797
  [strelka_frontend]=18798
  [strelka_manager]=18799
  [suricata]=18650
  [zeek]=18651
#Elastic IB project IDs
  [distribution]=18630
  [edr-agent-store]=18470
  [elastic-agent-fips]=18468
  [elasticsearch-fips]=18062
  [filebeat-fips]=18469
  [kibana-fips]=18063
# Other IB project IDs
  [flux-cli]=18776
  [gitea]=18694
  [kafka]=18626
  [kafka-ui]=18627
  [kafka-operator]=18628
  [mariadb-galera]=18699
  [mariadb-operator]=18719
  [misp-core]=17848
  [misp-modules]=18066
  [pgpool]=18766
  [postgresql-repmgr]=18767
  [valkey]=18768
  [wiki]=18629
)

# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: ${0} [options]
Options:
  -g, --gitlab URL          GitLab URL
  -p, --project-id ID       GitLab project ID (sets PROJECT_ID)
  -j, --job-id ID           GitLab job ID (sets JOB_ID)
  -t, --tag TAG             Docker image tag to apply after loading (sets DOCKER_IMAGE_TAG)
  -k, --token TOKEN         GitLab access token (sets GITLAB_ACCESS_TOKEN)
  -h, --help                Show this help and exit
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--gitlab)
      GITLAB_URL="$2"
      shift 2
      ;;
    -p|--project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    -j|--job-id)
      JOB_ID="$2"
      shift 2
      ;;
    -t|--tag)
      DOCKER_IMAGE_TAG="$2"
      shift 2
      ;;
    -k|--token)
      GITLAB_ACCESS_TOKEN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

prompt_select_project() {
  local -a services
  mapfile -t services < <(printf '%s\n' "${!SERVICE_TO_PROJECT_ID_MAP[@]}" | sort)
  echo ""
  echo "Select a project:"
  local i=1
  for svc in "${services[@]}"; do
    printf "  %2d) %s (project ID: %s)\n" "$i" "$svc" "${SERVICE_TO_PROJECT_ID_MAP[$svc]}"
    ((i++))
  done
  echo ""
  read -p "Enter number or service name: " selection

  if [[ "$selection" =~ ^[0-9]+$ ]]; then
    if (( selection >= 1 && selection <= ${#services[@]} )); then
      PROJECT_ID="${SERVICE_TO_PROJECT_ID_MAP[${services[$((selection-1))]}]}"
      log_info "PROJECT_ID set to ${PROJECT_ID} (${services[$((selection-1))]})"
    else
      log_error "Invalid selection: $selection"
      exit 1
    fi
  else
    selection="${selection//-/_}"
    if [[ -n "${SERVICE_TO_PROJECT_ID_MAP[$selection]+x}" ]]; then
      PROJECT_ID="${SERVICE_TO_PROJECT_ID_MAP[$selection]}"
      log_info "PROJECT_ID set to ${PROJECT_ID} ($selection)"
    else
      log_error "Unknown service: $selection"
      exit 1
    fi
  fi
  export PROJECT_ID
}

prompt_if_unset() {
  local var_name="$1"
  local prompt_msg="${2:-Enter value for ${var_name}:}"

  # Check if the variable is unset or empty
  if [[ -z "${!var_name}" ]]; then
    # Use -s for the access token to hide typing
    if [[ "${var_name}" == "GITLAB_ACCESS_TOKEN" ]]; then
      read -sp "${prompt_msg}" input_value
      echo "" # Add a newline since 'read -s' doesn't provide one
    else
      read -p "${prompt_msg}" input_value
    fi

    export "${var_name}"="${input_value}"

    # Only echo the value if it's NOT the access token
    if [[ "${var_name}" != "GITLAB_ACCESS_TOKEN" ]]; then
      log_info "${var_name} has been set to '${input_value}'"
    else
      log_info "${var_name} has been set (value hidden for security)"
    fi
  else
    # Mask the token even when it's already set
    if [[ "${var_name}" == "GITLAB_ACCESS_TOKEN" ]]; then
      log_info "${var_name} is already set (value hidden)"
    else
      log_info "${var_name} is already set to '${!var_name}'"
    fi
  fi
}

# Check if required tools are available
check_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        exit 1
    fi
    if [[ "${EXTRACT_ARTIFACTS}" = "true" ]] && ! command -v unzip >/dev/null 2>&1; then
        log_error "unzip is required but not installed"
        exit 1
    fi
    if [[ "${LOAD_IMAGE}" = "true" ]] && ! command -v "${CONTAINER_ENGINE}" >/dev/null 2>&1; then
        log_error "${CONTAINER_ENGINE} is required but not installed"
        exit 1
    fi
}

# Validate configuration
validate_config() {
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID is not set"
        exit 1
    fi
    if [[ -z "${JOB_ID}" ]]; then
        log_error "JOB_ID is not set"
        exit 1
    fi
    if [[ -z "${GITLAB_ACCESS_TOKEN}" ]]; then
        log_error "GITLAB_ACCESS_TOKEN is not set"
        exit 1
    fi
}

# Get last job matching the given name
get_latest_job_id_by_name() {
  local name="$1"
  local page=1
  while :; do
    # Fetch once per page; if GitLab returns HTML/errors, jq will fail and we abort.
    local body
    body="$(curl -fsSL -H "Authorization: Bearer ${GITLAB_ACCESS_TOKEN}" \
      "${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/jobs?per_page=100&page=${page}")" || return 2

    # If jq chokes, stop immediately.
    local id
    id="$(jq -er --arg name "${name}" '
      (map(select(.name==$name)) | .[0].id) // empty
    ' 2>/dev/null <<<"${body}")" || return 3

    if [[ -n "${id}" ]]; then
      printf '%s\n' "${id}"
      return 0
    fi

    # No match on this page. If the page is empty, we’re done.
    jq -e 'length > 0' <<<"${body}" >/dev/null || return 1
    page=$((page+1))
  done
}

# Get job information
get_job_info() {
    job_url="${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}"
    log_info "Fetching job information from ${job_url}"

    # Use -L to follow redirects and save to temp file to handle newlines properly
    temp_file=$(mktemp)
    curl -s -L -H "Authorization: Bearer ${GITLAB_ACCESS_TOKEN}" "${job_url}" -o "${temp_file}"

    # Check if response is valid JSON
    if ! cat "${temp_file}" | jq . >/dev/null 2>&1; then
        log_error "Invalid JSON response from GitLab API"
        log_info "Response: $(cat "${temp_file}")"
        rm -f "${temp_file}"
        exit 1
    fi

    # Read the response from the temp file
    response=$(cat "${temp_file}")
    rm -f "${temp_file}"

    if echo "${response}" | jq -e '.message' >/dev/null 2>&1; then
        error_msg=$(echo "${response}" | jq -r '.message')
        log_error "Failed to fetch job info: ${error_msg}"
        exit 1
    fi

    job_name=$(echo "${response}" | jq -r '.name')
    job_status=$(echo "${response}" | jq -r '.status')
    log_info "Job: ${job_name} (Status: ${job_status})"

    if [[ "${job_status}" != "success" ]]; then
        log_warn "Job status is '${job_status}', not 'success'. Artifacts may not be available."
    fi
}

# Download job artifacts
download_artifacts() {
    artifacts_url="${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}/artifacts"
    output_file="${OUTPUT_DIR}/artifacts.zip"

    # Clean previous run if requested
    if [[ "${CLEAN_OUTPUT_DIR}" = "true" ]] && [[ -d "${OUTPUT_DIR}" ]]; then
        log_info "Cleaning output directory: ${OUTPUT_DIR}"
        rm -rf "${OUTPUT_DIR}"
    fi

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    # Download artifacts (follow redirects)
    log_info "Downloading artifacts from job ${JOB_ID}..."
    http_code=$(curl -s -L -w "%{http_code}" -o "${output_file}" -H "Authorization: Bearer ${GITLAB_ACCESS_TOKEN}" "${artifacts_url}")

    if [[ "${http_code}" -eq 404 ]]; then
        log_error "Artifacts not found for job ${JOB_ID}. The job may not have artifacts or they may have expired."
        exit 1
    elif [[ "${http_code}" -eq 401 ]]; then
        log_error "Authentication failed. Please check your access token."
        exit 1
    elif [[ "${http_code}" -ne 200 ]]; then
        log_error "Failed to download artifacts. HTTP status: ${http_code}"
        exit 1
    fi

    log_info "Artifacts downloaded to: ${output_file}"

    if [[ "${EXTRACT_ARTIFACTS}" = "true" ]]; then
        log_info "Extracting artifacts..."
        unzip -q "${output_file}" -d "${OUTPUT_DIR}"
        log_info "Artifacts extracted to: ${OUTPUT_DIR}"

        # List extracted files
        log_info "Extracted files:"
        find "${OUTPUT_DIR}" -type f -not -name "artifacts.zip" | head -20
        file_count=$(find "${OUTPUT_DIR}" -type f -not -name "artifacts.zip" | wc -l)
        if [[ "${file_count}" -gt 20 ]]; then
            log_info "... and $((file_count - 20)) more files"
        fi

        # Load Docker image if enabled
        if [[ "${LOAD_IMAGE}" = "true" ]]; then
            load_docker_image
        fi
    else
        log_info "Artifacts saved as zip file: ${output_file}"
    fi
}

# Load Docker image from extracted artifacts
load_docker_image() {
    log_info "Looking for ${CONTAINER_ENGINE} image in extracted artifacts..."

    # Prefer tars under ci-artifacts/tar/... if present
    tar_file=$(find "${OUTPUT_DIR}" -path "*/ci-artifacts/tar/*/*.tar" -type f | head -1)
    if [[ -z "${tar_file}" ]]; then
        log_warn "No tar found under ci-artifacts/tar/; falling back to any *.tar in ${OUTPUT_DIR}"
        tar_file=$(find "${OUTPUT_DIR}" -type f -name "*.tar" | head -1)
    fi
    if [[ -z "${tar_file}" ]]; then
        log_error "No ${CONTAINER_ENGINE} tar file found in artifacts"
        log_info "Searched in: ${OUTPUT_DIR}"
        return 1
    fi

    log_info "Using tar file: ${tar_file}"

    # If no tag was provided, derive one from the tar filename
    if [[ -z "${DOCKER_IMAGE_TAG}" ]]; then
        tar_base="$(basename "${tar_file}")"     # e.g. misp-modules-4698286-amd64.tar
        tar_noext="${tar_base%.tar}"             # misp-modules-4698286-amd64

        # Try to strip trailing "-<digits>..." (e.g. "-4698286-amd64")
        default_name="${tar_noext%%-[0-9]*}"     # -> misp-modules

        # If nothing was stripped (no -<digits> pattern), fall back to dropping last dash segment
        if [[ "${default_name}" = "${tar_noext}" ]]; then
            default_name="${tar_noext%-*}"
        fi

        # Append our marker suffix and :latest tag
        DOCKER_IMAGE_TAG="${default_name}-cibuild:latest"
        export DOCKER_IMAGE_TAG
        log_info "No ${CONTAINER_ENGINE} image tag provided; defaulting to: ${DOCKER_IMAGE_TAG}"
    fi

    log_info "Loading ${CONTAINER_ENGINE} image..."
    load_output=$("${CONTAINER_ENGINE}" load -i "${tar_file}" 2>&1)
    rc=$?
    echo "${load_output}"
    if [[ ${rc} -ne 0 ]]; then
        log_error "Failed to load ${CONTAINER_ENGINE} image from: ${tar_file}"
        return 1
    fi

    # 1) Try to get a named image from "Loaded image: repo/name:tag"
    loaded_image=$(echo "${load_output}" | awk -F': ' '/Loaded image:/ {print $2}' | head -1)

    # 2) If no name, look for "Loaded image ID: sha256:..."
    if [[ -z "${loaded_image}" ]]; then
        image_id=$(echo "${load_output}" | awk -F'ID: ' '/Loaded image ID:/ {print $2}' | head -1)
        if [[ -z "${image_id}" ]]; then
            log_error "${CONTAINER_ENGINE} load output did not contain 'Loaded image:' or 'Loaded image ID:'; not tagging anything."
            return 1
        fi
        loaded_image="${image_id}"
    fi

    log_info "Loaded image reference: ${loaded_image}"
    log_info "Tagging image as: ${DOCKER_IMAGE_TAG}"
    if "${CONTAINER_ENGINE}" tag "${loaded_image}" "${DOCKER_IMAGE_TAG}"; then
        log_info "Successfully tagged image as: ${DOCKER_IMAGE_TAG}"
    else
        log_error "Failed to tag image"
        return 1
    fi

    DOCKER_INSPECT_INFO="$(${CONTAINER_ENGINE} inspect "${DOCKER_IMAGE_TAG}" | jq)"
    log_info "${DOCKER_INSPECT_INFO}"
}

# Main execution
main() {
    log_info "GitLab Artifacts Downloader"
    log_info "=========================="
    validate_config
    check_dependencies
    log_info "Configuration:"
    log_info "  GitLab URL: ${GITLAB_URL}"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Job ID: ${JOB_ID}"
    log_info "  Output Directory: ${OUTPUT_DIR}"
    log_info "  Extract Artifacts: ${EXTRACT_ARTIFACTS}"
    log_info "  Load ${CONTAINER_ENGINE} Image: ${LOAD_IMAGE}"

    if [[ "${LOAD_IMAGE}" = "true" ]]; then
        if [[ -n "${DOCKER_IMAGE_TAG}" ]]; then
            log_info "  ${CONTAINER_ENGINE} Image Tag (preconfigured): ${DOCKER_IMAGE_TAG}"
        else
            log_info "  ${CONTAINER_ENGINE} Image Tag: (will be derived from artifacts tar)"
        fi
    fi

    get_job_info
    download_artifacts
    log_info "Download completed successfully!"
}

# If ${PROJECT_ID} isn't all digits, treat it as a name and map via the SERVICE_TO_PROJECT_ID_MAP array
# Skip when empty - using empty subscript causes "bad array subscript" error
if [[ -n "${PROJECT_ID}" ]] && [[ ! "${PROJECT_ID}" =~ ^[0-9]+$ ]]; then
  PROJECT_ID="${PROJECT_ID//-/_}"
  if [[ -n "${SERVICE_TO_PROJECT_ID_MAP[${PROJECT_ID}]+x}" ]]; then
    PROJECT_ID="${SERVICE_TO_PROJECT_ID_MAP[${PROJECT_ID}]}"
  else
    PROJECT_ID=
  fi
fi

prompt_if_unset "GITLAB_URL" "Please enter the GitLab URL: "
prompt_if_unset "GITLAB_ACCESS_TOKEN" "Please enter your GitLab access token: "
if [[ -z "${PROJECT_ID}" ]]; then
  prompt_select_project
else
  log_info "PROJECT_ID is already set to '${PROJECT_ID}'"
fi

# if ${JOB_ID} isn't all digits, treat it as a job name to look up (the most recent job with that name)
if [[ -n "${JOB_ID}" ]] && [[ ! "${JOB_ID}" =~ ^[0-9]+$ ]]; then
  OLD_JOB_ID=${JOB_ID}
  JOB_ID="$(get_latest_job_id_by_name "${OLD_JOB_ID}")"
  [[ -n "${JOB_ID}" ]] && \
    log_info "Found \"${JOB_ID}\" as most recent job for \"${OLD_JOB_ID}\"" || \
    log_warn "Did not find most recent job for \"${OLD_JOB_ID}\""
fi

prompt_if_unset "JOB_ID" "Please enter the GitLab job ID from repo: "

# Run main function
main