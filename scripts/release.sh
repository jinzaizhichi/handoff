#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  make release VERSION=X.Y.Z
  ./scripts/release.sh X.Y.Z

This script updates pyproject.toml, runs local package checks, creates a
release commit, and creates a local git tag. It does not push.
EOF
}

VERSION="${1:-${VERSION:-}}"
if [[ -z "${VERSION}" ]]; then
  usage >&2
  exit 2
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([A-Za-z0-9.-]+)?$ ]]; then
  echo "release: invalid VERSION '${VERSION}'" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "release: not inside a git repository" >&2
  exit 2
fi

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "release: git worktree is not clean; commit or stash changes first" >&2
  exit 2
fi

if git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
  echo "release: tag v${VERSION} already exists" >&2
  exit 2
fi

CURRENT_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' pyproject.toml | head -n 1)"
if [[ -z "${CURRENT_VERSION}" ]]; then
  echo "release: failed to read current version from pyproject.toml" >&2
  exit 2
fi

if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
  echo "release: version is already ${VERSION}" >&2
  exit 2
fi

echo "Updating version: ${CURRENT_VERSION} -> ${VERSION}"
VERSION="${VERSION}" perl -0pi -e 's/^version = "\K[^"]+(?=")/$ENV{VERSION}/m' pyproject.toml

echo "Building package"
rm -rf dist
uv build

echo "Checking package metadata"
uvx twine check dist/*

echo "Creating git commit"
git add pyproject.toml
git commit -m "release: v${VERSION}"

echo "Creating local tag"
git tag "v${VERSION}"

cat <<EOF
Release prepared locally.

  commit: release: v${VERSION}
  tag:    v${VERSION}

Next step:
  git push && git push --tags
EOF
