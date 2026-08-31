#!/usr/bin/env bash
# Claude 계정의 세션/주간 limit을 조회해 VictoriaMetrics로 push한다.
#
# 조회 방식: `claude -p /usage` 의 텍스트 출력을 파싱한다. (raw /api/oauth/usage 는
# 429/scope 문제로 불가.) CLI가 자체 토큰으로 인증하고 호출 시 토큰 갱신까지 해주므로,
# 별도 토큰 파일/refresh 로직이 필요 없다. 성공/실패 무관하게 health 메트릭을 남긴다.
#
# 전제: 해당 리눅스 계정에 `claude`가 로그인돼 있어야 한다 (claude auth login).
#
# crontab 예:
#   */15 * * * * VM_URL=http://localhost:8428 ACCOUNT_LABEL=acct@x.com /opt/claude-usage/limit-poller.sh >> $HOME/poller.log 2>&1
#
# 환경변수:
#   VM_URL         VictoriaMetrics 주소 (필수)
#   ACCOUNT_LABEL  계정 라벨 (권장; 없으면 claude auth status 이메일 → unknown)
#   CLAUDE_BIN     claude 실행 파일 경로 (기본 자동 탐지)
set -uo pipefail

VM_URL="${VM_URL:?VM_URL을 지정하세요 (예: http://CENTRAL_HOST:8428)}"

# cron의 최소 PATH에서도 claude를 찾도록
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}"
for c in "$HOME/.local/bin/claude" "$HOME/.local/share/claude/latest/claude" /usr/bin/claude /usr/local/bin/claude; do
  [ -n "$CLAUDE_BIN" ] && break; [ -x "$c" ] && CLAUDE_BIN="$c"
done
[ -n "$CLAUDE_BIN" ] || { echo "$(date -Is) claude 실행 파일을 찾지 못함"; exit 1; }
command -v jq >/dev/null || { echo "jq 필요"; exit 1; }

ACCOUNT="${ACCOUNT_LABEL:-$("$CLAUDE_BIN" auth status 2>/dev/null | jq -r '.email // empty' 2>/dev/null || echo unknown)}"
[ -n "$ACCOUNT" ] || ACCOUNT=unknown

push() { curl -sf --max-time 15 --data-binary @- "$VM_URL/api/v1/import/prometheus"; }
report_health() {
  printf 'claude_limit_up{account="%s"} %s\nclaude_limit_last_run_timestamp{account="%s"} %s\n' \
    "$ACCOUNT" "$1" "$ACCOUNT" "$(date +%s)" | push || true
}
fail() { echo "$(date -Is) ERR account=$ACCOUNT: $1"; report_health 0; exit 1; }

# cron 정각 몰림 방지
sleep $((RANDOM % 30))

# /usage 조회 (CLI가 토큰 인증·갱신까지 수행)
OUT=$(timeout 120 "$CLAUDE_BIN" -p /usage 2>&1) || fail "claude -p /usage 실패: $(printf '%s' "$OUT" | head -c 200)"
printf '%s' "$OUT" | grep -q "% used" || fail "usage 출력 파싱 불가(미로그인/한도?): $(printf '%s' "$OUT" | head -c 200)"

METRICS=""
while IFS= read -r line; do
  case "$line" in *"% used"*"resets"*) ;; *) continue ;; esac
  label=$(printf '%s' "$line" | sed -E 's/^[^A-Za-z]*Current (.*): [0-9]+% used.*/\1/')
  pct=$(printf '%s'   "$line" | sed -E 's/.*: ([0-9]+)% used.*/\1/')
  datestr=$(printf '%s' "$line" | sed -E 's/.*resets (.*) \(UTC\).*/\1/')
  case "$label" in
    session)              win=five_hour ;;
    "week (all models)")  win=seven_day ;;
    "week ("*")")         m=$(printf '%s' "$label" | sed -E 's/week \((.*)\)/\1/' | tr 'A-Z ' 'a-z_'); win="seven_day_$m" ;;
    *)                    win=$(printf '%s' "$label" | tr 'A-Z ()' 'a-z___') ;;
  esac
  [ -n "$pct" ] || continue
  METRICS+="claude_limit_utilization{account=\"$ACCOUNT\",window=\"$win\"} $pct"$'\n'
  epoch=$(date -u -d "$datestr UTC" +%s 2>/dev/null || true)
  [ -n "$epoch" ] && METRICS+="claude_limit_resets_at{account=\"$ACCOUNT\",window=\"$win\"} $epoch"$'\n'
done <<<"$OUT"

[ -n "$METRICS" ] || fail "파싱된 윈도우 없음: $(printf '%s' "$OUT" | head -c 200)"

METRICS+="claude_limit_up{account=\"$ACCOUNT\"} 1"$'\n'
METRICS+="claude_limit_last_run_timestamp{account=\"$ACCOUNT\"} $(date +%s)"$'\n'

printf '%s' "$METRICS" | push || fail "VM push 실패"
echo "$(date -Is) OK account=$ACCOUNT ($(printf '%s' "$METRICS" | grep -c utilization) windows)"
