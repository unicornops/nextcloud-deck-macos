#!/usr/bin/env bash
# Starts a throwaway Nextcloud server with the Deck app for the end-to-end tests, without Docker.
#
# Nextcloud runs on PHP's built-in server behind Caddy, which serves it over HTTPS with its own local CA
# (the app only talks HTTPS; run trust-ca.sh once so the system trusts that CA). SQLite, no cron, no mail.
# Everything lives in $E2E_DIR, so `stop-server.sh` and `rm -rf "$E2E_DIR"` undo it.
#
# Environment (all optional):
#   NEXTCLOUD_VERSION  "latest" (default), a major such as "35", or an exact release such as "35.0.1"
#   DECK_VERSION       empty (default: the newest Deck the app store has for that server), or e.g. "1.19.0"
#   E2E_DIR            working directory, default build/e2e
#   E2E_PORT           HTTPS port, default 8443
#
# Writes $E2E_DIR/env: the server URL and the test users' names and passwords, as shell variables.
# Needs php (8.3 or 8.4 with gd, intl, mbstring, pdo_sqlite, xml, zip, curl), caddy, curl, jq and unzip.
set -euo pipefail

NEXTCLOUD_VERSION="${NEXTCLOUD_VERSION:-latest}"
DECK_VERSION="${DECK_VERSION:-}"
E2E_DIR="${E2E_DIR:-build/e2e}"
E2E_PORT="${E2E_PORT:-8443}"
PHP_PORT="${E2E_PHP_PORT:-8080}"

mkdir -p "$E2E_DIR"
E2E_DIR="$(cd "$E2E_DIR" && pwd)"
SERVER_DIR="$E2E_DIR/nextcloud"
DATA_DIR="$E2E_DIR/data"
LOG_DIR="$E2E_DIR/logs"
SERVER_URL="https://localhost:$E2E_PORT"
mkdir -p "$LOG_DIR"

log() { printf '==> %s\n' "$*"; }

# Random passwords per server, kept for restarts; the server only listens on localhost.
if [ ! -f "$E2E_DIR/passwords" ]; then
    {
        echo "ADMIN_PASSWORD=$(openssl rand -hex 16)"
        echo "ALICE_PASSWORD=$(openssl rand -hex 16)"
        echo "BOB_PASSWORD=$(openssl rand -hex 16)"
    } >"$E2E_DIR/passwords"
    chmod 600 "$E2E_DIR/passwords"
fi
# shellcheck source=/dev/null
. "$E2E_DIR/passwords"

occ() { php "$SERVER_DIR/occ" --no-interaction "$@"; }

# MARK: - Download

case "$NEXTCLOUD_VERSION" in
    latest) archive="latest.zip" ;;
    *.*) archive="nextcloud-$NEXTCLOUD_VERSION.zip" ;;
    *) archive="latest-$NEXTCLOUD_VERSION.zip" ;;
esac

if [ ! -f "$SERVER_DIR/occ" ]; then
    log "Downloading Nextcloud ($archive)"
    curl -fsSL --retry 3 -o "$E2E_DIR/nextcloud.zip" "https://download.nextcloud.com/server/releases/$archive"
    unzip -q "$E2E_DIR/nextcloud.zip" -d "$E2E_DIR"
    rm "$E2E_DIR/nextcloud.zip"
fi

# MARK: - Install

if ! occ status --output=json 2>/dev/null | jq -e '.installed' >/dev/null; then
    log "Installing Nextcloud"
    occ maintenance:install \
        --database sqlite \
        --admin-user admin \
        --admin-pass "$ADMIN_PASSWORD" \
        --data-dir "$DATA_DIR"
fi
occ status

log "Configuring Nextcloud for localhost behind Caddy"
occ config:system:set trusted_domains 0 --value="localhost:$E2E_PORT"
occ config:system:set trusted_domains 1 --value="localhost"
occ config:system:set overwrite.cli.url --value="$SERVER_URL"
occ config:system:set overwriteprotocol --value=https
occ config:system:set trusted_proxies 0 --value=127.0.0.1
occ config:system:set trusted_proxies 1 --value=::1
occ config:system:set loglevel --type=integer --value=2
occ config:system:set logfile --value="$LOG_DIR/nextcloud.log"
# The tests sign in and fail to sign in many times in a row; don't slow them down or lock them out.
occ config:system:set auth.bruteforce.protection.enabled --type=boolean --value=false
occ config:system:set ratelimit.protection.enabled --type=boolean --value=false
# No mail server or update checks here.
occ config:system:set updatechecker --type=boolean --value=false
occ config:system:set has_internet_connection --type=boolean --value=true
occ config:system:set appstoreenabled --type=boolean --value=true
# Short test passwords, and no request to haveibeenpwned.com for them.
occ app:disable password_policy >/dev/null 2>&1 || true
# Skip the first-run wizard and dashboard prompts in the browser sign-in page.
occ app:disable firstrunwizard >/dev/null 2>&1 || true

# MARK: - Deck

if occ app:list --output=json | jq -e '.enabled.deck' >/dev/null; then
    log "Deck already enabled"
elif [ -n "$DECK_VERSION" ]; then
    log "Installing Deck $DECK_VERSION from its release"
    curl -fsSL --retry 3 -o "$E2E_DIR/deck.tar.gz" \
        "https://github.com/nextcloud-releases/deck/releases/download/v$DECK_VERSION/deck-v$DECK_VERSION.tar.gz"
    rm -rf "$SERVER_DIR/apps/deck"
    tar xzf "$E2E_DIR/deck.tar.gz" -C "$SERVER_DIR/apps"
    rm "$E2E_DIR/deck.tar.gz"
    occ app:enable deck
else
    log "Installing the newest Deck for this server from the app store"
    occ app:install deck
fi

# MARK: - Test app

# Real servers run apps that read request parameters while booting, which changes which value wins when the URL
# and the body set the same parameter (#131). This test-only app does the same, so the tests see what they see.
rm -rf "$SERVER_DIR/apps/e2e_early_params"
cp -R "$(dirname "$0")/apps/e2e_early_params" "$SERVER_DIR/apps/"
occ app:enable e2e_early_params

# MARK: - Users

add_user() { # user display-name password
    if ! occ user:info "$1" >/dev/null 2>&1; then
        OC_PASS="$3" occ user:add --password-from-env --display-name="$2" "$1"
    fi
}
add_user alice "Alice Example" "$ALICE_PASSWORD"
add_user bob "Bob Example" "$BOB_PASSWORD"
occ group:add family >/dev/null 2>&1 || true
occ group:adduser family alice
occ group:adduser family bob

# MARK: - Serve

stop_pid() {
    if [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; then
        kill "$(cat "$1")" || true
    fi
}
stop_pid "$E2E_DIR/php.pid"
stop_pid "$E2E_DIR/caddy.pid"

log "Starting PHP on 127.0.0.1:$PHP_PORT"
# The built-in server handles one request at a time unless it forks workers; the app sends several at once.
PHP_CLI_SERVER_WORKERS=8 nohup php -d memory_limit=512M -S "127.0.0.1:$PHP_PORT" -t "$SERVER_DIR" \
    >"$LOG_DIR/php.log" 2>&1 &
echo $! >"$E2E_DIR/php.pid"

cat >"$E2E_DIR/Caddyfile" <<EOF
{
	admin off
	skip_install_trust
	storage file_system "$E2E_DIR/caddy"
	log {
		output file "$LOG_DIR/caddy.log"
	}
}

$SERVER_URL {
	tls internal
	reverse_proxy 127.0.0.1:$PHP_PORT
}
EOF

log "Starting Caddy on $SERVER_URL"
nohup caddy run --config "$E2E_DIR/Caddyfile" --adapter caddyfile >"$LOG_DIR/caddy-run.log" 2>&1 &
echo $! >"$E2E_DIR/caddy.pid"

# Caddy creates its CA and the localhost certificate on first start.
CA_CERT="$E2E_DIR/caddy/pki/authorities/local/root.crt"
for _ in $(seq 1 60); do
    if [ -f "$CA_CERT" ] && curl -fsS --cacert "$CA_CERT" -o /dev/null "$SERVER_URL/status.php"; then
        break
    fi
    sleep 1
done
curl -fsS --cacert "$CA_CERT" "$SERVER_URL/status.php"
echo

cat >"$E2E_DIR/env" <<EOF
E2E_SERVER_URL=$SERVER_URL
E2E_CA_CERT=$CA_CERT
E2E_ADMIN_PASSWORD=$ADMIN_PASSWORD
E2E_ALICE_USER=alice
E2E_ALICE_PASSWORD=$ALICE_PASSWORD
E2E_BOB_USER=bob
E2E_BOB_PASSWORD=$BOB_PASSWORD
E2E_NEXTCLOUD_VERSION=$(occ status --output=json | jq -r .versionstring)
E2E_DECK_VERSION=$(occ app:list --output=json | jq -r '.enabled.deck')
EOF
log "Server ready: $(grep -E 'VERSION' "$E2E_DIR/env" | tr '\n' ' ')"
