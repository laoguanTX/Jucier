# 7-Zip runtime

`tool/build_7zip_macos.sh` places the locally-built macOS `7zz` executable here.
`tool/prepare_7zip_windows.ps1` places the full Windows `7z.exe` and `7z.dll`
in `windows/`. Executables are build inputs and are not committed.

At runtime Jucier checks, in order:

1. `JUCIER_7ZZ_PATH` (development and testing override);
2. the app bundle at `Contents/Resources/bin/7zz`;
3. this Flutter asset directory (local development);
4. `7zz` available on `PATH`.

Windows searches the override, `bin/7z.exe` beside the application, the bundled
`data/flutter_assets/assets/sevenzip/windows/` directory, development assets,
standard 7-Zip installation directories, and `7z.exe`/`7zz.exe` on `PATH`.
The full `7z.exe` requires its matching `7z.dll` in the same directory.
