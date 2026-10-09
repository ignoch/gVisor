#!/bin/sh
# Smoke tests for gVisor (runsc) on this Docker Desktop daemon + the picky
# sandboxed agent service.
#
# Note: Docker Desktop's backend regenerates the daemon config in the VM at
# arbitrary times, which unregisters runsc (ambient state). The picky check
# below runs FIRST and self-heals the registration (idempotent, seconds), so
# the following state checks are deterministic. If checks 2-3 fail on their
# own, re-run 'docker compose run --rm install-into-vm'.
set -u
failures=0

echo "== 1. pi responds under gVisor (also self-heals registration) =="
if docker compose run --rm -T picky --version 2>/dev/null | grep -qx '1\.1\.0'; then
  echo "OK: pi launches under runsc"
else
  echo "FAIL: pi did not answer --version under runsc"; failures=$((failures+1))
fi

echo
echo "== 2. runsc registered in docker runtimes (post-heal) =="
runtimes_json=$(docker info --format '{{json .Runtimes}}')
case "$runtimes_json" in
  *'"runsc"'*) echo "OK: runsc registered" ;;
  *) echo "FAIL: runsc not registered — re-run 'docker compose run --rm install-into-vm'"
     failures=$((failures+1)) ;;
esac

echo
echo "== 3. gVisor banner in a runsc container =="
if docker run --runtime runsc --rm alpine:3.22 dmesg | grep -qi gvisor; then
  echo "OK: gVisor sandbox active"
else
  echo "FAIL: no gVisor banner (container did not run under runsc?)"
  failures=$((failures+1))
fi

echo
echo "== 4. picky service pinned to runsc (compose config) =="
picky_runtime=$(docker compose config --format json | jq -r '.services.picky.runtime // empty')
echo "picky runtime: ${picky_runtime:-<service absent>}"
if [ "$picky_runtime" = "runsc" ]; then
  echo "OK: picky pinned to gVisor"
else
  echo "FAIL: picky runtime is '$picky_runtime' (expected runsc)"; failures=$((failures+1))
fi

echo
echo "== 5. sandbox auth.json synced into state volume (size only) =="
auth_size=$(docker compose run --rm -T --entrypoint sh picky -c 'wc -c < /state/auth.json' 2>/dev/null | tail -1 | tr -d '[:space:]')
echo "/state/auth.json: ${auth_size:-<missing>} bytes"
case "$auth_size" in
  ''|*[!0-9]*)
    echo "FAIL: auth.json not readable in sandbox"; failures=$((failures+1)) ;;
  *)
    if [ "$auth_size" -gt 2 ]; then
      echo "OK: host auth.json is synced and readable by the agent"
    else
      echo "FAIL: got the volume placeholder ({}, 2 bytes), not the host auth (116)"
      failures=$((failures+1))
    fi ;;
esac

echo
echo "== 6. default runtime remains runc =="
default=$(docker info --format '{{.DefaultRuntime}}')
echo "default runtime: ${default:-<none>}"
if [ "$default" = "runc" ]; then
  echo "OK: default runtime untouched"
else
  echo "FAIL: expected runc, got '$default'"; failures=$((failures+1))
fi

echo
echo "== 7. normal runc container still works =="
if docker run --rm alpine:3.22 sh -c 'echo runc-ok' | grep -q runc-ok; then
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