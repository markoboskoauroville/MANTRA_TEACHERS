#!/bin/sh
# build.sh: Ableton Teacher (Mantra).app and DaVinci Teacher (Mantra).app from one source. Runs on GitHub (workflow),
# never on the Mac (MANTRA_MANIFEST compile-on-github.md). Signed "${SIGN:-Mantra Apps}"; NO_INSTALL=1 skips /Applications.
set -e
cd "$(dirname "$0")"
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
mkdir -p build
swiftc -O -swift-version 5 -parse-as-library -o build/TeacherBin app/*.swift 2>&1 | grep -v "warning:" || true
[ -x build/TeacherBin ] || { echo "the app did not build"; exit 1; }
# the icons, drawn in code
swiftc -O icon/make_icons.swift -o build/mkicon 2>&1 | grep -v "warning:" || true

mk() { # key, App name, bundle id, bundle id of the taught app is in code
  KEY="$1"; NAME="$2"; ID="$3"; EXE="Teacher"
  APP="build/$NAME.app"
  rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp build/TeacherBin "$APP/Contents/MacOS/$EXE"
  cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>$ID</string>
<key>CFBundleExecutable</key><string>$EXE</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$V</string>
<key>CFBundleVersion</key><string>$V</string>
<key>TeacherKey</key><string>$KEY</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>The Teacher listens when you press MIC, so you can tell it what to do.</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
</dict></plist>
PL
  if [ -x build/mkicon ]; then
    rm -rf "build/$KEY.iconset"
    build/mkicon "$KEY" "build/$KEY.iconset" || true
    iconutil -c icns "build/$KEY.iconset" -o "$APP/Contents/Resources/AppIcon.icns" || true
  fi
  codesign --force -s "${SIGN:-Mantra Apps}" "$APP"
}
mk ableton "Ableton Teacher (Mantra)" community.auroville.abletonteacher
mk davinci "DaVinci Teacher (Mantra)" community.auroville.davinciteacher
[ -n "$NO_INSTALL" ] && { echo "built both Teachers (v$V)"; exit 0; }
for x in "build/Ableton Teacher (Mantra).app" "build/DaVinci Teacher (Mantra).app"; do
  rm -rf "/Applications/$(basename "$x")"; cp -R "$x" /Applications/
done
echo "built both Teachers (v$V), installed in /Applications"
