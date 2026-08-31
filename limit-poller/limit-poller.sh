#!/usr/bin/env bash
# Claude 계정의 5시간/weekly limit 사용률을 조회해 VictoriaMetrics로 push한다.
# 성공/실패와 무관하게 계정별 health 메트릭을 항상 push하므로, 특정 계정의 오류
# (토큰 만료·401·429·로그인 안 됨 등)도 Grafana에서 바로 확인할 수 있다.
#
# 조회 대상: 비공식 엔드포인트 GET https://api.anthropic.com/api/oauth/usage
#   (User-Agent: claude-code/<버전> 필수)
#
# 사용 예 (crontab -e):
#   */15 * * * * VM_URL=http://CENTRAL_HOST:8428 ACCOUNT_LABEL=acct@x.com /opt/claude-usage/limit-poller.sh >> $HOME/poller.log 2>&1
#
# 환경변수:
#   VM_URL                  VictoriaMetrics 주소 (필수)
#   ACCOUNT_LABEL           계정 라벨 (권장; 없으면 ~/.claude.json 이메일 → "unknown")
#   CLAUDE_CODE_OAUTH_TOKEN 장수명 토큰 (claude setup-token). 없으면 아래 파일/creds 순.
#   CRED_FILE               기본 ~/.claude/.credentials.json
set -uo pipefail

VM_URL="${VM_URL:?VM_URL을 지정하세요 (예: http://CENTRAL_HOST:8428)}"
CRED_FILE="${CRED_FILE:-$HOME/.claude/.credentials.json}"
CLAUDE_JSON="${CLAUDE_JSON:-$HOME/.claude.json}"
TOKEN_FILE="${TOKEN_FILE:-$HOME/.claude/oauth-token}"

command -v jq >/dev/null || { echo "jq가 필요합니다"; exit 1; }

ACCOUNT="${ACCOUNT_LABEL:-$(jq -r '.oauthAccount.emailAddress // "unknown"' "$CLAUDE_JSON" 2>/dev/null || echo unknown)}"
CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
UA="claude-code/${CC_VERSION:-2.0.0}"

# VictoriaMetrics로 prometheus 텍스트 라인 push (stdin)
push() { curl -sf --max-time 15 --data-binary @- "$VM_URL/api/v1/import/prometheus"; }

# 계정 health 메트릭은 성공/실패 어느 경로든 항상 남긴다.
#   claude_limit_up             1=정상, 0=오류
#   claude_limit_http_code      usage 응답 코드 (000=네트워크 실패, 0=요청 못함)
#   claude_limit_last_run_timestamp  마지막 실행 시각(epoch) — staleness 감지용
report_health() {
  local up="$1" code="$2"
  printf 'claude_limit_up{account="%s"} %s\nclaude_limit_http_code{account="%s"} %s\nclaude_limit_last_run_timestamp{account="%s"} %s\n' \
    "$ACCOUNT" "$up" "$ACCOUNT" "$code" "$ACCOUNT" "$(date +%s)" | push || true
}

fail() {  # up=0, http_code, 로그 메시지 → health push 후 종료
  local code="$1" msg="$2"
  echo "$(date -Is) ERR account=$ACCOUNT code=$code: $msg"
  report_health 0 "$code"
  exit 1
}

# --- 토큰 확보 (우선순위: env > 파일 > .credentials.json) ---
TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}"
[ -n "$TOKEN" ] || TOKEN=$(cat "$TOKEN_FILE" 2>/dev/null || true)
[ -n "$TOKEN" ] || TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CRED_FILE" 2>/dev/null)
[ -n "$TOKEN" ] || fail 0 "토큰 없음 (CLAUDE_CODE_OAUTH_TOKEN / $TOKEN_FILE / $CRED_FILE) — 로그인 필요"

# cron 정각에 여러 계정 요청이 몰리지 않게 무작위 지연
sleep $((RANDOM % 60))

# --- usage 조회 (HTTP 코드까지 캡처, 실패해도 health 남김) ---
RAW=$(curl -s -w $'\n%{http_code}' --max-time 30 https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" -H "User-Agent: $UA" -H "Content-Type: application/json")
HTTP_CODE=$(printf '%s' "$RAW" | tail -n1)
BODY=$(printf '%s' "$RAW" | sed '$d')
[[ "$HTTP_CODE" =~ ^[0-9]+$ ]] || HTTP_CODE=000

[ "$HTTP_CODE" = "200" ] || fail "$HTTP_CODE" "usage 응답 비정상 (401=토큰만료/무효, 429=rate limit, 000=네트워크): $(printf '%s' "$BODY" | head -c 200)"

# --- utilization (숫자인 윈도우만) ---
UTIL=$(jq -r --arg acct "$ACCOUNT" '
  to_entries[]
  | select((.value | type) == "object")
  | select((.value.utilization | type) == "number")
  | "claude_limit_utilization{account=\"\($acct)\",window=\"\(.key)\"} \(.value.utilization)"
' <<<"$BODY" 2>/dev/null)
[ -n "$UTIL" ] || fail "$HTTP_CODE" "응답 파싱 실패/윈도우 없음: $(printf '%s' "$BODY" | head -c 200)"

# --- resets_at (마이크로초+타임존 오프셋 → GNU date로 epoch 변환) ---
RESET_METRICS=""
while read -r WIN ISO; do
  [ -n "$WIN" ] || continue
  EPOCH=$(date -d "$ISO" +%s 2>/dev/null) || continue
  RESET_METRICS+="claude_limit_resets_at{account=\"$ACCOUNT\",window=\"$WIN\"} $EPOCH"$'\n'
done < <(jq -r '
  to_entries[]
  | select((.value | type) == "object")
  | select((.value.utilization | type) == "number")
  | select(.value.resets_at != null)
  | "\(.key) \(.value.resets_at)"
' <<<"$BODY" 2>/dev/null)

HEALTH=$(printf 'claude_limit_up{account="%s"} 1\nclaude_limit_http_code{account="%s"} 200\nclaude_limit_last_run_timestamp{account="%s"} %s' \
  "$ACCOUNT" "$ACCOUNT" "$ACCOUNT" "$(date +%s)")

METRICS=$(printf '%s\n%s\n%s' "$UTIL" "$RESET_METRICS" "$HEALTH" | grep -avE '^$')

printf '%s\n' "$METRICS" | push || fail "$HTTP_CODE" "VM push 실패"

echo "$(date -Is) OK account=$ACCOUNT ($(printf '%s\n' "$UTIL" | grep -c utilization) windows)"
