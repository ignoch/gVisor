#!/bin/sh
# Copy the fetched gVisor binaries into the Docker Desktop VM and register
# "runsc" as a docker runtime, then hot-reload the daemon configuration.
#
# Requires (see compose.yml): privileged container with pid: host,
# the VM root mounted at /host, the fetched volume mounted at /bins.
set -e

BINS=/bins
# Container view of the VM (bind): /host/usr/local/bin on this side is
# /usr/local/bin inside the VM — the path dockerd will exec.
HOSTBIN=/host/usr/local/bin
VMRUNBIN=/usr/local/bin
CONF=/host/run/config/docker/daemon.json
PIDFILE=/host/run/desktop/docker.pid

echo "==> 1/3: copy binaries into the VM"
if [ ! -x "$BINS/runsc" ]; then
  echo "ERROR: $BINS/runsc missing — run 'docker compose run --rm fetch' first" >&2
  exit 1
fi
mkdir -p "$HOSTBIN"
cp -a "$BINS/runsc" "$BINS/containerd-shim-runsc-v1" "$HOSTBIN/"
if [ -d "$BINS/gvisor-bin" ]; then
  cp -a "$BINS/gvisor-bin" "$HOSTBIN/"
fi
ls -l "$HOSTBIN/runsc" "$HOSTBIN/containerd-shim-runsc-v1"

echo "==> 2/3: register the runsc runtime in the daemon config"
if [ ! -f "$CONF" ]; then
  echo "ERROR: $CONF not found — Docker Desktop VM layout changed?" >&2
  exit 1
fi
cp "$CONF" "$CONF.bak"
jq --arg path "$VMRUNBIN/runsc" \
   '.runtimes = ((.runtimes // {}) + {"runsc": {"path": $path}})' \
   "$CONF" > "$CONF.new"
jq -e . "$CONF.new" > /dev/null
mv "$CONF.new" "$CONF"
grep -A3 '"runsc"' "$CONF"

echo "==> 3/3: activate (SIGHUP hot-reload)"
OLD_PID=$(cat "$PIDFILE")
kill -HUP "$OLD_PID"
echo "Done. daemon.json backup (tmpfs, cleared at next VM boot): $CONF.bak"
echo "Verify from the host: sh verify.sh"