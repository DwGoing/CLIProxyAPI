#!/usr/bin/env bash
#
# podman-build.sh - Linux/macOS Podman Build Script
#
# This script mirrors the simple docker-build.sh flow, but uses Podman and a
# Podman-specific compose file so SELinux relabeling works on Linux hosts.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_COMPOSE_FILE="${PROJECT_DIR}/temp/podman-compose.yml"
COMPOSE_CMD=()

detect_compose_cmd() {
  if command -v podman-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(podman-compose)
    return
  fi

  if command -v podman >/dev/null 2>&1 && podman help compose >/dev/null 2>&1; then
    COMPOSE_CMD=(podman compose)
    return
  fi

  echo "Error: Podman Compose is required. Install either 'podman compose' support or 'podman-compose'."
  exit 1
}

write_local_compose_file() {
  local pull_policy="$1"

  mkdir -p "$(dirname "${LOCAL_COMPOSE_FILE}")"
  cat > "${LOCAL_COMPOSE_FILE}" <<EOF
services:
  cli-proxy-api:
    image: \${CLI_PROXY_IMAGE:-eceasy/cli-proxy-api:latest}
    pull_policy: ${pull_policy}
    build:
      context: ${PROJECT_DIR}
      dockerfile: Dockerfile
      args:
        GOPROXY: \${GOPROXY:-https://proxy.golang.org,direct}
        VERSION: \${VERSION:-dev}
        COMMIT: \${COMMIT:-none}
        BUILD_DATE: \${BUILD_DATE:-unknown}
    container_name: cli-proxy-api
    environment:
      DEPLOY: \${DEPLOY:-}
    ports:
      - "8317:8317"
      - "8085:8085"
      - "1455:1455"
      - "54545:54545"
      - "51121:51121"
      - "11451:11451"
    volumes:
      - "\${CLI_PROXY_CONFIG_PATH:-${PROJECT_DIR}/config.yaml}:/CLIProxyAPI/config.yaml:Z"
      - "\${CLI_PROXY_AUTH_PATH:-${PROJECT_DIR}/auths}:/root/.cli-proxy-api:Z"
      - "\${CLI_PROXY_LOG_PATH:-${PROJECT_DIR}/logs}:/CLIProxyAPI/logs:Z"
      - "\${CLI_PROXY_PLUGIN_PATH:-${PROJECT_DIR}/plugins}:/CLIProxyAPI/plugins:Z"
    restart: always
EOF
}

remove_existing_container() {
  if podman container exists cli-proxy-api; then
    echo "Removing existing cli-proxy-api container..."
    podman rm -f cli-proxy-api
  fi
}

if [[ "${1:-}" != "" ]]; then
  echo "Error: unknown option '${1}'."
  echo "Usage: ./podman-build.sh"
  exit 1
fi

detect_compose_cmd

# --- Step 1: Choose Environment ---
echo "Please select an option:"
echo "1) Run using Pre-built Image (Recommended)"
echo "2) Build from Source and Run (For Developers)"
read -r -p "Enter choice [1-2]: " choice

case "$choice" in
  1) pull_policy="always" ;;
  2) pull_policy="never" ;;
  *)
    echo "Invalid choice. Please enter 1 or 2."
    exit 1
    ;;
esac

write_local_compose_file "${pull_policy}"

# --- Step 2: Execute based on choice ---
case "$choice" in
  1)
    echo "--- Running with Pre-built Image ---"
    remove_existing_container
    "${COMPOSE_CMD[@]}" -f "${LOCAL_COMPOSE_FILE}" up -d --remove-orphans --no-build
    echo "Services are starting from remote image."
    echo "Run '${COMPOSE_CMD[*]} logs -f' to see the logs."
    ;;
  2)
    echo "--- Building from Source and Running ---"

    VERSION="${VERSION:-$(git describe --tags --always --dirty)}"
    COMMIT="$(git rev-parse --short HEAD)"
    BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    echo "Building with the following info:"
    echo "  Version: ${VERSION}"
    echo "  Commit: ${COMMIT}"
    echo "  Build Date: ${BUILD_DATE}"
    echo "  Image: localhost/cli-proxy-api:${VERSION}"
    echo "----------------------------------------"

    export CLI_PROXY_IMAGE="localhost/cli-proxy-api:${VERSION}"

    echo "Building the Podman image..."
    "${COMPOSE_CMD[@]}" -f "${LOCAL_COMPOSE_FILE}" build \
      --build-arg VERSION="${VERSION}" \
      --build-arg COMMIT="${COMMIT}" \
      --build-arg BUILD_DATE="${BUILD_DATE}"

    echo "Starting the services..."
    remove_existing_container
    "${COMPOSE_CMD[@]}" -f "${LOCAL_COMPOSE_FILE}" up -d --remove-orphans

    echo "Build complete. Services are starting."
    echo "Run '${COMPOSE_CMD[*]} logs -f' to see the logs."
    ;;
esac
