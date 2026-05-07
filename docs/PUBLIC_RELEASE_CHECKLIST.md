# Public Release Checklist

Use this checklist before pushing to a public repository.

## Source Tree

- No `.env` file is present.
- No rosbag, logs, camera frames, maps, or calibration datasets are present.
- No private registry, private host, private IP, user home path, token, key, or
  device identity appears in source files.
- README examples use placeholders such as `<your-github-repo-url>` and
  `<your-prebuilt-ros-noetic-image>`.
- `.gitignore` and `.dockerignore` include generated outputs.

## Runtime Safety

- Docker Compose has no `depends_on` on robot services.
- Scripts use `docker compose run --rm --no-deps` for capture commands.
- The tool does not call `docker compose up`, `restart`, or `down` for robot
  services.
- The default generated point cloud topic is namespaced under
  `/calibration/...`, not a production topic.

## Validation

```bash
./scripts/calibration_capture.sh audit
bash -n scripts/calibration_capture.sh docker/calibration-capture/entrypoint.sh
python3 -m py_compile docker/calibration-capture/livox_custom_to_pointcloud2.py
docker compose -f docker-compose.yml config >/tmp/lidar-camera-calibration-compose.yml
```

Optional runtime validation on a robot with ROS topics already available:

```bash
./scripts/calibration_capture.sh build
./scripts/calibration_capture.sh check
./scripts/calibration_capture.sh record 5 public_release_smoke
rosbag info calibration_data/bags/public_release_smoke.bag
```
