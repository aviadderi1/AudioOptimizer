#!/bin/sh
# Builds "AD Audio Optimizer.app" (universal: Apple Silicon + Intel). Run on a Mac with Xcode command line tools.
set -e
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
FW="-framework AppKit -framework CoreAudio"
swiftc -O -target arm64-apple-macos12 Sources/*.swift $FW -o build/ADAudioOptimizer-arm64
swiftc -O -target x86_64-apple-macos12 Sources/*.swift $FW -o build/ADAudioOptimizer-x86_64
APP="build/AD Audio Optimizer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/ADAudioOptimizer-arm64 build/ADAudioOptimizer-x86_64 -output "$APP/Contents/MacOS/ADAudioOptimizer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
ICONSET=build/AppIcon.iconset
mkdir -p $ICONSET
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
  d=$((s*2)); sips -z $d $d Resources/icon.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICONSET -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
cd build && ditto -c -k --keepParent "AD Audio Optimizer.app" "AD-Audio-Optimizer-mac.zip"
echo "Built build/AD Audio Optimizer.app"
