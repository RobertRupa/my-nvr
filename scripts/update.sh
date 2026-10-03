#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PORTAINER_URL="${PORTAINER_URL:-https://127.0.0.1:9443}"
PASSWORD_FILE="${PORTAINER_PASSWORD_FILE:-/etc/my-nvr/portainer-admin-password}"

bash "$SCRIPT_DIR/backup.sh"

git -c safe.directory="$REPO_DIR" -C "$REPO_DIR" fetch origin main
git -c safe.directory="$REPO_DIR" -C "$REPO_DIR" pull --ff-only origin main

PASSWORD="$(cat "$PASSWORD_FILE")"
AUTH="$(jq -cn --arg u admin --arg p "$PASSWORD" '{Username:$u,Password:$p}')"
JWT="$(curl -kfsS -X POST "$PORTAINER_URL/api/auth" -H 'Content-Type: application/json' --data "$AUTH" | jq -r '.jwt // empty')"
[[ -n "$JWT" ]] || { echo "Portainer authentication failed." >&2; exit 1; }

STACKS="$(curl -kfsS "$PORTAINER_URL/api/stacks" -H "Authorization: Bearer $JWT")"
STACK_ID="$(jq -r '.[] | select(.Name == "my-nvr") | .Id' <<<"$STACKS" | head -n1)"
ENDPOINT_ID="$(jq -r '.[] | select(.Name == "my-nvr") | .EndpointId' <<<"$STACKS" | head -n1)"

[[ -n "$STACK_ID" && -n "$ENDPOINT_ID" ]] || { echo "Portainer stack my-nvr not found." >&2; exit 1; }

PAYLOAD='{"Env":[],"Prune":false,"RepositoryAuthentication":false,"RepositoryReferenceName":"refs/heads/main","RepullImageAndRedeploy":true}'

curl -kfsS -X PUT   "$PORTAINER_URL/api/stacks/$STACK_ID/git/redeploy?endpointId=$ENDPOINT_ID"   -H "Authorization: Bearer $JWT"   -H 'Content-Type: application/json'   --data "$PAYLOAD" >/dev/null

echo "Redeployment requested through Portainer."
