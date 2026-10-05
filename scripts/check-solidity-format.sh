#!/usr/bin/env bash
set -euo pipefail

task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${HOME}/.foundry/bin:${PATH}"
cd "${task_root}"

files=()
while IFS= read -r -d '' file; do
  [[ -f "$file" ]] && files+=("$file")
done < <(git ls-files --cached --others --exclude-standard -z -- '*.sol')

if [[ ${#files[@]} -gt 0 ]]; then
  forge fmt --check "${files[@]}"
fi
