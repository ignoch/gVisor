# gVisor (runsc) on Docker Desktop + sandboxed Pi agent

Runs the gVisor sandbox runtime on the current Docker Desktop daemon and hosts
the Pi coding agent (`picky`) inside it — defense in depth: gVisor syscall
sandbox (systrap platform) + Docker Desktop VM isolation.

## Files

- `dockerfile` — alpine image for the installer services (`tar`, `zstd`, `jq`)
- `compose.yml` — four services:
  - `fetch` (unprivileged): downloads `gvisor.tar.zstd`, verifies its sha512
    checksum, extracts into the `runsc-runtime-binaries` volume. Idempotent.
  - `install-into-vm` (privileged): copies the binaries into the VM's
    `/usr/local/bin`, registers `runsc` additively in the daemon's
    `/run/config/docker/daemon.json`, hot-reloads dockerd with SIGHUP.
  - `picky`: the Pi coding agent under `runtime: runsc` (see below).
- `dockerfile.picky` — alpine:3.23 (node 24.18.1; pi needs >= 22.19) +
  `git`, `bash`, `su-exec`; pins pi version via `ARG PI_VERSION` (default 1.1.0)
- `picky-entrypoint.sh` — runs as root: syncs the host-bound `auth.json` into
  the state volume with agent ownership (single-file binds arrive root:root
  0600 through Docker Desktop's virtiofs share), fixes pre-existing root-owned
  state dirs, then drops to `pagent` (uid 1000) for pi itself
- `picky-run.sh` — runs as pagent: picks `/work` (bound project) or `$HOME`,
  applies `/state/gitconfig` as global git config when present, `exec pi`
- `verify.sh` — smoke tests

## One-time gVisor install

    docker compose run --rm fetch
    docker compose run --rm install-into-vm
    sh verify.sh

## The picky service

    docker compose run --rm picky                       # isolated agent home
    docker compose run --rm -v ~/Projects/<x>:/work picky   # work on a project

Every picky launch re-applies the runtime registration automatically via
`depends_on` (fast, idempotent, no container disturbance — SIGHUP only).

The session cwd is `/work` when a project is bound for that run, else the
agent home. Git identity: put your config in `/state/gitconfig` (e.g.
`docker compose run --rm --entrypoint sh picky -c 'git config --global user.name "..." > /state/gitconfig && git config --global user.email "..." >> /state/gitconfig'`
or edit via any container) — it is applied through `GIT_CONFIG_GLOBAL` and
survives re-creations.

### Auth model

- Bind (default): your host `~/.pi/agent/auth.json` is bound at
  `/secrets/auth.json` and synced into `/state/auth.json` at each launch —
  the host file remains the source of truth; in-container token writes are
  NOT copied back (API keys are static, so this is safe; treat the volume
  copy as a live secret: purge with
  `docker run --rm -v picky-agent-home:/s alpine:3.22 rm /s/auth.json`).
- Alternative: disable the bind in `compose.yml` and create a git-ignored
  `.env` with `ANTHROPIC_API_KEY=...` / `OPENAI_API_KEY=...` and add
  `env_file: .env` to the `picky` service — secrets then leave only on the
  host, and the volume keeps no credentials.

### Upgrades

    docker compose build --build-arg PI_VERSION=<x.y.z> picky

## Ambient state caveat (found empirically)

Docker Desktop's backend regenerates `/run/config/docker/daemon.json` at
arbitrary times (not only VM reboots), which unregisters runsc. Effects:

- `picky` launches self-heal via `depends_on` — no action needed.
- Raw `docker run --runtime runsc` may fail with "unknown or invalid runtime
  name" — re-run `docker compose run --rm install-into-vm` first.
- `verify.sh` handles both (the picky check runs first and heals).
- If SIGHUP hot-reload ever fails to register the runtime, fall back to
  killing dockerd — Docker Desktop respawns it with the new config:
  `docker run --privileged --pid=host --rm -v /:/host alpine:3.22 sh -c 'kill $(cat /host/run/desktop/docker.pid)'`
  then re-run `docker compose run --rm install-into-vm`.
- Docker Desktop updates that rebuild the VM clear the binaries as well —
  run both one-time steps again.

## Force a fresh gVisor download

    docker volume rm runsc-runtime-binaries
    docker compose run --rm fetch

## Notes

- The default runtime stays `runc`; Docker Desktop internals and the bundled
  sysbox runtimes are untouched. Registration is opt-in per container.
- The gVisor tarball contains `runsc`, `containerd-shim-runsc-v1` and
  `gvisor-bin/*`; all are copied, but only `runsc` is registered.
- The host-side `/etc/docker/daemon.json` runsc entry is inert (no host
  dockerd is installed); it is kept for a possible future native-docker setup.
- The picky service mounts no host paths except the single auth file; project
  access is per-session and explicit (option-B access model).