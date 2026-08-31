#!/usr/bin/env bash
# Claude 계정 OAuth 로그인 헬퍼 (headless poller 계정용, TUI 불필요)
#
# Claude Code와 같은 공개 client id로 PKCE authorization code 플로우를 수행해
# ~/.claude/.credentials.json 을 생성한다. poller가 바로 사용 가능.
#
# 사용법 (해당 리눅스 계정으로):
#   claude-oauth-login.sh start
#     → 출력된 URL을 브라우저에서 열어 해당 Claude 계정으로 로그인/승인
#     → 화면에 표시되는 코드(형식: xxxx#yyyy)를 복사
#   claude-oauth-login.sh finish 'xxxx#yyyy'
#     → 토큰 교환 후 credentials 저장
set -euo pipefail

CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"   # Claude Code 공개 OAuth client id
REDIRECT_URI="https://console.anthropic.com/oauth/code/callback"
PENDING="$HOME/.claude/oauth-pending"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

case "${1:-}" in
  start)
    mkdir -p "$HOME/.claude"
    VERIFIER=$(openssl rand 32 | b64url)
    CHALLENGE=$(printf %s "$VERIFIER" | openssl dgst -sha256 -binary | b64url)
    printf %s "$VERIFIER" > "$PENDING"
    chmod 600 "$PENDING"
    echo "https://claude.ai/oauth/authorize?code=true&client_id=$CLIENT_ID&response_type=code&redirect_uri=https%3A%2F%2Fconsole.anthropic.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key%20user%3Aprofile%20user%3Ainference&code_challenge=$CHALLENGE&code_challenge_method=S256&state=$VERIFIER"
    ;;
  finish)
    CODE_RAW="${2:?인증 코드를 인자로 주세요 (형식: code#state)}"
    [ -f "$PENDING" ] || { echo "먼저 start를 실행하세요"; exit 1; }
    VERIFIER=$(cat "$PENDING")
    CODE="${CODE_RAW%%#*}"
    STATE="${CODE_RAW#*#}"
    [ "$STATE" = "$CODE_RAW" ] && STATE="$VERIFIER"
    RESP=$(curl -sf --max-time 30 https://console.anthropic.com/v1/oauth/token \
      -H "Content-Type: application/json" \
      -d "{\"grant_type\":\"authorization_code\",\"code\":\"$CODE\",\"state\":\"$STATE\",\"client_id\":\"$CLIENT_ID\",\"redirect_uri\":\"$REDIRECT_URI\",\"code_verifier\":\"$VERIFIER\"}") \
      || { echo "토큰 교환 요청 실패"; exit 1; }
    AT=$(jq -r '.access_token // empty' <<<"$RESP")
    RT=$(jq -r '.refresh_token // empty' <<<"$RESP")
    [ -n "$AT" ] || { echo "토큰 교환 실패: $RESP"; exit 1; }
    EXP=$(( ( $(date +%s) + $(jq -r '.expires_in // 3600' <<<"$RESP") ) * 1000 ))
    SUB=$(jq -r '.account.subscription_type // .subscription_type // "unknown"' <<<"$RESP")
    jq -n --arg at "$AT" --arg rt "$RT" --argjson exp "$EXP" --arg sub "$SUB" \
      '{claudeAiOauth:{accessToken:$at,refreshToken:$rt,expiresAt:$exp,scopes:["user:inference","user:profile"],subscriptionType:$sub}}' \
      > "$HOME/.claude/.credentials.json"
    chmod 600 "$HOME/.claude/.credentials.json"
    rm -f "$PENDING"
    echo "로그인 완료 — $HOME/.claude/.credentials.json 저장됨 (subscription: $SUB)"
    ;;
  *)
    echo "사용법: $0 start | finish '<code#state>'"
    exit 1
    ;;
esac
