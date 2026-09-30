# Windows runtime

Run `pwsh -File tool/prepare_7zip_windows.ps1` from the project root to
extract the pinned official Windows x64 `7z.exe` and `7z.dll` here.
Both files are required for the full archive format support and are bundled
as Flutter assets. They are build inputs and are not committed.

Alternatively supply `-SevenZipDirectory 'C:\Program Files\7-Zip'` to copy
an existing full installation. Do not substitute the limited `7zr.exe`.
