#!/usr/bin/env bash
set -euo pipefail

task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${PATH}"
cd "${task_root}"

if command -v bun >/dev/null 2>&1; then
  exec bun "$@"
elif [[ -x "${HOME}/.bun/bin/bun" ]]; then
  exec "${HOME}/.bun/bin/bun" "$@"
fi

printf '%s\n' 'Bun is required to run the commit checks.' >&2
exit 1
