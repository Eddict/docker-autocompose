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
# Optional: control decomposerize script output and other settings
# Use --script to enable saving the decomposerize output as a shell script (default is disabled)
# Use --docker-image <image> to override the Docker image
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

# Pull latest image version
debug_echo "Pulling latest image version"
docker pull "$DOCKER_IMAGE"
debug_echo "Pulled $DOCKER_IMAGE successfully"

# List all container names (including stopped)
containers=$(docker ps -a --format '{{.Names}}')

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

  # Generate docker-compose.yaml for this container
  debug_echo "Running autocompose for $container"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "$DOCKER_IMAGE" autocompose "$container" > "$container/docker-compose.yaml"
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
