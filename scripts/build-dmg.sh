#!/bin/zsh
# Baut Shortcut Deck (Release) und packt es in ein DMG mit Programme-Verknüpfung.
# Ergebnis: build/ShortcutDeck-<version>.dmg
set -euo pipefail
cd "${0:A:h}/.."

xcodebuild -project ShortcutDeck.xcodeproj -scheme ShortcutDeck -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' build | grep -E "error:|BUILD" || true

app="build/Build/Products/Release/ShortcutDeck.app"
[[ -d "$app" ]] || { print -u2 "Build fehlgeschlagen"; exit 1; }
codesign --verify --strict "$app"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
stage="build/dmg-stage"
dmg="build/ShortcutDeck-$version.dmg"
rm -rf "$stage" "$dmg"
mkdir -p "$stage"
cp -R "$app" "$stage/Shortcut Deck.app"
ln -s /Applications "$stage/Programme"
hdiutil create -volname "Shortcut Deck" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
rm -rf "$stage"
print -r -- "$dmg"
