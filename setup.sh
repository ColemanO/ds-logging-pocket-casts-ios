#!/usr/bin/env bash
#
# One-time workspace setup for the Pocket Casts iOS fork.
# Safe to re-run.
#
# What this does:
#   - Creates podcasts/Credentials/LocalApiCredentials.swift with placeholder
#     values if it doesn't already exist. This unblocks the GenerateCredentials
#     build phase for developers who don't have the shared secrets file at
#     ~/.configure/pocketcasts-ios/secrets/pocket_casts_credentials.json.
#     The file is gitignored.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_CREDS="$ROOT_DIR/podcasts/Credentials/LocalApiCredentials.swift"

if [ -f "$LOCAL_CREDS" ]; then
    echo "✓ LocalApiCredentials.swift already exists — skipping."
else
    echo "→ Creating placeholder $LOCAL_CREDS"
    cat > "$LOCAL_CREDS" <<'SWIFT'
/// Local API Credentials placeholder for development builds.
/// This file is gitignored. Replace values with real secrets if needed.
///
struct ApiCredentials {

    static let zendeskAPIKey = ""
    static let zendeskUrl = ""
    static let zendeskNewUrl = ""
    static let dotcomSecret = ""
    static let loggingEncryptionKey = ""
    static let sharingServerSecret = ""
    static let sentryDSN = ""
    static let googleSignInSecret = ""
    static let googleSignInServerClientId = ""
    static let instagramAppID = ""
}
SWIFT
    echo "✓ Wrote placeholder credentials."
fi

echo ""
echo "Setup complete. Next steps:"
echo "  - Open podcasts.xcodeproj in Xcode, or"
echo "  - Build with: make build"
echo "  - Run tests with: make test"
