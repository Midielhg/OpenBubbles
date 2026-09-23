#!/usr/bin/env bash
# Local Windows release build (x64). Run from Git Bash: bash scripts/build-windows-local.sh
#
# Prerequisites (see README "Building on Windows"): Flutter 3.24.0, Rust (+ x86_64-pc-windows-msvc
# target), VS 2022 Build Tools (VCTools, VC.Tools.ARM64 on ARM hosts, VC.ATL), protoc, Strawberry
# Perl, NASM, NuGet, Developer Mode on, and LongPathsEnabled=1.
# Override any tool location with the environment variables below.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-$(dirname "$(command -v flutter 2>/dev/null || echo "$HOME/flutter/bin/flutter")")}"
WINGET_PKGS="$LOCALAPPDATA/Microsoft/WinGet/Packages"
NUGET_DIR="${NUGET_DIR:-$WINGET_PKGS/Microsoft.NuGet_Microsoft.Winget.Source_8wekyb3d8bbwe}"
PROTOC_EXE="${PROTOC_EXE:-$WINGET_PKGS/Google.Protobuf_Microsoft.Winget.Source_8wekyb3d8bbwe/bin/protoc.exe}"
STRAWBERRY="${STRAWBERRY:-/c/Strawberry}"

# native Windows perl + nasm for vendored OpenSSL (Git Bash's cygwin perl can't configure it),
# nuget for flutter_inappwebview's WebView2 download
export PATH="$NUGET_DIR:$STRAWBERRY/perl/bin:$STRAWBERRY/c/bin:$LOCALAPPDATA/bin/NASM:$FLUTTER_BIN:$HOME/.cargo/bin:$PATH"
export PROTOC="$(cygpath -w "$PROTOC_EXE")"
# some git deps (firebase_dart) exceed MAX_PATH; scoped to this build, not global config
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.longpaths GIT_CONFIG_VALUE_0=true
# short cargo target dir so vendored OpenSSL's perl Configure stays under MAX_PATH
export CARGOKIT_TEMP_DIR_OVERRIDE="${CARGOKIT_TEMP_DIR_OVERRIDE:-$(cygpath -w "$HOME/.obk")}"

echo "perl: $(command -v perl)"; echo "nasm: $(command -v nasm)"; echo "nuget: $(command -v nuget)"; echo "PROTOC=$PROTOC"

cd "$REPO_ROOT"
flutter pub get
flutter build windows --release
