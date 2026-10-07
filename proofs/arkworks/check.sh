#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
manifest="$project_dir/Cargo.toml"
cargo fmt --manifest-path "$manifest" --all -- --check
cargo clippy --offline --locked --manifest-path "$manifest" --all-targets --all-features -- -D warnings
cargo test --offline --locked --manifest-path "$manifest" --all-features
RUSTDOCFLAGS="${RUSTDOCFLAGS:-} -D warnings" cargo doc --offline --locked --manifest-path "$manifest" --all-features --no-deps
