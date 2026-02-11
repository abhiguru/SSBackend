#!/bin/bash
set -euo pipefail

# Run all custom init scripts from /custom-init/ in order
# This runs AFTER the Supabase image's built-in migrate.sh
for f in /custom-init/*.sql /custom-init/*.sh; do
    [ -e "$f" ] || continue
    case "$f" in
        *.sh)
            echo "$0: running $f"
            . "$f"
            ;;
        *.sql)
            echo "$0: running $f"
            psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc -U supabase_admin -d postgres -f "$f"
            ;;
    esac
done
