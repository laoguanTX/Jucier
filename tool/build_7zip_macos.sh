#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir=$($project_dir/tool/download_7zip.sh)
bundle_dir="$source_dir/CPP/7zip/Bundles/Alone2"

(cd "$bundle_dir" && make -j -f ../../cmpl_mac_arm64.mak \
  MY_ARCH='-arch arm64 -Wno-poison-system-directories')
(cd "$bundle_dir" && make -j -f ../../cmpl_clang.mak \
  PLATFORM=x64 O=b/m_x64 IS_X64=1 \
  MY_ARCH='-arch x86_64 -Wno-poison-system-directories')

arm64_binary="$bundle_dir/b/m_arm64/7zz"
x86_64_binary="$bundle_dir/b/m_x64/7zz"
for built_binary in "$arm64_binary" "$x86_64_binary"; do
  if [ ! -x "$built_binary" ]; then
    printf 'The build completed but %s was not found.\n' "$built_binary" >&2
    exit 1
  fi
done

destination="$project_dir/assets/sevenzip/7zz"
lipo -create "$arm64_binary" "$x86_64_binary" -output "$destination"
chmod 755 "$destination"
lipo "$destination" -verify_arch arm64 x86_64
"$destination" i >/dev/null

mkdir -p "$project_dir/assets/sevenzip/licenses"
cp "$project_dir/third_party/7zip/licenses/License.txt" "$project_dir/assets/sevenzip/licenses/7zip-License.txt"
cp "$project_dir/third_party/7zip/licenses/copying.txt" "$project_dir/assets/sevenzip/licenses/LGPL-2.1.txt"
cp "$project_dir/third_party/7zip/licenses/unRarLicense.txt" "$project_dir/assets/sevenzip/licenses/unRAR-License.txt"

printf 'Built universal arm64/x86_64 7zz at %s\n' "$destination"
