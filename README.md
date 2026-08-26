# jucier

A focused macOS archive utility built with Flutter, Forui, and the official
7-Zip source. Jucier intentionally uses a single-window workflow: drop files to
create an archive, drop an archive to browse it, and keep the current operation
visible in a compact footer.

## Current features

- Browse 7-Zip's supported archive formats with nested folder navigation.
- Create 7z, ZIP, TAR, and GZIP archives.
- Passwords, compression levels, split volumes, and encrypted 7z headers.
- Extract with overwrite, skip, or automatic rename conflict behavior.
- Test archive integrity, show progress, and cancel the active operation.
- Drag and drop plus native macOS open/save panels.
- Automatic light and dark desktop themes from Forui.

## Requirements

- Flutter 3.47 or newer.
- macOS with Xcode Command Line Tools.

## Build 7-Zip from source

The build is pinned to the version and checksum in `third_party/7zip`. It
downloads the official source archive, verifies it, compiles the full `Alone2`
console executable, and installs the result as a Flutter asset:

```sh
./tool/build_7zip_macos.sh
```

Run that command once before starting the app:

```sh
flutter run -d macos
```

For a Universal binary, build once on Apple Silicon and once on Intel, then
combine the two artifacts:

```sh
./tool/create_universal_7zip.sh /path/to/arm64/7zz /path/to/x86_64/7zz
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
