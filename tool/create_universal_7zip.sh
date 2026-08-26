#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'Usage: %s /path/to/arm64/7zz /path/to/x86_64/7zz\n' "$0" >&2
  exit 64
fi

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination="$project_dir/assets/sevenzip/7zz"

lipo -create "$1" "$2" -output "$destination"
chmod 755 "$destination"
lipo -info "$destination"
