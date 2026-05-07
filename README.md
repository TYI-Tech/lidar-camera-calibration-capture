# LiDAR-Camera Calibration Rosbag Capture

这个仓库用于在已有 ROS1 运行环境中录制 LiDAR-camera 外参标定需要的 rosbag。它不启动飞控、不启动 LiDAR 驱动、不独占相机，只连接宿主机上的 ROS master，检查并录制现有话题。

默认话题适配 Livox MID360 + USB RGB 相机：

- Livox MID360 原始话题：`/livox/lidar`，类型 `livox_ros_driver2/CustomMsg`
- 标定专用转换点云话题：`/calibration/livox/points`，类型 `sensor_msgs/PointCloud2`
- USB RGB 图像话题：`/usb_cam/image_raw`
- USB RGB 相机参数话题：`/usb_cam/camera_info`

录制结果默认写入 `calibration_data/bags/*.bag`，可直接用于后续离线外参标定工具，例如 `direct_visual_lidar_calibration`。

## 前置条件

1. 机器人主系统已经启动 ROS master、Livox MID360 驱动和 USB RGB 相机 ROS 发布节点。
2. 宿主机可以看到以下话题：

   ```bash
   rostopic info /livox/lidar
   rostopic info /usb_cam/image_raw
   rostopic info /usb_cam/camera_info
   ```

3. 宿主机已安装 Docker 和 Docker Compose v2。
4. 如需做相机内参 GUI 标定，需要本机 X11 可用。

## 解耦原则

这个工具只做录制，不管理飞行器主系统：

- 不启动、不停止、不重启 `flight-core`、`vision-gateway`、`media-gateway`、`control-gateway`、`pointcloud-gateway` 或任何飞行控制服务。
- 不打开 `/dev/video*`、不独占相机、不访问 LiDAR 设备，只连接已有 ROS master。
- 不修改主工程配置、环境变量、launch 文件或 Docker Compose 文件。
- 不向主系统常用 `/livox/points` 写数据；默认只发布临时标定话题 `/calibration/livox/points`。
- 所有录制命令都使用 `docker compose run --rm --no-deps` 启动一次性容器，命令结束后容器退出。
- 容器默认使用当前宿主用户 UID/GID 运行，避免生成 root-owned rosbag 或日志。

如果 `/usb_cam/image_raw` 或 `/usb_cam/camera_info` 不存在，说明相机 ROS 发布者还没有由外部系统提供。本工具会直接报错，不会为了录制去重启或改动主系统服务。请先用你现场认可的方式提供相机 ROS 话题，再运行本工具。

## 快速开始

```bash
git clone <your-github-repo-url> lidar-camera-calibration-capture
cd lidar-camera-calibration-capture
cp .env.example .env

./scripts/calibration_capture.sh build
./scripts/calibration_capture.sh check
./scripts/calibration_capture.sh record 15 calib_01

rosbag info calibration_data/bags/calib_01.bag
```

`check` 会确认 `/livox/lidar`、`/usb_cam/image_raw`、`/usb_cam/camera_info` 可用。如果宿主没有发布标定专用 `/calibration/livox/points`，容器会在自身生命周期内启动转换进程，把 Livox `CustomMsg` 转成 `PointCloud2`。

## USB 相机内参标定

9x13 方格标定板对应 12x8 内角点，方格边长 0.020 m 时执行：

```bash
xhost +local:docker
./scripts/calibration_capture.sh intrinsics-check
./scripts/calibration_capture.sh intrinsics-calibrate 12 8 0.020 /usb_cam/image_raw /usb_cam
```

GUI 打开后移动标定板覆盖画面不同位置，点击 `CALIBRATE`，再点击 `SAVE`。输出默认位于 `calibration_data/intrinsics/calibrationdata.tar.gz`。解包后可得到相机内参 YAML。

## 录制外参标定 bag

建议每次录制 10 到 20 秒。标定板需要同时被 RGB 相机拍到，并在 LiDAR 点云中形成清晰平面。

```bash
./scripts/calibration_capture.sh record 15 calib_02
```

bag 默认包含：

- `/usb_cam/image_raw`
- `/usb_cam/camera_info`
- `/calibration/livox/points`

如果你已有深度或投影深度话题，并希望一起录制，可在 `.env` 中设置：

```bash
CALIBRATION_RECORD_DEPTH=true
CALIBRATION_DEPTH_TOPIC=/rgb_camera/livox/projected_depth
```

## 常用命令

```bash
./scripts/calibration_capture.sh help
./scripts/calibration_capture.sh build
./scripts/calibration_capture.sh pull
./scripts/calibration_capture.sh check
./scripts/calibration_capture.sh topics
./scripts/calibration_capture.sh record 15 calib_01
./scripts/calibration_capture.sh intrinsics-calibrate 12 8 0.020 /usb_cam/image_raw /usb_cam
./scripts/calibration_capture.sh shell
```

## 配置项

主要配置都在 `.env`：

- `ROS_MASTER_URI`：容器连接的 ROS master，默认 `http://127.0.0.1:11311`
- `CALIBRATION_LIVOX_INPUT_TOPIC`：Livox 原始 `CustomMsg` 话题
- `CALIBRATION_POINTS_TOPIC`：转换后或已有的 `PointCloud2` 话题
- `CALIBRATION_IMAGE_TOPIC`：RGB 图像话题
- `CALIBRATION_CAMERA_INFO_TOPIC`：RGB 相机参数话题
- `CALIBRATION_DURATION_SEC`：默认录制时长
- `CALIBRATION_CAPTURE_BASE_IMAGE`：Dockerfile 基础镜像
- `CALIBRATION_RUN_UID` / `CALIBRATION_RUN_GID`：生成文件使用的运行用户，脚本会自动设置

默认 Dockerfile 使用公开 `ros:noetic-ros-base-focal`，安装录包和相机内参标定依赖，并在构建时编译最小 `livox_ros_driver2` 消息包，因此不需要把完整飞控工程放进本仓库。

如果现场 Docker Hub 或 apt 网络不可用，但机器上已经有包含 ROS Noetic、`camera_calibration`、`rosbag` 和 catkin 构建工具的自有镜像，可以临时改 `.env`：

```bash
CALIBRATION_CAPTURE_BASE_IMAGE=<your-prebuilt-ros-noetic-image>
CALIBRATION_CAPTURE_INSTALL_APT_DEPS=false
```

这只用于现场复用已有镜像；公开仓库应保留 `.env.example` 的公开默认值，不提交本机 `.env`。

## 公开发布检查

上传公开 GitHub 仓库前执行：

```bash
./scripts/calibration_capture.sh audit
git status --short
```

确认输出中没有真实 `.env`、rosbag、日志、私有镜像地址、内网 IP、访问令牌或设备身份信息。

## 输出目录

```text
calibration_data/
  bags/
    calib_01.bag
  intrinsics/
    calibrationdata.tar.gz
logs/
  calibration-capture/
```

这些目录已被 `.gitignore` 忽略，上传 GitHub 时不会携带 rosbag、日志或本机 `.env`。

## 排障

如果 `check` 等待话题超时，先在宿主机确认：

```bash
rostopic list | grep -E '/livox/lidar|/usb_cam/image_raw|/usb_cam/camera_info'
```

如果 `/usb_cam/*` 不存在，本工具不会自动修复或重启主系统。请先确认你的相机 ROS 发布者已经由外部系统启动。

如果容器无法连接 ROS master，确认使用了 `network_mode: host`，并检查 `.env` 中的 `ROS_MASTER_URI`。

如果 `intrinsics-calibrate` 无法打开 GUI，先确认：

```bash
echo "$DISPLAY"
xhost +local:docker
```

如果 `record` 只录到了图像没有点云，查看是否存在 `/livox/lidar` 发布者，并确认 `.env` 中的 `CALIBRATION_POINTS_TOPIC`。默认情况下，工具只使用 `/calibration/livox/points` 作为标定专用点云话题。
