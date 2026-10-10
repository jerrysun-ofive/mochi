#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <release-manifest.json> <output.rb>" >&2
  exit 64
fi

MANIFEST="$1"
OUTPUT="$2"
VERSION="$(jq -r .version "$MANIFEST")"
SHA="$(jq -r .dmgSHA256 "$MANIFEST")"
URL="$(jq -r .dmgURL "$MANIFEST")"

sed \
  -e "s|__VERSION__|$VERSION|g" \
  -e "s|__SHA256__|$SHA|g" \
  -e "s|__URL__|$URL|g" \
  "${0:A:h:h}/Packaging/mochi.rb.template" > "$OUTPUT"
