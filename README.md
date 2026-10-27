# jucier

Jucier 是一款面向 Linux、macOS 和 Windows 的压缩工具，基于 Flutter、Forui 和
7-Zip 构建。应用采用单窗口操作：拖入文件即可创建压缩包，拖入压缩包即可浏览内容，
当前任务的进度会显示在窗口底部。

## 项目结构

- `lib/app.dart`：应用初始化、全局主题和依赖配置。
- `lib/application/`：单窗口导航和应用级页面过渡。
- `lib/archive/`：压缩包数据模型、支持的格式和 7-Zip 引擎。
- `lib/screens/`：完整页面组件。
- `lib/dialogs/`：各类输入对话框。
- `lib/platform/`：原生平台通道服务。
- `lib/widgets/`：可复用的界面组件。

## 现有功能

- 浏览 7-Zip 支持的压缩格式，并逐级进入压缩包内的文件夹。
- 创建 ZIP、7z、TAR、GZIP、XZ、BZIP2、WIM、TAR.GZ 和 TAR.XZ 压缩包。
- 提供压缩预设、ZIP AES-256／传统加密方式、分卷压缩和 7z 文件头加密。
- 各桌面平台均可保存压缩性能设置：“均衡”最多使用 8 个线程，并在创建后完整校验；
  “速度优先”由原生引擎自动分配线程，为 7z 使用更大的固实压缩块，并跳过创建后校验；
  “节省资源”最多使用 2 个线程，并使用更小的 7z 字典。
  该设置适用于新建压缩包，包括通过 Finder 发起的压缩；可编辑的 7z 预设仍采用
  非固实压缩。对于很小的文件，增加并行度不一定能提高速度。
- 快速增量添加文件，并提供独立的 7z 整理操作。
- 替换现有压缩包前进行校验，精确选择包内条目，支持取消暂存过程和批量解压。
- 解压时可选择覆盖、跳过或自动重命名冲突文件。
- 默认启用“智能解压”，可在设置中关闭。整包解压时，如果顶层包含多项内容，
  会将其放入与压缩包同名的文件夹；如果只有一个文件或一个顶层文件夹，则直接解压。
- 检查压缩包完整性、显示进度，并取消正在执行的任务。
- 支持将文件拖入应用，以及使用系统原生的打开／保存对话框。
- 在 Linux、macOS 和 Windows 上通过系统默认应用预览文件，并保存用户设置。
- 可选择双击压缩包时打开文件列表（默认），或直接解压到压缩包所在位置，
  并遵循“智能解压”设置。各桌面平台都会保存这一选择，并在需要时提示输入密码。
- 在 macOS 和 Windows 上，主窗口关闭、隐藏或最小化时，桌面快捷操作会使用紧凑的
  进度／结果窗口。ZIP 压缩、自定义压缩和解压共用现有引擎及取消操作。
  自定义压缩会询问压缩选项，“解压到”会在同一临时会话中询问目标目录。
  已显示的主窗口会被复用；已隐藏的工作区会在任务结束后保留。
  临时窗口随内容和展开的选项调整大小，高度不超过屏幕范围。
  任务完成后可以打开输出文件夹。显示结果时保留进度窗口的高度，并以淡入方式呈现；
  较长的结果会平滑撑开窗口，避免尺寸突然跳变。Linux 使用主窗口完成外部解压操作。
- 提供跟随系统、浅色和深色主题，并保存外观设置。

## 环境要求

- Flutter 3.47 或更新版本。
- Linux：GTK 3、桌面会话，以及 `7zz` 或 `7z`。构建时还需要 Clang、CMake、Ninja、
  pkg-config 和 GTK 3 开发头文件。
- macOS：需要安装 Xcode Command Line Tools。
- Windows x64：Windows 10/11；构建时还需要安装 Visual Studio 的“使用 C++ 的桌面开发”
  工作负载和 Windows SDK。

## 在 Linux 上构建

安装构建依赖和完整的系统 7-Zip 运行时。在 Debian、Ubuntu 24.04+ 和 Linux Mint 22 上执行：

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev 7zip
flutter pub get
flutter run -d linux
flutter build linux --release
```

直接启动发布版本：

```sh
./build/linux/x64/release/bundle/jucier
./build/linux/x64/release/bundle/jucier /path/to/archive.zip
```

分发时必须保留**整个**应用目录。Linux 会先查找可执行文件旁的 `bin/7zz` 或 `bin/7z`，
然后查找 PATH 中的 `7zz` 和 `7z`。设置 `JUCIER_7ZZ_PATH` 可以覆盖这些查找位置。
请使用与主机架构匹配的 Linux 可执行文件；macOS 和 Windows 的引擎文件不能作为
Linux 运行时使用。系统 `7zip` 软件包会提供所需的支持库和许可证。

可以将已构建的应用注册到当前用户的应用菜单和“打开方式”列表：

```sh
bash tool/install_linux.sh
# 或者：bash tool/install_linux.sh /absolute/path/to/bundle
```

注册不会更改现有的默认应用。在文件管理器中选择使用 Jucier 打开，即可通过双击打开
压缩包或直接解压。请保留应用目录的位置；移动后需要重新执行注册。
删除 `~/.local/share/applications/dev.jucier.Jucier.desktop` 和
`~/.local/share/icons/hicolor/256x256/apps/dev.jucier.Jucier.png` 即可取消注册
（如果设置了 `$XDG_DATA_HOME`，则删除该目录下的对应文件）。

Linux 使用与应用明暗主题一致的自定义标题栏，提供最小化、最大化／还原和关闭按钮。
拖动顶栏空白区域可以移动窗口，双击可以最大化／还原；X11 和 Wayland 均通过 GTK
处理窗口操作，并保留原生边缘缩放和阴影。打开另一个压缩包时，会复用已有
进程和窗口，并支持包含空格或 Unicode 字符的路径。主题、压缩性能、双击行为、
智能解压、单项解压和文件列设置保存在 `$XDG_CONFIG_HOME/jucier/preferences.json`
（默认为 `~/.config/jucier/preferences.json`）。按 Ctrl+, 可以打开设置。
文件访问遵循当前用户的系统权限，因此不显示文件夹授权按钮。
Finder／资源管理器右键菜单、macOS 默认文件格式绑定，以及将压缩包内条目拖出应用的
功能，仍在原有平台提供。Linux 外部解压使用主窗口，并保留进度、取消、密码和结果控件。

## 在 Windows 上构建

在项目根目录准备完整的 Windows 7-Zip 运行时：

```powershell
pwsh -File tool/prepare_7zip_windows.ps1
flutter run -d windows
flutter build windows --release
```

脚本会校验固定的 SHA-256 哈希值，提取官方安装程序中的文件，但不会将其安装到
Windows；随后将 `7z.exe`、`7z.dll` 和许可证文件复制到 Flutter 资源目录。
运行时版本和校验值记录在 `third_party/7zip/WINDOWS_RUNTIME.json` 中。
下载来源为 [7-Zip 官方 GitHub 发布页](https://github.com/ip7z/7zip/releases)，
该页面也可从 [7-Zip 下载页](https://www.7-zip.org/download.html) 进入。

如果要使用已经安装的 7-Zip：

```powershell
pwsh -File tool/prepare_7zip_windows.ps1 -SevenZipDirectory 'C:\Program Files\7-Zip'
```

分发时必须保留**整个** `build/windows/x64/runner/Release` 目录，包括 `data` 和 DLL。
打包后的引擎通过应用所在位置定位，因此从资源管理器或其他工作目录启动时，
不需要预先安装 7-Zip，也不需要配置 PATH。所有桌面平台均可在开发时通过
`JUCIER_7ZZ_PATH` 指定其他引擎。

Windows 使用当前用户的文件系统权限，并将设置保存在
`HKEY_CURRENT_USER\Software\Jucier\Preferences` 中。按 Ctrl+, 可以打开设置。
通过 Windows 的“打开方式”选择 Jucier，或从命令行传入压缩包路径时，
应用会遵循设置中的双击行为。默认文件关联由 Windows 系统设置管理，
Jucier 不会覆盖 UserChoice。

Windows 标题栏与应用背景保持一致，支持原生拖动、调整大小、最大化／还原，
以及 Windows 11 贴靠布局的命中检测。在设置中可以为当前用户安装或卸载
“资源管理器右键菜单支持”，无需管理员权限。Jucier 子菜单提供文件和文件夹的
ZIP／自定义压缩，以及受支持压缩包的“解压到当前位置”／“解压到”操作。
COM 接口会接收完整的多选结果，支持 Unicode 路径，并复用正在运行的 Jucier 进程。
在 Windows 11 上，这些菜单项位于“显示更多选项”中。

注册信息位于 `HKEY_CURRENT_USER\Software\Classes`；卸载时仅移除 Jucier 的两组
菜单和四项 COM 注册。如果移动了应用，请在新位置重新安装右键菜单；状态检查会识别
失效路径。删除便携应用目录前，请先卸载右键菜单。
将压缩包内条目拖出应用仍是 macOS 功能；Windows 用户可以通过压缩包操作解压所选条目。

macOS 启动程序、Finder 扩展、书签权限和原生通道名称保持原有行为。
Dart 桌面服务共用原生通道协议，原有的 `MacOS*` 类名仍作为兼容别名保留。

## 从源码构建 7-Zip

构建使用 `third_party/7zip` 中固定的版本和校验值。脚本会下载并校验官方源码包，
分别编译完整 `Alone2` 控制台程序的 arm64 和 x86_64 版本，将其合并为通用二进制文件，
再安装到 Flutter 资源目录：

```sh
./tool/build_7zip_macos.sh
```

启动应用前先执行一次上述命令，然后运行：

```sh
flutter run -d macos
```

开发时可以通过 `JUCIER_7ZZ_PATH` 让 Jucier 使用其他 `7zz` 可执行文件。

## 验证

```sh
flutter analyze
flutter test
```

如果主机可用的测试进程数有限，可以运行 `flutter test --concurrency=1`。
压缩包集成测试与应用使用相同的运行时查找方式，因此 Linux 测试会使用已安装的
`7zz` 或 `7z`。Unix 符号链接测试，以及涉及 Windows 禁止使用的文件名的测试，
仍会按平台决定是否运行。

可以在不打开外部应用的情况下检查实际的 Linux 原生通道。
使用临时配置目录，验证两次启动之间的设置持久化：

```sh
smoke_config="$(mktemp -d)"
XDG_CONFIG_HOME="$smoke_config" JUCIER_SMOKE_PHASE=write \
  flutter run -d linux -t tool/linux_platform_smoke.dart
XDG_CONFIG_HOME="$smoke_config" JUCIER_SMOKE_PHASE=read \
  flutter run -d linux -t tool/linux_platform_smoke.dart
rm -r -- "$smoke_config"
```

也可以在不显示窗口、不启动外部应用的情况下检查实际的 Windows 原生通道：

```powershell
flutter run -d windows -t tool/windows_platform_smoke.dart --no-pub
```

资源管理器原生测试覆盖独立的注册表安装／修复／卸载，以及全部四项 COM 操作，
并包含多选和 Unicode 路径：

```powershell
cmake -S tool/windows_native_tests -B build/windows_native_tests -A x64
cmake --build build/windows_native_tests --config Debug
ctest --test-dir build/windows_native_tests -C Debug --output-on-failure
```

下载脚本会将需要随应用分发的 7-Zip 许可证文件复制到 `third_party/7zip/licenses`，
发布时必须一并包含这些文件。

## 压缩包操作说明

- 在已有路径创建压缩包时，会先构建替代文件，并在未选择“速度优先”时完成校验，
  然后替换原有内容。发布替代文件时会移除旧的编号分卷；发布前失败不会影响原压缩包。
  遇到一般文件系统错误时会回滚发布过程，但多分卷替换无法保证在断电或进程终止时
  仍保持原子性。
- 添加文件采用增量更新。“整理”操作会以标准等级 5 和固实压缩方式重建兼容的 7z
  压缩包。这需要用于解包内容的临时空间；替换原文件前会检查未修改的条目。
- ZIP 密码默认使用 AES-256。仅在接收方软件有要求时，才在高级选项中选择传统 ZIP
  加密方式。修改加密压缩包前会检查已有的加密数据。
- 仅解压所选条目时，同一批内容只解码一次，保留安全的相对符号链接，并拒绝通过目标
  位置已有的链接合并内容。发生冲突时，不会通过递归删除目录来将其替换为文件。
- GZIP／XZ／BZIP2 只接受一个普通文件。压缩目录请使用 TAR.GZ 或 TAR.XZ。
- 预览会话会被复用，可通过压缩包工具栏中的眼睛按钮关闭。关闭会话前，请先将修改
  保存回压缩包。

## 可重复运行的性能样例

```sh
dart run tool/benchmark_archives.dart
```

该命令会创建临时模拟文件，比较增量添加与重新压缩、批量解压与分别解压的耗时，
并解析一份包含 100,000 个条目的模拟列表。输出格式为 JSON，计时包含进程启动开销。
结果仅代表本机缓存预热后的样例，不保证适用于其他数据集。测试结束后会移除临时文件。
