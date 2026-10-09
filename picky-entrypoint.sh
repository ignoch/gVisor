#!/bin/sh
# picky container entrypoint — runs as ROOT by design, then drops privileges.
#
# Why root first: Docker Desktop's virtiofs share maps single-file bind mounts
# to root:root 0600 inside the VM, so the unprivileged agent user could not
# read the bound auth file directly. The root phase syncs it into the agent
# state volume with correct ownership (host file stays the source of truth —
# re-synced every launch: in-container writes to it are discarded) and relaxes
# the pre-existing root-owned state dirs so pi (uid 1000) can write to them.
#
# Then it re-executes picky-run.sh as pagent (uid 1000 matches the volume).

STATE=/state

if [ -f /secrets/auth.json ]; then
  cat /secrets/auth.json > "$STATE/auth.json.tmp" \
    && mv "$STATE/auth.json.tmp" "$STATE/auth.json" \
    && chown pagent:pagent "$STATE/auth.json" \
    && chmod 600 "$STATE/auth.json"
fi

chown -R pagent:pagent "$STATE/bin" "$STATE/git" "$STATE/missions" \
  "$STATE/npm" "$STATE/sessions" "$STATE/skills" 2>/dev/null || true

exec su-exec pagent /usr/local/bin/picky-run.sh "$@"