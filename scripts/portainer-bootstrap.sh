#!/usr/bin/env bash
set -Eeuo pipefail

PORTAINER_URL="${PORTAINER_URL:-https://127.0.0.1:9443}"
PASSWORD_FILE="${PORTAINER_PASSWORD_FILE:-/etc/my-nvr/portainer-admin-password}"
REPO_URL="${MY_NVR_REPO_URL:-https://github.com/RobertRupa/my-nvr.git}"
REPO_REF="${MY_NVR_REPO_REF:-refs/heads/main}"
STACK_NAME="${MY_NVR_STACK_NAME:-my-nvr}"
COMPOSE_FILE="${MY_NVR_COMPOSE_FILE:-compose.yml}"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ -r "$PASSWORD_FILE" ]] || die "Cannot read Portainer password file: $PASSWORD_FILE"

PASSWORD="$(cat "$PASSWORD_FILE")"
AUTH_PAYLOAD="$(jq -cn --arg u admin --arg p "$PASSWORD" '{Username:$u,Password:$p}')"
AUTH_RESPONSE="$(curl -kfsS -X POST "$PORTAINER_URL/api/auth"   -H 'Content-Type: application/json'   --data "$AUTH_PAYLOAD")" || die "Portainer authentication failed."

JWT="$(jq -r '.jwt // empty' <<<"$AUTH_RESPONSE")"
[[ -n "$JWT" ]] || die "Portainer did not return a JWT."

ENDPOINTS="$(curl -kfsS "$PORTAINER_URL/api/endpoints" -H "Authorization: Bearer $JWT")"
ENDPOINT_ID="$(jq -r 'map(select(.Type == 1)) | first | .Id // empty' <<<"$ENDPOINTS")"
[[ -n "$ENDPOINT_ID" ]] || ENDPOINT_ID="$(jq -r 'first | .Id // empty' <<<"$ENDPOINTS")"
[[ -n "$ENDPOINT_ID" ]] || die "No local Docker environment found in Portainer."

STACKS="$(curl -kfsS "$PORTAINER_URL/api/stacks" -H "Authorization: Bearer $JWT")"
STACK_ID="$(jq -r --arg n "$STACK_NAME" '.[] | select(.Name == $n) | .Id' <<<"$STACKS" | head -n1)"

if [[ -n "$STACK_ID" ]]; then
  echo "Portainer stack '$STACK_NAME' already exists (id=$STACK_ID); leaving it unchanged."
  exit 0
fi

PAYLOAD="$(jq -cn   --arg name "$STACK_NAME"   --arg url "$REPO_URL"   --arg ref "$REPO_REF"   --arg compose "$COMPOSE_FILE"   '{
    Name:$name,
    RepositoryURL:$url,
    RepositoryReferenceName:$ref,
    ComposeFile:$compose,
    RepositoryAuthentication:false,
    TLSSkipVerify:false
  }')"

TMP="$(mktemp)"
HTTP_CODE="$(curl -ksS -o "$TMP" -w '%{http_code}' -X POST   "$PORTAINER_URL/api/stacks/create/standalone/repository?endpointId=$ENDPOINT_ID"   -H "Authorization: Bearer $JWT"   -H 'Content-Type: application/json'   --data "$PAYLOAD")"

if [[ "$HTTP_CODE" != "200" ]]; then
  cat "$TMP" >&2
  rm -f "$TMP"
  die "Portainer failed to create the Git stack (HTTP $HTTP_CODE)."
fi

STACK_ID="$(jq -r '.Id // empty' "$TMP")"
rm -f "$TMP"
echo "Created Portainer Git stack '$STACK_NAME' (id=$STACK_ID) from $REPO_URL $REPO_REF:$COMPOSE_FILE."
