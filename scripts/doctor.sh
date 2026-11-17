#!/usr/bin/env bash
set -euo pipefail

readonly DOCTOR_TIMEOUT_SECONDS=120
readonly DOCTOR_POLL_SECONDS=2
readonly HEALTHY_STATUS="healthy"
readonly MISSING_CONTAINER="no-container"

SERVICES=(mysql redis s3 mailpit traefik api media-worker)

enter_repo_root() {
  cd "$(dirname "$0")/.."
}

container_id() {
  docker compose ps -q "$1" 2>/dev/null | head -n 1 || true
}

health_status() {
  local id="$1" status
  if [[ -z "$id" ]]; then
    echo "$MISSING_CONTAINER"
    return 0
  fi
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$id" 2>/dev/null) || status="$MISSING_CONTAINER"
  echo "$status"
  return 0
}

service_status() {
  health_status "$(container_id "$1")"
}

is_healthy() {
  [[ "$(service_status "$1")" == "$HEALTHY_STATUS" ]]
}

unhealthy_list() {
  local service unhealthy=""
  for service in "${SERVICES[@]}"; do
    if ! is_healthy "$service"; then
      unhealthy="$unhealthy $service"
    fi
  done
  echo "$unhealthy"
}

all_healthy() {
  [[ -z "$(unhealthy_list)" ]]
}

print_row() {
  local service="$1" status
  status=$(service_status "$service")
  if [[ "$status" == "$HEALTHY_STATUS" ]]; then
    printf '%-14s %s\n' "$service" "$status"
  else
    printf '%-14s %s  <- NOT HEALTHY\n' "$service" "$status"
  fi
  return 0
}

print_table() {
  local service
  printf '%-14s %s\n' "service" "status"
  for service in "${SERVICES[@]}"; do
    print_row "$service"
  done
}

wait_for_services() {
  local deadline=$((SECONDS + DOCTOR_TIMEOUT_SECONDS))
  while ! all_healthy; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      return 1
    fi
    sleep "$DOCTOR_POLL_SECONDS"
  done
  return 0
}

main() {
  enter_repo_root
  if wait_for_services; then
    print_table
    echo "doctor: all ${#SERVICES[@]} services healthy"
    return 0
  fi
  print_table
  echo "doctor: timed out after ${DOCTOR_TIMEOUT_SECONDS}s; not healthy:$(unhealthy_list)" >&2
  return 1
}

main "$@"
