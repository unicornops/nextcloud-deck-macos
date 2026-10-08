#!/usr/bin/env bash
# Stops the server started by start-server.sh. Its files stay in $E2E_DIR until you delete them.
set -euo pipefail

E2E_DIR="${E2E_DIR:-build/e2e}"
for name in caddy php nginx php-fpm redis mariadb; do
    pid_file="$E2E_DIR/$name.pid"
    if [ -f "$pid_file" ]; then
        kill "$(cat "$pid_file")" 2>/dev/null || true
        rm -f "$pid_file"
    fi
done
