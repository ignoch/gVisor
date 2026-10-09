#!/bin/sh
# Smoke tests for the gVisor (runsc) installation on this Docker daemon.
# Run after 'docker compose run --rm install-into-vm' and after any Docker
# Desktop / VM restart (registration is regenerated and must be re-applied).
set -u
failures=0

echo "== 1. runsc registered in docker runtimes =="
runtimes_json=$(docker info --format '{{json .Runtimes}}')
echo "$runtimes_json"
case "$runtimes_json" in
  *'"runsc"'*) echo "OK: runsc registered" ;;
  *) echo "FAIL: runsc not registered"; failures=$((failures+1)) ;;
esac

echo
echo "== 2. default runtime remains runc =="
default=$(docker info --format '{{.DefaultRuntime}}')
echo "default runtime: ${default:-<none>}"
if [ "$default" = "runc" ]; then
  echo "OK: default runtime untouched"
else
  echo "FAIL: expected runc, got '$default'"; failures=$((failures+1))
fi

echo
echo "== 3. gVisor banner in a runsc container =="
if docker run --runtime runsc --rm alpine:3.20 dmesg | grep -qi gvisor; then
  echo "OK: gVisor sandbox active"
else
  echo "FAIL: no gVisor banner (container did not run under runsc?)"
  failures=$((failures+1))
fi

echo
echo "== 4. normal runc container still works =="
if docker run --rm alpine:3.20 sh -c 'echo runc-ok' | grep -q runc-ok; then
  echo "OK: runc regression check passed"
else
  echo "FAIL: plain container broken"; failures=$((failures+1))
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS: all smoke tests passed"
else
  echo "FAIL: $failures smoke test(s) failed"
  exit 1
fi