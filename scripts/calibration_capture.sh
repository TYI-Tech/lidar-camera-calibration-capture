#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-lidar-camera-calibration}"
export COMPOSE_PROJECT_NAME
CALIBRATION_RUN_UID="${CALIBRATION_RUN_UID:-$(id -u)}"
CALIBRATION_RUN_GID="${CALIBRATION_RUN_GID:-$(id -g)}"
export CALIBRATION_RUN_UID CALIBRATION_RUN_GID

usage() {
  cat <<'HELP'
Usage:
  ./scripts/calibration_capture.sh init
  ./scripts/calibration_capture.sh audit
  ./scripts/calibration_capture.sh pull
  ./scripts/calibration_capture.sh build
  ./scripts/calibration_capture.sh check
  ./scripts/calibration_capture.sh topics
  ./scripts/calibration_capture.sh record [duration_sec] [bag_name]
  ./scripts/calibration_capture.sh intrinsics-check
  ./scripts/calibration_capture.sh intrinsics-calibrate [columns rows square_m [image_topic [camera_namespace]]]
  ./scripts/calibration_capture.sh shell

Quick flow:
  cp .env.example .env
  ./scripts/calibration_capture.sh build
  ./scripts/calibration_capture.sh check
  ./scripts/calibration_capture.sh record 15 calib_01

For a 9x13-square chessboard with 0.020 m squares:
  ./scripts/calibration_capture.sh intrinsics-calibrate 12 8 0.020 /usb_cam/image_raw /usb_cam
HELP
}

compose() {
  docker compose -f docker-compose.yml "$@"
}

prepare_dirs() {
  mkdir -p calibration_data/bags calibration_data/intrinsics logs/calibration-capture/ros
}

audit_public_release() {
  local failed=0
  local patterns
  patterns='(AKIA|BEGIN .*PRIVATE|PRIVATE KEY|secret|token|password|passwd|fingerprint|refreshToken|accessToken|crpi-|aliyun|personal|192\.168\.|10\.[0-9]+\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|/home/[^ ]+|uav-nx|richard)'

  echo "Checking for files that should not be published..."
  if find . \( -path './.git' -o -path './calibration_data' -o -path './logs' \) -prune -o \
      \( -name '.env' -o -name '*.bag' -o -name '*.bag.active' -o -name '*.pyc' \) -print | grep -q .; then
    find . \( -path './.git' -o -path './calibration_data' -o -path './logs' \) -prune -o \
      \( -name '.env' -o -name '*.bag' -o -name '*.bag.active' -o -name '*.pyc' \) -print
    failed=1
  fi

  echo "Scanning tracked source tree for common private markers..."
  if grep -RInE "${patterns}" \
      --exclude-dir=.git \
      --exclude-dir=calibration_data \
      --exclude-dir=logs \
      --exclude='.env' \
      --exclude='*.bag' \
      --exclude='*.pyc' \
      --exclude='SECURITY.md' \
      --exclude='PUBLIC_RELEASE_CHECKLIST.md' \
      --exclude='calibration_capture.sh' \
      .; then
    failed=1
  fi

  if (( failed )); then
    echo "Audit failed. Review the findings before publishing." >&2
    return 1
  fi
  echo "Audit passed: no common private markers or publish-blocked files found."
}

case "${1:-help}" in
  help|--help|-h)
    usage
    ;;
  audit)
    audit_public_release
    ;;
  init)
    prepare_dirs
    if [[ ! -f .env ]]; then
      cp .env.example .env
      echo "Created .env from .env.example"
    fi
    ;;
  pull)
    compose pull --ignore-pull-failures calibration-capture
    ;;
  build)
    prepare_dirs
    compose build calibration-capture
    ;;
  check)
    prepare_dirs
    compose run --rm --no-deps calibration-capture check
    ;;
  topics)
    compose run --rm --no-deps calibration-capture topics
    ;;
  intrinsics-check)
    prepare_dirs
    compose run --rm --no-deps calibration-capture intrinsics-check
    ;;
  intrinsics-calibrate)
    shift
    prepare_dirs
    compose run --rm --no-deps calibration-capture intrinsics-calibrate "$@"
    ;;
  record)
    shift
    prepare_dirs
    compose run --rm --no-deps calibration-capture record "$@"
    ;;
  shell)
    prepare_dirs
    compose run --rm --no-deps calibration-capture bash
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
