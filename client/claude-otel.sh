# Claude Code 텔레메트리 설정 — 각 머신의 /etc/profile.d/claude-otel.sh 로 배포
#
# 배포:   sudo cp claude-otel.sh /etc/profile.d/claude-otel.sh
# 적용:   재로그인 (또는 source /etc/profile.d/claude-otel.sh)
#
# CENTRAL_HOST 만 실제 중앙 서버 주소로 바꾸면 됨. 나머지는 모든 머신 공통.

export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT="http://CENTRAL_HOST:4317"

# member = 머신/OS와 무관한 "사람" 식별자. 윈도우·리눅스를 같이 쓰는 사람도
# 이 값으로 묶어서 집계된다. 우선순위: ~/.claude-member > /etc/claude-member > 로그인명.
# 리눅스 계정명이 윈도우 USERNAME과 다른 사람은 ~/.claude-member 에 통일된 이름을 적어둘 것.
_member="$(cat "$HOME/.claude-member" 2>/dev/null || cat /etc/claude-member 2>/dev/null || id -un)"

# 머신명 + 로그인한 리눅스 계정명 + member가 모든 메트릭/이벤트에 라벨로 붙는다.
# user.* 네임스페이스는 Claude Code가 Claude 계정 식별용으로 쓰므로 os.user 사용.
export OTEL_RESOURCE_ATTRIBUTES="host.name=$(hostname -s),os.user=$(id -un),member=${_member}"
unset _member
