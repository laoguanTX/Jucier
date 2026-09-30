# jucier

A focused macOS and Windows archive utility built with Flutter, Forui, and
official 7-Zip runtimes. Jucier uses a single-window workflow: drop files to
create an archive, drop an archive to browse it, and keep the current operation
visible in a compact footer.

## Project structure

- `lib/app.dart`: application bootstrap, global theme, and dependency wiring.
- `lib/application/`: single-window navigation and app-level transitions.
- `lib/archive/`: archive domain models, supported formats, and the 7-Zip engine.
- `lib/screens/`: full-page presentation widgets.
- `lib/dialogs/`: focused user-input flows.
- `lib/platform/`: native platform-channel services.
- `lib/widgets/`: reusable presentation components.

## Current features

- Browse 7-Zip's supported archive formats with nested folder navigation.
- Create ZIP, 7z, TAR, GZIP, XZ, BZIP2, WIM, TAR.GZ, and TAR.XZ archives.
- Compression presets, explicit ZIP AES-256/legacy encryption, split volumes, and encrypted 7z headers.
- A persistent compression-performance setting shared by macOS and Windows:
  Balanced retains up to 8 threads and full verification; Speed uses native
  automatic threading, larger solid blocks for 7z, and skips post-create testing;
  Save resources limits threads to 2 and uses smaller 7z dictionaries.
  The setting applies to new archives, including Finder compression; the editable
  7z preset remains non-solid. Higher parallelism may not help tiny files.
- Fast incremental additions and an explicit 7z optimization action.
- Verified replacement of existing archives, exact member selection, cancellable staging, and batched extraction.
- Extract with overwrite, skip, or automatic rename conflict behavior.
- Smart extraction is enabled by default and can be disabled in Settings. Whole-archive extraction wraps multiple top-level items in an archive-named folder; a single file or existing top-level folder is extracted directly.
- Test archive integrity, show progress, and cancel the active operation.
- Drag and drop into the app plus native desktop open/save panels.
- Native default-app previews and persistent settings on macOS and Windows.
- System, light, and dark desktop themes with a persistent appearance setting.

## Requirements

- Flutter 3.47 or newer.
- macOS with Xcode Command Line Tools.
- For Windows x64: Windows 10/11 and Visual Studio with the Desktop development
  with C++ workload and Windows SDK (required only for building).

## Build on Windows

From the project root, prepare the full Windows 7-Zip runtime:

```powershell
pwsh -File tool/prepare_7zip_windows.ps1
flutter run -d windows
flutter build windows --release
```

The script verifies pinned SHA-256 hashes, extracts the official installer
without installing it into Windows, and copies `7z.exe`, `7z.dll`, and license
files into Flutter assets. The runtime release and checksums are recorded in
`third_party/7zip/WINDOWS_RUNTIME.json`. Downloads use the [official 7-Zip
GitHub releases](https://github.com/ip7z/7zip/releases), linked from the
[7-Zip download page](https://www.7-zip.org/download.html).

To use an existing installation instead:

```powershell
pwsh -File tool/prepare_7zip_windows.ps1 -SevenZipDirectory 'C:\Program Files\7-Zip'
```

Distribute the **entire** `build/windows/x64/runner/Release` directory, including
`data` and DLLs. The packaged engine is located relative to the application,
so launching from Explorer or a different working directory does not require
an installed 7-Zip or a configured PATH. `JUCIER_7ZZ_PATH` remains available
as a development override on both platforms.

Windows uses the current user's filesystem permissions and stores preferences
under `HKEY_CURRENT_USER\Software\Jucier\Preferences`. Ctrl+, opens settings.
Opening an archive with Jucier through Windows **Open with**, or passing its
path on the command line, opens the archive directly. Default file associations
are chosen in Windows system settings; Jucier does not overwrite UserChoice.
Windows has a title bar that shares the app background, with native dragging,
resizing, maximize/restore and Windows 11 Snap Layout hit testing. In Settings,
install or uninstall **资源管理器右键菜单支持** for the current user (no elevation).
The Jucier submenu offers ZIP/custom compression for files and folders and
extract-here/extract-to for supported archives. COM receives the complete
selection, including Unicode paths, and reuses a running Jucier process.
On Windows 11 these verbs appear under **Show more options**.
Registration lives under `HKEY_CURRENT_USER\Software\Classes`; uninstall removes
only Jucier's two menu trees and four COM registrations. If the app is moved,
install the menu again from its new location; status detects stale paths.
Uninstall the menu before deleting the portable app directory.
Dragging archive members out remains a macOS feature; Windows users can extract
members through the archive actions.

The macOS runner, Finder extension, bookmark permissions, and native channel
names retain their existing behavior. Dart desktop services share the native
channel contract; the previous `MacOS*` class names remain compatible aliases.

## Build 7-Zip from source

The build is pinned to the version and checksum in `third_party/7zip`. It
downloads the official source archive, verifies it, compiles both arm64 and
x86_64 slices of the full `Alone2` console executable, combines them into a
Universal binary, and installs the result as a Flutter asset:

```sh
./tool/build_7zip_macos.sh
```

Run that command once before starting the app:

```sh
flutter run -d macos
```

During development, `JUCIER_7ZZ_PATH` can point Jucier at another `7zz`
executable.

## Verification

```sh
flutter analyze
flutter test
```

For hosts with limited test-process capacity, run `flutter test --concurrency=1`.
Archive integration tests use the bundled runtime for the current platform;
macOS symbolic-link tests and filenames forbidden by Windows remain platform
specific. The real Windows runner channels can also be checked without showing
a window or launching external apps:

```powershell
flutter run -d windows -t tool/windows_platform_smoke.dart --no-pub
```

The native Explorer tests cover isolated registry install/repair/uninstall and
all four COM actions with multi-selection and Unicode paths:

```powershell
cmake -S tool/windows_native_tests -B build/windows_native_tests -A x64
cmake --build build/windows_native_tests --config Debug
ctest --test-dir build/windows_native_tests -C Debug --output-on-failure
```

7-Zip's redistributed license files are copied to
`third_party/7zip/licenses` by the download script and must be included with
release artifacts.

## Archive operation behavior

- Creating at an existing path replaces the old contents after building the
  replacement and, unless Speed is selected, testing it. Old numbered volumes are removed as part of publication;
  failures before publication leave the original intact. Publication rolls back
  on ordinary filesystem errors. A multi-volume replacement is not atomic across
  a power failure or process termination.
- Adding files uses incremental updates. The **整理** action explicitly rebuilds
  compatible 7z archives with standard level 5 and solid compression. It needs
  temporary space for the unpacked contents; unchanged entries are checked before
  the original is replaced.
- ZIP passwords default to AES-256. Choose legacy ZIP encryption in advanced
  options only when the receiving software requires it. Existing encrypted data
  is checked before modifying an encrypted archive.
- Selected-only extraction decodes a batch once, preserves safe relative symbolic
  links, and refuses to merge through links already in the destination. Conflicting
  directories are not recursively deleted to replace them with a file.
- GZIP/XZ/BZIP2 accept one regular file. Use TAR.GZ or TAR.XZ for directories.
- Preview sessions are reused and can be closed from the eye button in the archive
  toolbar. Save changes into the archive before closing a session.

## Repeatable performance sample

```sh
dart run tool/benchmark_archives.dart
```

This creates temporary synthetic files and compares incremental additions with
recompression, and batched extraction with separate extractions. It also parses a
100,000-member synthetic listing. Output is JSON; timings include process startup
and are a warm-cache local sample, not a guarantee for other datasets. The temporary
files are removed when the benchmark finishes.
