#!/usr/bin/env bash
# Signs in the daily page check's test account again, and stores its new session as the
# CHATGPT_SESSION secret of this repository (with gh). Run it on a Mac, from a clone of the
# repository, when the page check opens a "renew the test account's session" issue (the session
# lasts about 90 days). The session never shows on screen, and its file is deleted at the end.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swiftc -swift-version 6 -parse-as-library scripts/renew-page-check-session.swift -o "$tmp/renew"
"$tmp/renew" "$tmp/session.json" "$@"
gh secret set CHATGPT_SESSION < "$tmp/session.json"
echo "Stored the new session as the CHATGPT_SESSION secret."
echo "To run the page check now: gh workflow run page-check.yml"
