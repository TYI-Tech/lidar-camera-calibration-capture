ARG BASE_IMAGE=ros:noetic-ros-base-focal
FROM ${BASE_IMAGE}
ARG INSTALL_APT_DEPS=true

SHELL ["/bin/bash", "-lc"]
USER root

ENV CALIBRATION_HOME=/opt/calibration-capture
ENV ROS_LOG_DIR=/logs/ros
ENV DEBIAN_FRONTEND=noninteractive

RUN if [[ "${INSTALL_APT_DEPS}" == "true" ]]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        python3-empy \
        python3-opencv \
        ros-noetic-camera-calibration \
        ros-noetic-camera-info-manager \
        ros-noetic-message-generation \
        ros-noetic-message-runtime \
        ros-noetic-rosbag \
        ros-noetic-rospy \
        ros-noetic-sensor-msgs \
        ros-noetic-std-msgs; \
    fi \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/livox_msg_ws/src/livox_ros_driver2
COPY docker/calibration-capture/livox_ros_driver2 ./

RUN source /opt/ros/noetic/setup.bash \
    && cd /tmp/livox_msg_ws \
    && catkin_make install -DCMAKE_INSTALL_PREFIX=/opt/livox_msg_ws/install \
    && rm -rf /tmp/livox_msg_ws

WORKDIR /opt
COPY docker/calibration-capture ${CALIBRATION_HOME}

RUN chmod +x ${CALIBRATION_HOME}/entrypoint.sh ${CALIBRATION_HOME}/livox_custom_to_pointcloud2.py \
    && mkdir -p /data/bags /data/intrinsics /logs/ros

ENTRYPOINT ["/opt/calibration-capture/entrypoint.sh"]
CMD ["help"]
