#!/usr/bin/env bash
set -euo pipefail

readonly client_id="Iv1.b507a08c87ecfe98"
readonly state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/lazygit-commit"
readonly auth_file="$state_dir/auth.json"
readonly copilot_url="https://api.githubcopilot.com/chat/completions"
readonly token_url="https://api.github.com/copilot_internal/v2/token"
readonly device_url="https://github.com/login/device/code"
readonly access_url="https://github.com/login/oauth/access_token"

die() { printf 'aicommit: %s\n' "$*" >&2; exit 1; }

for command in curl jq git; do
  command -v "$command" >/dev/null || die "missing dependency: $command"
done

mkdir -p "$state_dir"
[[ -f "$auth_file" ]] || { printf '{}\n' >"$auth_file"; chmod 600 "$auth_file"; }

auth_get() { jq -r --arg key "$1" '.[$key] // empty' "$auth_file"; }

auth_set() {
  local tmp
  tmp=$(mktemp)
  jq --arg key "$1" --arg value "$2" '.[$key] = $value' "$auth_file" >"$tmp"
  mv "$tmp" "$auth_file"
  chmod 600 "$auth_file"
}

refresh_token() {
  local response token expires
  response=$(curl -fsS "$token_url" \
    -H 'Accept: application/json' \
    -H "Authorization: Bearer $(auth_get github_token)" \
    -H 'Editor-Version: vscode/1.99.3' \
    -H 'Editor-Plugin-Version: copilot-chat/0.26.7' \
    -H 'User-Agent: GitHubCopilotChat/0.26.7') || die 'unable to refresh Copilot token'
  token=$(jq -r '.token // empty' <<<"$response")
  expires=$(jq -r '.expires_at // 0' <<<"$response")
  [[ -n "$token" ]] || die 'GitHub account has no Copilot access'
  auth_set copilot_token "$token"
  auth_set copilot_expires "$expires"
}

copilot_token() {
  local token expires now
  token=$(auth_get copilot_token)
  expires=$(auth_get copilot_expires)
  now=$(date +%s)
  if [[ -z "$token" || "${expires:-0}" -le $((now + 60)) ]]; then
    [[ -n "$(auth_get github_token)" ]] || die 'run: aicommit login'
    refresh_token
    token=$(auth_get copilot_token)
  fi
  printf '%s' "$token"
}

login() {
  local response device user url interval expires_in attempt error token
  response=$(curl -fsS "$device_url" -X POST \
    -H 'Accept: application/json' -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg id "$client_id" '{client_id: $id, scope: "read:user"}')") \
    || die 'unable to start GitHub device flow'
  device=$(jq -r '.device_code // empty' <<<"$response")
  user=$(jq -r '.user_code // empty' <<<"$response")
  url=$(jq -r '.verification_uri // .verification_uri_complete // empty' <<<"$response")
  interval=$(jq -r '.interval // 5' <<<"$response")
  expires_in=$(jq -r '.expires_in // 900' <<<"$response")
  [[ -n "$device" && -n "$user" && -n "$url" ]] || die "invalid device-flow response: $response"

  printf 'Open %s\nand enter code %s\n\nPress Enter after authorizing... ' "$url" "$user"
  read -r

  attempt=0
  while (( attempt < expires_in / interval )); do
    response=$(curl -fsS "$access_url" -X POST \
      -H 'Accept: application/json' -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg id "$client_id" --arg code "$device" \
        '{client_id: $id, device_code: $code, grant_type: "urn:ietf:params:oauth:grant-type:device_code"}')") \
      || die 'unable to poll GitHub device flow'
    token=$(jq -r '.access_token // empty' <<<"$response")
    [[ -n "$token" ]] && { auth_set github_token "$token"; refresh_token; printf 'Logged in.\n'; return; }
    error=$(jq -r '.error // empty' <<<"$response")
    case "$error" in
      authorization_pending) sleep "$interval" ;;
      slow_down) interval=$((interval + 5)); sleep "$interval" ;;
      *) die "GitHub login failed: ${error:-unknown error}" ;;
    esac
    attempt=$((attempt + 1))
  done
  die 'GitHub device code expired'
}

generate() {
  local diff history prompt payload response message
  git diff --cached --quiet && die 'stage changes first'
  diff=$(git diff --cached --no-ext-diff)
  history=$(git log -5 --oneline 2>/dev/null || true)
  prompt=$(printf '%s\n\nRecent commits:\n%s\n\nStaged diff:\n%s\n' \
    'Write one Conventional Commits message for the staged changes below.' \
    "$history" "${diff:0:12000}")
  payload=$(jq -nc --arg model "${AICOMMIT_MODEL:-gpt-4o-mini}" --arg content "$prompt" \
    '{model: $model, messages: [{role: "user", content: $content}], max_tokens: 100, temperature: 0.2}')
  response=$(curl -fsS "$copilot_url" -X POST \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $(copilot_token)" \
    -H 'Editor-Version: vscode/1.99.3' \
    -H 'Editor-Plugin-Version: copilot-chat/0.26.7' \
    -H 'Openai-Organization: github-copilot' \
    -H 'Openai-Intent: conversation-panel' \
    -d "$payload") || die 'Copilot request failed'
  message=$(jq -r '.choices[0].message.content // empty |
    gsub("[\\r\\n]+"; " ") |
    gsub("[\\\"\\u0027\\u0024\\u0060;|&<>]"; "") |
    gsub("^[[:space:]]+|[[:space:]]+$"; "")' <<<"$response")
  [[ -n "$message" ]] || die "invalid Copilot response: $response"
  printf '%s\n' "$message"
}

case "${1:-generate}" in
  generate) generate ;;
  login) login ;;
  logout) rm -f "$auth_file" ;;
  status) [[ -n "$(auth_get github_token)" ]] && printf 'logged in\n' || printf 'logged out\n' ;;
  *) die "usage: ${0##*/} [generate|login|logout|status]" ;;
esac
