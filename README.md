# jucier

A focused macOS archive utility built with Flutter, Forui, and the official
7-Zip source. Jucier intentionally uses a single-window workflow: drop files to
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
- Fast incremental additions and an explicit 7z optimization action.
- Verified replacement of existing archives, exact member selection, cancellable staging, and batched extraction.
- Extract with overwrite, skip, or automatic rename conflict behavior.
- Smart extraction is enabled by default and can be disabled in Settings. Whole-archive extraction wraps multiple top-level items in an archive-named folder; a single file or existing top-level folder is extracted directly.
- Test archive integrity, show progress, and cancel the active operation.
- Drag and drop plus native macOS open/save panels.
- System, light, and dark desktop themes with a persistent appearance setting.

## Requirements

- Flutter 3.47 or newer.
- macOS with Xcode Command Line Tools.

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

7-Zip's redistributed license files are copied to
`third_party/7zip/licenses` by the download script and must be included with
release artifacts.

## Archive operation behavior

- Creating at an existing path replaces the old contents after building and testing
  the replacement. Old numbered volumes are removed as part of publication;
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
