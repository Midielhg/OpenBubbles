#!/usr/bin/env bash
# Local Windows release build of openbubbles-app (x64, built on an ARM64 host).
set -euo pipefail

# native Windows perl + nasm for vendored OpenSSL (Git Bash's cygwin perl can't configure it),
# nuget for flutter_inappwebview's WebView2 download
NUGET_DIR="$LOCALAPPDATA/Microsoft/WinGet/Packages/Microsoft.NuGet_Microsoft.Winget.Source_8wekyb3d8bbwe"
export PATH="$NUGET_DIR:/c/Strawberry/perl/bin:/c/Strawberry/c/bin:$LOCALAPPDATA/bin/NASM:/c/Users/MidielHenriquez/Dev/tools/flutter/bin:$HOME/.cargo/bin:$PATH"
PROTOC_EXE="$LOCALAPPDATA/Microsoft/WinGet/Packages/Google.Protobuf_Microsoft.Winget.Source_8wekyb3d8bbwe/bin/protoc.exe"
export PROTOC="$(cygpath -w "$PROTOC_EXE")"
# some git deps (firebase_dart) exceed MAX_PATH; scoped to this build, not global config
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.longpaths GIT_CONFIG_VALUE_0=true

# short cargo target dir so vendored OpenSSL's perl Configure stays under MAX_PATH
export CARGOKIT_TEMP_DIR_OVERRIDE='C:\Users\MidielHenriquez\.obk'

echo "perl:$(command -v perl)"; echo "nasm: $(command -v nasm)"; echo "nuget: $(command -v nuget)"; echo "PROTOC=$PROTOC"

# flutter_inappwebview's build dirs exceed MAX_PATH here; needs LongPathsEnabled=1 in
# HKLM\SYSTEM\CurrentControlSet\Control\FileSystem. (subst/junctions don't help: cargokit and
# flutter resolve them back to the real path.)
cd /c/Users/MidielHenriquez/Dev/iMessage/openbubbles-app
flutter pub get
flutter build windows --release
