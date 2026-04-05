#!/bin/bash

set -e

# Color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
# YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

info_echo() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

debug_echo() {
  if [ "$DEBUG" = true ]; then
    echo -e "${BLUE}[DEBUG]${NC} $1"
  fi
}

error_echo() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Set DEBUG=true for debug output (default is false)
DEBUG=${DEBUG:-false}
# Set DOCKER_IMAGE to override the default image used for autocompose and decomposerize
DOCKER_IMAGE=${DOCKER_IMAGE:-"ghcr.io/eddict/docker-compo-decompo:latest"}
# Set OUTPUT_SCRIPT=true to enable saving decomposerize output as a shell script (default is false)
OUTPUT_SCRIPT=${OUTPUT_SCRIPT:-false}
# Set DOCKER_CONTAINERS to filter for a specific container name (default is empty, meaning all containers)
DOCKER_CONTAINERS=${DOCKER_CONTAINERS:-""}
# Optional: control decomposerize script output and other settings
# Use --script to enable saving the decomposerize output as a shell script (default is disabled)
# Use --docker-image <image> to override the Docker image
# Use --containers <names> to filter for specific container names (comma-separated, e.g. web,db,cache)
# Use --debug to enable debug output
while [[ $# -gt 0 ]]; do
  case $1 in
    --script)
      OUTPUT_SCRIPT=true
      shift
      ;;
    --docker-image)
      DOCKER_IMAGE="$2"
      shift 2
      ;;
    --containers)
      DOCKER_CONTAINERS="$2"
      shift 2
      ;;
    --debug)
      DEBUG=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Print effective config at start
debug_echo "Effective DOCKER_IMAGE: $DOCKER_IMAGE"
debug_echo "Effective DEBUG: $DEBUG"
debug_echo "Effective DOCKER_CONTAINERS: $DOCKER_CONTAINERS"

# Pull latest image version
debug_echo "Pulling latest image version"
docker pull "$DOCKER_IMAGE"
debug_echo "Pulled $DOCKER_IMAGE successfully"

# List all container names (including stopped)
all_containers=$(docker ps -a --format '{{.Names}}')
containers="$all_containers"

# If DOCKER_CONTAINERS is set, filter containers to only those matching any of the comma-separated names (substring match)
if [ -n "$DOCKER_CONTAINERS" ]; then
  IFS=',' read -ra FILTERS <<< "$DOCKER_CONTAINERS"
  filtered_containers=""
  for filter in "${FILTERS[@]}"; do
    matches=$(echo "$all_containers" | grep "$filter" || true)
    if [ -n "$matches" ]; then
      while IFS= read -r match; do
        if [ -n "$match" ]; then
          filtered_containers="$filtered_containers\n$match"
        fi
      done <<< "$matches"
    fi
  done
  # Remove duplicates and empty lines
  containers=$(echo "$filtered_containers" | sort | uniq | sed '/^$/d')
fi


# --- Volume ownership logic ---
# Map: volume_name -> list of containers using it
declare -A volume_containers
# Map: container_name -> created timestamp
declare -A container_created
# Map: volume_name -> created timestamp
declare -A volume_created
# Map: volume_name -> owner container
declare -A volume_owner

# Gather volume usage and creation times (ALWAYS check all containers, not just filtered)
for container in $all_containers; do
  debug_echo "Inspecting container: $container for created time and volumes"
  # Get container created time
  c_created=$(docker inspect --format '{{.Created}}' "$container")
  debug_echo "Container $container created at: $c_created"
  container_created[$container]="$c_created"
  # Get volumes used by this container
  mounts=$(docker inspect --format '{{range .Mounts}}{{if eq .Type \"volume\"}}{{.Name}}\\n{{end}}{{end}}' "$container")
  debug_echo "Container $container uses volumes: $mounts"
  for v in $mounts; do
    debug_echo "Volume $v used by container $container"
    volume_containers[$v]="${volume_containers[$v]} $container"
  done
done

# Get volume creation times and try to determine owner by label
for v in "${!volume_containers[@]}"; do
  debug_echo "Inspecting volume: $v for creation time and labels"
  v_created=$(docker volume inspect --format '{{.CreatedAt}}' "$v" 2>/dev/null || echo "")
  debug_echo "Volume $v created at: $v_created"
  volume_created[$v]="$v_created"
  # Try to get owner from labels
  v_labels=$(docker volume inspect --format '{{json .Labels}}' "$v" 2>/dev/null || echo "")
  debug_echo "Volume $v labels: $v_labels"
  v_owner=""
  if [[ "$v_labels" != "null" && "$v_labels" != "" ]]; then
    compose_vol=$(echo "$v_labels" | grep -o '"com.docker.compose.volume":"[^"]*"' | cut -d'"' -f4)
    compose_proj=$(echo "$v_labels" | grep -o '"com.docker.compose.project":"[^"]*"' | cut -d'"' -f4)
    debug_echo "Volume $v compose_vol: $compose_vol, compose_proj: $compose_proj"
    if [[ -n "$compose_vol" && -n "$compose_proj" ]]; then
      # Owner is likely the container with matching project/volume
      for c in ${volume_containers[$v]}; do
        c_labels=$(docker inspect --format '{{json .Config.Labels}}' "$c" 2>/dev/null || echo "")
        debug_echo "Container $c labels: $c_labels"
        c_proj=$(echo "$c_labels" | grep -o '"com.docker.compose.project":"[^"]*"' | cut -d'"' -f4)
        c_vol=$(echo "$c_labels" | grep -o '"com.docker.compose.volume":"[^"]*"' | cut -d'"' -f4)
        debug_echo "Container $c compose_proj: $c_proj, compose_vol: $c_vol"
        if [[ "$c_proj" == "$compose_proj" && "$c_vol" == "$compose_vol" ]]; then
          v_owner="$c"
          debug_echo "Volume $v owner determined by label: $v_owner"
          break
        fi
      done
    fi
  fi
  # If not found by label, use creation time proximity
  if [[ -z "$v_owner" && -n "${volume_created[$v]}" ]]; then
    min_diff=9999999999
    for c in ${volume_containers[$v]}; do
      c_time=$(date -d "${container_created[$c]}" %s 2>/dev/null || echo 0)
      v_time=$(date -d "${volume_created[$v]}" +%s 2>/dev/null || echo 0)
      diff=$(( c_time > v_time ? c_time - v_time : v_time - c_time ))
      debug_echo "Comparing times for volume $v: container $c ($c_time), volume ($v_time), diff $diff"
      if (( diff < min_diff )); then
        min_diff=$diff
        v_owner="$c"
        debug_echo "Volume $v owner candidate by time: $v_owner (diff $diff)"
      fi
    done
  fi
  volume_owner[$v]="$v_owner"
  debug_echo "Final owner for volume $v: $v_owner"
done

# --- Main container processing loop ---
for container in $containers; do
  info_echo "Processing container: $container"
  mkdir -p "$container"
  debug_echo "Created directory: $container"

  # Get the image name for this container
  image_name=$(docker inspect --format='{{.Config.Image}}' "$container")
  debug_echo "Image for $container: $image_name"

  # Save docker image inspect output for reference
  docker image inspect "$image_name" > "$container/image-inspect.json" || debug_echo "Could not inspect image $image_name"
  debug_echo "Saved image inspect to $container/image-inspect.json"

  # Determine if this container is the owner of any shared volume
  createvolumes_flag=""
  mounts=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}\n{{end}}{{end}}' "$container")
  for v in $mounts; do
    # If this volume is used by multiple containers
    if [[ "${volume_containers[$v]}" =~ " " ]]; then
      if [[ "${volume_owner[$v]}" == "$container" ]]; then
        createvolumes_flag="-c"
        debug_echo "Container $container is owner of volume $v, will use --createvolumes"
      fi
    fi
  done

  # Generate docker-compose.yaml for this container
  debug_echo "Running autocompose for $container with $createvolumes_flag"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$DOCKER_IMAGE" autocompose $createvolumes_flag "$container" > "$container/docker-compose.yaml"
  debug_echo "Generated $container/docker-compose.yaml"

  # Validate the compose file without changing directories
  debug_echo "Validating $container/docker-compose.yaml with docker compose"
  if docker compose -f "$container/docker-compose.yaml" config > /dev/null; then
    info_echo "$container/docker-compose.yaml is valid."
    debug_echo "Validation for $container succeeded"

    # Run decomposerize on the generated YAML
    if [ "$OUTPUT_SCRIPT" = true ]; then
      docker run --rm -i "$DOCKER_IMAGE" decomposerize < "$container/docker-compose.yaml" > "$container/docker-run.sh"
      debug_echo "Generated $container/docker-run.sh"
    else
      output=$(docker run --rm -i "$DOCKER_IMAGE" decomposerize < "$container/docker-compose.yaml")
      if [ -z "$output" ]; then
        info_echo "docker run command for $container: (no output from decomposerize)"
      else
        echo "$output"
      fi
    fi
  else
    error_echo "$container/docker-compose.yaml has errors!"
    debug_echo "Validation for $container failed"
  fi
  debug_echo "Finished processing $container"
done
