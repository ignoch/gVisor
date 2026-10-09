# gVisor (runsc) on Docker Desktop

Runs the gVisor sandbox runtime on the current Docker Desktop daemon so that
containers (e.g. the Pi coding agent) can opt in with `runtime: runsc`
(defense in depth: gVisor syscall sandbox + Docker Desktop VM).

## Files

- `dockerfile` — alpine image with `tar`, `zstd` (extract) and `jq` (config edit)
- `compose.yml` — two one-shot services:
  - `fetch` (unprivileged): downloads `gvisor.tar.zstd`, verifies its sha512
    checksum, extracts into the `runsc-runtime-binaries` volume. Idempotent —
    skips when the volume is already populated.
  - `install-into-vm` (privileged): copies the binaries into the Docker Desktop
    VM's `/usr/local/bin`, registers `runsc` in the daemon's
    `/run/config/docker/daemon.json` (additive `jq` merge, backup kept), then
    hot-reloads dockerd with SIGHUP.
- `install-into-vm.sh` — the helper logic used by `install-into-vm`
- `verify.sh` — smoke tests

## Install

    docker compose run --rm fetch
    docker compose run --rm install-into-vm

## Verify

    sh verify.sh

## After a Docker Desktop / VM restart

The registration lives in the VM's `/run`, which is regenerated at every VM
boot; the downloaded volume persists. Just re-run:

    docker compose run --rm install-into-vm
    sh verify.sh

## Force a fresh download

    docker volume rm runsc-runtime-binaries
    docker compose run --rm fetch

## Use it

    docker run --runtime runsc --rm alpine:3.20 dmesg | head
    # in compose: services.<name>.runtime: runsc

## Notes

- The default runtime stays `runc`; Docker Desktop internals and the bundled
  sysbox runtimes are untouched. Registration is opt-in per container.
- The tarball contains `runsc`, `containerd-shim-runsc-v1` and `gvisor-bin/*`;
  all are copied, but only `runsc` is registered (docker-runtime mode).
- If SIGHUP hot-reload ever fails to register the runtime (check
  `docker info`), fall back to killing dockerd — Docker Desktop respawns it
  with the new config:
  `docker run --privileged --pid=host --rm -v /:/host alpine:3.20 sh -c 'kill $(cat /host/run/desktop/docker.pid)'`
  then re-run `docker compose run --rm install-into-vm`.
- Docker Desktop updates that rebuild the VM clear the binaries as well —
  run both steps again.
- The host-side `/etc/docker/daemon.json` runsc entry is inert (no host
  dockerd is installed); it is kept for a possible future native-docker setup.