#!/usr/bin/env bash
set -euo pipefail

export ROS_MASTER_URI="${ROS_MASTER_URI:-http://127.0.0.1:${ROS_MASTER_PORT:-11311}}"
export ROS_HOSTNAME="${ROS_HOSTNAME:-127.0.0.1}"
export ROS_LOG_DIR="${ROS_LOG_DIR:-/logs/ros}"

mkdir -p "${ROS_LOG_DIR}" "${CALIBRATION_BAG_DIR:-/data/bags}" "${CALIBRATION_INTRINSIC_OUTPUT_DIR:-/data/intrinsics}" 2>/dev/null || true

source /opt/ros/noetic/setup.bash
if [[ -f /opt/livox_msg_ws/install/setup.bash ]]; then
  source /opt/livox_msg_ws/install/setup.bash
fi

usage() {
  cat <<'HELP'
Usage:
  calibration-capture check
  calibration-capture topics
  calibration-capture convert
  calibration-capture record [duration_sec] [bag_name]
  calibration-capture intrinsics-check
  calibration-capture intrinsics-calibrate [columns rows square_m [image_topic [camera_namespace]]]

The container records ROS1 bags for offline LiDAR-camera calibration. It does
not open the RGB camera or LiDAR directly; make sure the required ROS topics
are already published on the host ROS master.

Chessboard columns and rows are inner-corner counts. A 9x13-square board has
12x8 inner corners, so use 12 8 with a 0.020 m square size when applicable.
HELP
}

topic_ready() {
  local topic="$1"
  timeout 3 rostopic info "$topic" >/dev/null 2>&1
}

wait_topic() {
  local topic="$1"
  local timeout_sec="${2:-20}"
  local elapsed=0
  until topic_ready "$topic"; do
    if (( elapsed >= timeout_sec )); then
      echo "Timed out waiting for topic: ${topic}" >&2
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

topic_has_publisher() {
  local topic="$1"
  timeout 3 rostopic info "$topic" 2>/dev/null | awk '
    /^Publishers:/ { in_publishers = 1; next }
    /^Subscribers:/ { in_publishers = 0 }
    in_publishers && /\*/ { found = 1 }
    END { exit found ? 0 : 1 }
  '
}

start_converter() {
  python3 /opt/calibration-capture/livox_custom_to_pointcloud2.py \
    --input-topic "${CALIBRATION_LIVOX_INPUT_TOPIC:-/livox/lidar}" \
    --output-topic "${CALIBRATION_POINTS_TOPIC:-/calibration/livox/points}" \
    --frame-id "${CALIBRATION_POINTS_FRAME_ID:-livox_frame}" &
  CONVERTER_PID=$!
}

stop_converter() {
  if [[ -n "${CONVERTER_PID:-}" ]]; then
    kill "${CONVERTER_PID}" >/dev/null 2>&1 || true
    wait "${CONVERTER_PID}" >/dev/null 2>&1 || true
  fi
}

camera_namespace_for_image() {
  local image_topic="$1"
  if [[ -n "${CALIBRATION_INTRINSIC_CAMERA_NS:-}" ]]; then
    echo "${CALIBRATION_INTRINSIC_CAMERA_NS}"
    return 0
  fi
  case "${image_topic}" in
    */image_raw) echo "${image_topic%/image_raw}" ;;
    */image_rect) echo "${image_topic%/image_rect}" ;;
    */image_rect_color) echo "${image_topic%/image_rect_color}" ;;
    *) dirname "${image_topic}" ;;
  esac
}

check_intrinsics_tools() {
  if ! rospack find camera_calibration >/dev/null 2>&1; then
    echo "ROS package camera_calibration is missing; rebuild calibration-capture." >&2
    return 1
  fi
  if ! python3 -c 'import cv2, cv_bridge' >/dev/null 2>&1; then
    echo "OpenCV/cv_bridge Python modules are missing; rebuild calibration-capture." >&2
    return 1
  fi
}

ensure_pointcloud_topic() {
  wait_topic "${CALIBRATION_LIVOX_INPUT_TOPIC:-/livox/lidar}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
  if ! topic_has_publisher "${CALIBRATION_POINTS_TOPIC:-/calibration/livox/points}"; then
    start_converter
    trap stop_converter EXIT INT TERM
  fi
  wait_topic "${CALIBRATION_POINTS_TOPIC:-/calibration/livox/points}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
}

case "${1:-help}" in
  help|--help|-h)
    usage
    ;;
  topics)
    echo "ROS_MASTER_URI=${ROS_MASTER_URI}"
    rostopic list
    ;;
  check)
    echo "ROS_MASTER_URI=${ROS_MASTER_URI}"
    echo "Checking source topics..."
    wait_topic "${CALIBRATION_IMAGE_TOPIC:-/usb_cam/image_raw}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    wait_topic "${CALIBRATION_CAMERA_INFO_TOPIC:-/usb_cam/camera_info}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    ensure_pointcloud_topic
    echo "Required image, camera info, and point cloud topics are available."
    ;;
  intrinsics-check)
    echo "ROS_MASTER_URI=${ROS_MASTER_URI}"
    echo "DISPLAY=${DISPLAY:-}"
    check_intrinsics_tools
    wait_topic "${CALIBRATION_IMAGE_TOPIC:-/usb_cam/image_raw}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    wait_topic "${CALIBRATION_CAMERA_INFO_TOPIC:-/usb_cam/camera_info}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    echo "Intrinsic calibration tools and image topics are available."
    ;;
  intrinsics-calibrate)
    columns="${2:-${CALIBRATION_INTRINSIC_PATTERN_COLUMNS:-12}}"
    rows="${3:-${CALIBRATION_INTRINSIC_PATTERN_ROWS:-8}}"
    square_m="${4:-${CALIBRATION_INTRINSIC_SQUARE_M:-0.020}}"
    image_topic="${5:-${CALIBRATION_IMAGE_TOPIC:-/usb_cam/image_raw}}"
    camera_ns="${6:-$(camera_namespace_for_image "${image_topic}")}"
    output_dir="${CALIBRATION_INTRINSIC_OUTPUT_DIR:-/data/intrinsics}"

    check_intrinsics_tools
    wait_topic "${image_topic}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    wait_topic "${camera_ns}/camera_info" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    mkdir -p "${output_dir}"
    export TMPDIR="${output_dir}"

    echo "Starting camera intrinsic calibration."
    echo "Board inner corners: ${columns}x${rows}; square: ${square_m} m"
    echo "Image topic: ${image_topic}; camera namespace: ${camera_ns}"
    echo "After the GUI opens: move the board through the image, then click CALIBRATE and SAVE."
    echo "Expected result archive: ${output_dir}/calibrationdata.tar.gz"
    exec rosrun camera_calibration cameracalibrator.py \
      --size "${columns}x${rows}" \
      --square "${square_m}" \
      --no-service-check \
      image:="${image_topic}" \
      camera:="${camera_ns}"
    ;;
  convert)
    exec python3 /opt/calibration-capture/livox_custom_to_pointcloud2.py \
      --input-topic "${CALIBRATION_LIVOX_INPUT_TOPIC:-/livox/lidar}" \
      --output-topic "${CALIBRATION_POINTS_TOPIC:-/calibration/livox/points}" \
      --frame-id "${CALIBRATION_POINTS_FRAME_ID:-livox_frame}"
    ;;
  record)
    duration_sec="${2:-${CALIBRATION_DURATION_SEC:-15}}"
    bag_name="${3:-calib_$(date +%Y%m%d_%H%M%S)}"
    bag_dir="${CALIBRATION_BAG_DIR:-/data/bags}"
    bag_path="${bag_dir}/${bag_name}.bag"
    mkdir -p "${bag_dir}"

    wait_topic "${CALIBRATION_IMAGE_TOPIC:-/usb_cam/image_raw}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    wait_topic "${CALIBRATION_CAMERA_INFO_TOPIC:-/usb_cam/camera_info}" "${CALIBRATION_WAIT_TIMEOUT_SEC:-20}"
    ensure_pointcloud_topic

    topics=(
      "${CALIBRATION_IMAGE_TOPIC:-/usb_cam/image_raw}"
      "${CALIBRATION_CAMERA_INFO_TOPIC:-/usb_cam/camera_info}"
      "${CALIBRATION_POINTS_TOPIC:-/calibration/livox/points}"
    )
    if [[ "${CALIBRATION_RECORD_DEPTH:-false}" == "true" && -n "${CALIBRATION_DEPTH_TOPIC:-}" ]]; then
      topics+=("${CALIBRATION_DEPTH_TOPIC}")
    fi

    echo "Recording ${duration_sec}s to ${bag_path}"
    set +e
    timeout --signal=INT --kill-after=5 "${duration_sec}" rosbag record -O "${bag_path}" "${topics[@]}"
    record_rc=$?
    set -e
    if [[ "${record_rc}" != "0" && "${record_rc}" != "124" && "${record_rc}" != "130" ]]; then
      exit "${record_rc}"
    fi
    echo "Saved ${bag_path}"
    ;;
  *)
    exec "$@"
    ;;
esac
