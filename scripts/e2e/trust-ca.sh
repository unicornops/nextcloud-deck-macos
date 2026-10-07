#!/usr/bin/env bash
# Makes the system trust the local CA that Caddy signs the test server's certificate with, so the app's
# URLSession accepts https://localhost without any test-only TLS code. Needs sudo.
#
# The CA is created by start-server.sh and is new for every $E2E_DIR. On your own Mac, run
# `untrust-ca.sh` afterwards (or remove "Caddy Local Authority" in Keychain Access).
set -euo pipefail

E2E_DIR="${E2E_DIR:-build/e2e}"
CA_CERT="$E2E_DIR/caddy/pki/authorities/local/root.crt"
[ -f "$CA_CERT" ] || {
    echo "No CA at $CA_CERT: run start-server.sh first" >&2
    exit 1
}

case "$(uname -s)" in
    Darwin)
        sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CA_CERT"
        ;;
    Linux)
        sudo cp "$CA_CERT" /usr/local/share/ca-certificates/shuffleboard-e2e.crt
        sudo update-ca-certificates
        ;;
    *)
        echo "Unsupported OS" >&2
        exit 1
        ;;
esac
echo "Trusted $CA_CERT"
