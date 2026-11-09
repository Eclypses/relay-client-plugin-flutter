#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_FILE="$SCRIPT_DIR/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"

if [[ ! -f "$PKG_FILE" ]]; then
  echo "Missing generated package file: $PKG_FILE"
  echo "Run 'flutter pub get' from example/ first, then re-run this script."
  exit 1
fi

if grep -q '.iOS("13.0")' "$PKG_FILE"; then
  sed -i '' 's/\.iOS("13\.0")/.iOS("16.0")/g' "$PKG_FILE"
  echo "Updated FlutterGeneratedPluginSwiftPackage minimum iOS to 16.0"
else
  echo "No 13.0 entry found. Current iOS platform line:"
  grep -n '\.iOS(' "$PKG_FILE" || true
fi
