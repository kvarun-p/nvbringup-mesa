#!/bin/sh
# Clones Mesa at the tag these patches are for and applies them on a new branch.
#   ./apply.sh [dir]          (default: ./mesa)
# In an existing Mesa checkout at the same tag: git am /path/to/nvbringup-mesa/patches/*.patch
set -eu
TAG=mesa-26.2.3
BRANCH=nvbringup-26.2
here=$(cd "$(dirname "$0")" && pwd)
dir=${1:-mesa}

[ -e "$dir" ] && { echo "$dir already exists"; exit 1; }
git clone --depth 1 --branch "$TAG" https://gitlab.freedesktop.org/mesa/mesa.git "$dir"
cd "$dir"
git switch -q -c "$BRANCH"
# git am records a committer; use a placeholder when no git identity is set up.
if git config user.email >/dev/null; then
    git am -q "$here"/patches/*.patch
else
    git -c user.name=nvbringup -c user.email=nvbringup@localhost am -q "$here"/patches/*.patch
fi
echo "$dir: $TAG plus $(git rev-list --count "$TAG"..HEAD) NVBringup commits on branch $BRANCH"
