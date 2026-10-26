#!/usr/bin/env bash
set -euo pipefail

# 为当前用户注册已有的应用目录，不更改 MIME 默认关联。
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="${1:-$project_dir/build/linux/x64/release/bundle}"
if [[ ! -x "$bundle/jucier" ]]; then
  echo "请先运行 flutter build linux --release 构建应用，或传入已构建的应用目录。" >&2
  exit 1
fi
bundle="$(cd -- "$bundle" && pwd)"
if [[ "$bundle" == *$'\n'* || "$bundle" == *$'\r'* ]]; then
  echo "应用目录路径不能包含换行符。" >&2
  exit 1
fi
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data_dir/applications" "$data_dir/icons/hicolor/256x256/apps"
cp "$project_dir/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png" \
  "$data_dir/icons/hicolor/256x256/apps/dev.jucier.Jucier.png"

# 按 Desktop Entry 的 Exec 语法转义路径，支持空格和引号。
exec_path="${bundle//\\/\\\\\\\\}"
exec_path="${exec_path//\"/\\\\\"}"
exec_path="${exec_path//\$/\\\\\$}"
exec_path="${exec_path//\`/\\\\\`}"
exec_path="${exec_path//%/%%}"
cat > "$data_dir/applications/dev.jucier.Jucier.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Jucier
Comment=创建、浏览和解压压缩包
Exec="$exec_path/jucier" %F
Icon=dev.jucier.Jucier
Terminal=false
Categories=Utility;Archiving;Compression;
MimeType=application/zip;application/x-7z-compressed;application/x-rar;application/vnd.rar;application/x-tar;application/gzip;application/x-gzip;application/x-xz;application/x-bzip2;application/x-compressed-tar;application/x-xz-compressed-tar;application/x-bzip-compressed-tar;application/x-iso9660-image;
StartupWMClass=dev.jucier.Jucier
EOF
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data_dir/applications"
fi
echo "已为当前用户注册 Jucier，请在文件管理器的“打开方式”菜单中选择它。"
