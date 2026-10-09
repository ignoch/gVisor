#!/bin/sh
# Runs as pagent (uid 1000). Work dir: /work when a project is bind-mounted
# for this session (docker compose run --rm -v ~/Projects/<x>:/work picky),
# otherwise the agent home. Git identity: /state/gitconfig (in the agent-state
# volume) is used when present, so git config survives re-creations.
if [ -d /work ]; then
  cd /work
else
  cd "$HOME"
fi
if [ -f /state/gitconfig ]; then
  export GIT_CONFIG_GLOBAL=/state/gitconfig
fi
exec pi "$@"