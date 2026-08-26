#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir=$($project_dir/tool/download_7zip.sh)
bundle_dir="$source_dir/CPP/7zip/Bundles/Alone2"
architecture=$(uname -m)

case "$architecture" in
  arm64)
    makefile='../../cmpl_mac_arm64.mak'
    ;;
  x86_64)
    makefile='../../cmpl_clang.mak'
    ;;
  *)
    printf 'Unsupported macOS architecture: %s\n' "$architecture" >&2
    exit 1
    ;;
esac

(cd "$bundle_dir" && make -j -f "$makefile")

built_binary=$(find "$bundle_dir" -type f -name 7zz -perm +111 -print | head -n 1)
if [ -z "$built_binary" ]; then
  printf 'The build completed but no 7zz executable was found.\n' >&2
  exit 1
fi

destination="$project_dir/assets/sevenzip/7zz"
cp "$built_binary" "$destination"
chmod 755 "$destination"
"$destination" i >/dev/null

mkdir -p "$project_dir/assets/sevenzip/licenses"
cp "$project_dir/third_party/7zip/licenses/License.txt" "$project_dir/assets/sevenzip/licenses/7zip-License.txt"
cp "$project_dir/third_party/7zip/licenses/copying.txt" "$project_dir/assets/sevenzip/licenses/LGPL-2.1.txt"
cp "$project_dir/third_party/7zip/licenses/unRarLicense.txt" "$project_dir/assets/sevenzip/licenses/unRAR-License.txt"

printf 'Built %s 7zz at %s\n' "$architecture" "$destination"
