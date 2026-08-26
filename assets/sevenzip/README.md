# 7-Zip runtime

`tool/build_7zip_macos.sh` places the locally-built `7zz` executable in this
directory. The executable is intentionally not committed to source control.

At runtime Jucier checks, in order:

1. `JUCIER_7ZZ_PATH` (development and testing override);
2. the app bundle at `Contents/Resources/bin/7zz`;
3. this Flutter asset directory (local development);
4. `7zz` available on `PATH`.
