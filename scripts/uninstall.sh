#!/usr/bin/env bash
# Removes OpenWhisper, its settings, stored API key, permissions and local signing certificate.
set -uo pipefail

APP_NAME="OpenWhisper"
BUNDLE_ID="com.openwhisper.app"
CERT_NAME="OpenWhisper Local Signing"

pkill -x "$APP_NAME" 2>/dev/null
rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1
security delete-generic-password -s "$BUNDLE_ID" -a openai-api-key >/dev/null 2>&1
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1
tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1
security delete-identity -c "$CERT_NAME" >/dev/null 2>&1

echo "✓ OpenWhisper removed."
