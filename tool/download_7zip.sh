#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
metadata_dir="$project_dir/third_party/7zip"
version=$(tr -d '[:space:]' < "$metadata_dir/VERSION")
compact_version=$(printf '%s' "$version" | tr -d '.')
archive_name="7z${compact_version}-src.tar.xz"
download_dir="$metadata_dir/downloads"
source_dir="$metadata_dir/source/$version"
archive_path="$download_dir/$archive_name"
archive_url="https://github.com/ip7z/7zip/releases/download/$version/$archive_name"

mkdir -p "$download_dir" "$source_dir"

if [ ! -f "$archive_path" ]; then
  curl --fail --location --retry 3 --output "$archive_path" "$archive_url"
fi

(cd "$download_dir" && shasum -a 256 -c "$metadata_dir/SHA256SUMS" >&2)

if [ ! -f "$source_dir/DOC/readme.txt" ]; then
  tar -xJf "$archive_path" -C "$source_dir"
fi

mkdir -p "$metadata_dir/licenses"
cp "$source_dir/DOC/License.txt" "$metadata_dir/licenses/License.txt"
cp "$source_dir/DOC/copying.txt" "$metadata_dir/licenses/copying.txt"
cp "$source_dir/DOC/unRarLicense.txt" "$metadata_dir/licenses/unRarLicense.txt"

printf '%s\n' "$source_dir"
