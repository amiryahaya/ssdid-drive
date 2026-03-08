#!/usr/bin/env bash
set -euo pipefail

# Deploy landing page and admin portal static files to the VPS.
# Usage: ./scripts/deploy-static.sh <user@host>

REMOTE="${1:?Usage: $0 <user@host>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Building admin portal ==="
cd "$REPO_ROOT/clients/admin"
npm ci
npm run build

echo "=== Deploying landing page ==="
rsync -avz --delete "$REPO_ROOT/clients/landing/" "$REMOTE:/var/www/landing/"

echo "=== Deploying admin portal ==="
rsync -avz --delete "$REPO_ROOT/clients/admin/dist/" "$REMOTE:/var/www/admin/"

echo "=== Done ==="
echo "Landing: https://drive.ssdid.my/"
echo "Admin:   https://drive.ssdid.my/admin/"
