#!/usr/bin/env bash
# Builds OpenWhisper.app, signs it, installs it to /Applications and launches it.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="OpenWhisper"
BUNDLE_ID="com.openwhisper.app"
CERT_NAME="OpenWhisper Local Signing"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "→ Building…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# macOS ties Microphone/Accessibility permissions to the app's signature. Signing every
# build with the same local certificate means you only grant them once, not after each update.
ensure_signing_identity() {
    security find-certificate -c "$CERT_NAME" >/dev/null 2>&1 && return 0
    echo "→ Creating a local self-signed code-signing certificate ($CERT_NAME)"
    local tmp
    tmp="$(mktemp -d)"
    cat > "$tmp/cert.cfg" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cfg" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" >/dev/null 2>&1 &&
    /usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$CERT_NAME" \
        -out "$tmp/id.p12" -passout pass:openwhisper >/dev/null 2>&1 &&
    security import "$tmp/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P openwhisper -T /usr/bin/codesign >/dev/null
    local status=$?
    rm -rf "$tmp"
    return $status
}

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    IDENTITY="$CODESIGN_IDENTITY"
elif ensure_signing_identity; then
    IDENTITY="$CERT_NAME"
else
    echo "  (couldn't create a certificate — falling back to ad-hoc signing;"
    echo "   you'll need to re-grant Accessibility after each reinstall)"
    IDENTITY="-"
fi

echo "→ Signing with: $IDENTITY"
if ! codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" 2>/dev/null; then
    echo "  signing with '$IDENTITY' failed — using ad-hoc signature"
    IDENTITY="-"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

if [[ -w /Applications ]]; then DEST_DIR="/Applications"; else DEST_DIR="$HOME/Applications"; fi
mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/$APP_NAME.app"

echo "→ Installing to $DEST"
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
if [[ "$IDENTITY" == "-" ]]; then
    # Ad-hoc signatures change every build, so stale permission entries would silently stop working.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "→ Launching"
open "$DEST"

cat <<EOF

✓ OpenWhisper is installed and running (look for the waveform in your menu bar).

  1. Paste your OpenAI API key into Settings (opens automatically the first time).
  2. Press ⌃⌥Space (or your own shortcut) to dictate, press again to transcribe & paste.
  3. Allow Microphone and Accessibility when macOS asks — Accessibility is what lets
     OpenWhisper press ⌘V for you.

It starts automatically at login (toggle in Settings).
EOF
