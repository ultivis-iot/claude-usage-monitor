#!/usr/bin/env bash
# Claude Code 텔레메트리 클라이언트 설치 (리눅스)
#
# 원라이너:
#   curl -fsSL <RAW_URL>/client/install-client.sh | sudo CENTRAL_HOST=<중앙서버IP> bash
#
# 환경변수:
#   CENTRAL_HOST  중앙 서버 주소 (필수)
#   MEMBER        사람 식별자 (선택; 미지정 시 로그인명. 윈도우와 통일하려면 지정)
set -euo pipefail

CENTRAL_HOST="${CENTRAL_HOST:?CENTRAL_HOST를 지정하세요 (예: CENTRAL_HOST=<중앙서버IP>)}"
DEST=/etc/profile.d/claude-otel.sh

[ "$(id -u)" = "0" ] || { echo "root 권한 필요: sudo ... bash"; exit 1; }

# MEMBER 파일 우선순위(~/.claude-member > /etc/claude-member > 로그인명)는 런타임에 평가.
# 설치 시 MEMBER를 넘기면 /etc/claude-member 에 기본값으로 기록(각 사용자가 ~/.claude-member로 덮어쓸 수 있음).
if [ -n "${MEMBER:-}" ] && [ ! -f /etc/claude-member ]; then
  printf '%s\n' "$MEMBER" > /etc/claude-member
fi

cat > "$DEST" <<EOF
# Claude Code 텔레메트리 (claude-usage-monitor가 설치)
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT="http://${CENTRAL_HOST}:4317"
_member="\$(cat "\$HOME/.claude-member" 2>/dev/null || cat /etc/claude-member 2>/dev/null || id -un)"
export OTEL_RESOURCE_ATTRIBUTES="host.name=\$(hostname -s),os.user=\$(id -un),member=\${_member}"
unset _member
EOF
chmod 644 "$DEST"

echo "설치 완료: $DEST (CENTRAL_HOST=$CENTRAL_HOST)"
echo "적용: 재로그인 또는  source $DEST  후 claude 실행"
