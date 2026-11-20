#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."

revision=e05d12a9c0fd4d8c0245d2ec5c3c177e7e0f759b
expected=e78b49dbf588bfd8f9478728e66a0860cd98926d4cc5b8c9aab7bb25865d7b3d
target=Sources/LocalSendHelper/upstream
if [[ -f "$target/.vorssaint-revision" ]] && [[ $(cat "$target/.vorssaint-revision") == "$revision" ]]; then
    exit 0
fi
if [[ -e "$target" ]]; then
    printf 'Move the existing LocalSend source tree aside before preparing the pinned revision.\n' >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl --fail --silent --show-error --location "https://codeload.github.com/localsend/localsend/tar.gz/$revision" -o "$work/source.tgz"
printf '%s  %s\n' "$expected" "$work/source.tgz" | shasum -a 256 -c
mkdir "$work/source"
tar -xzf "$work/source.tgz" --strip-components=1 -C "$work/source"
printf '%s\n' "$revision" > "$work/source/.vorssaint-revision"
mv "$work/source" "$target"
