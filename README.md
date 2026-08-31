# claude-usage-monitor

여러 PC/서버, 여러 리눅스 계정, 여러 Claude 계정에 걸친 Claude Code 사용량을
중앙에서 수집·시각화하고, 계정별 weekly/5시간 limit 사용률과 초기화 시각까지
한 대시보드에서 보는 스택.

```
[각 머신: Claude Code] --OTLP(4317)--> [OTel Collector] --> [VictoriaMetrics] --> [Grafana]
                                              └-(이벤트 로그)-> [VictoriaLogs]
[limit-poller (계정당 1개, cron)] --api.anthropic.com/api/oauth/usage--> [VictoriaMetrics]
```

수집되는 축: **Claude 계정**(`user_email`, `user_account_uuid`) × **멤버**(`member`, 사람)
× **머신**(`host_name`) × **로그인 계정**(`os_user`) × **세션**(`session_id`) × 모델/토큰타입.

- `member`는 머신/OS와 무관한 "사람" 식별자. 윈도우·리눅스를 같이 쓰는 사람도 이 값으로 묶인다.
- 머신이 Claude 계정을 바꿔 로그인해도 별도 설정 불필요 — `user_email` 라벨은
  Claude Code가 전송 시점의 로그인 계정으로 붙이므로 전환 이후 데이터에 자동 반영된다.

## 1. 중앙 서버 띄우기

```bash
docker compose up -d
```

| 서비스 | 포트 | 용도 |
|---|---|---|
| otel-collector | 4317(gRPC), 4318(HTTP) | 각 머신의 Claude Code가 보내는 OTLP 수신 |
| victoriametrics | 8428 | 시계열 저장 (보존 2년, `--retentionPeriod`) |
| victorialogs | 9428 | 요청 단위 원본 이벤트(`claude_code.api_request`) 저장 (선택) |
| grafana | 3000 | 대시보드 (초기 admin/admin — 접속 후 변경) |

외부에 노출되는 포트는 **4317(OTLP)과 3000(Grafana)뿐**이다. 8428/9428/4318은
127.0.0.1 바인딩이라 서버 안에서만 접근 가능하다 (poller는 `VM_URL=http://localhost:8428`).

Grafana 접속 → `Claude` 폴더에 대시보드 3장이 자동 프로비저닝되며, 서로 링크로 연결된다:

- **📊 Overview** — 전체 계정 limit 현황 + 초기화 시각, "지금 누가 어느 계정을 쓰는 중인가"
  (최근 10분 활동), 전체 토큰 흐름, 24시간 소비 랭킹. 랭킹/활성 테이블의 멤버·계정을
  클릭하면 아래 상세 대시보드로 이동.
- **👤 By Account** — `$account` 변수로 계정 선택. 그 계정의 limit 게이지, 누가 쓰는지
  (멤버×머신), 모델별 분포, 비용, 세션별 상세.
- **💻 By Person** — `$member`/`$host` 변수로 사람 선택. 7일 토큰/비용, 어느 계정으로
  쓰는지(계정 전환 이력 포함), 머신별(윈도우/리눅스) 분해, 세션별 상세.

## 2. 각 머신(클라이언트) 설정

### 빠른 설치 — 원라이너 (권장)

각 PC에서 아래 한 줄만 실행한다. `<중앙서버IP>`를 중앙 서버 주소로 바꾼다.
(별도 인증 불필요.)

**리눅스** (모든 리눅스 계정에 적용, root 필요):
```bash
curl -fsSL https://raw.githubusercontent.com/ultivis-iot/claude-usage-monitor/main/client/install-client.sh \
  | sudo CENTRAL_HOST=<중앙서버IP> bash
# 윈도우와 사람을 묶으려면 MEMBER도: ... | sudo CENTRAL_HOST=<중앙서버IP> MEMBER=kim bash
```

**Windows** (PowerShell, 사용자 단위, 관리자 불필요):
```powershell
$s = irm 'https://raw.githubusercontent.com/ultivis-iot/claude-usage-monitor/main/client/install-client.ps1'
& ([scriptblock]::Create($s)) -CentralHost <중앙서버IP> -Member kim
```

설치 후 새 터미널/VS Code부터 적용된다. 확인: 아무 머신에서 `claude` 세션을 한 번 연 뒤
서버에서 `curl -s 'http://localhost:8428/api/v1/label/__name__/values'` 에 `claude_code_...`가 보이면 성공.

### 수동 설치 (원라이너 대신)

```bash
# CENTRAL_HOST를 중앙 서버 주소로 바꾼 뒤:
sudo cp client/claude-otel.sh /etc/profile.d/claude-otel.sh
# 재로그인하면 그 머신의 모든 리눅스 계정에 적용됨
```

- hostname과 로그인한 리눅스 계정명이 자동으로 라벨(`host.name`, `os.user`)로 붙는다.
- `member`(사람 식별자)는 기본적으로 로그인명을 쓴다. 윈도우·리눅스 계정명이 다른
  사람은 리눅스에서 `~/.claude-member`(또는 머신 공통이면 `/etc/claude-member`)에
  통일된 이름을 한 줄 적어두면 그 값이 우선한다.
- cron/systemd에서 headless로 Claude Code를 돌리는 경우 profile.d가 적용되지 않으므로
  해당 유닛/크론탭에 같은 환경변수를 직접 지정해야 한다.

### Windows 머신

```powershell
# 각 Windows 사용자당 1회 (관리자 권한 불필요).
# -Member 는 리눅스 쪽 member와 같은 이름으로 (생략 시 Windows 사용자명):
powershell -ExecutionPolicy Bypass -File .\client\claude-otel-setup.ps1 -CentralHost "중앙서버주소" -Member "kim"
# 이후 열려 있는 터미널/VS Code 전부 재시작
```

- 사용자 레벨 환경변수로 등록되며, `host.name`/`os.user`에 COMPUTERNAME/USERNAME이
  소문자로 들어가 리눅스 쪽과 같은 라벨 체계를 유지한다.
- **WSL에서 Claude Code를 쓰는 경우엔 Windows 스크립트가 아니라 리눅스와 동일하게**
  `claude-otel.sh`를 WSL 안의 `/etc/profile.d/`에 배포한다
  (WSL hostname은 기본적으로 Windows 컴퓨터명과 같아서 라벨도 자연스럽게 일치).
- 확인: 아무 머신에서 `claude` 세션 하나 연 뒤
  `curl -s 'http://CENTRAL_HOST:8428/api/v1/label/__name__/values' | jq` 에
  `claude_code_...` 메트릭이 보이면 성공.

## 3. limit-poller 설정 (Claude 계정당 1개)

weekly/5h limit은 Anthropic 서버가 계정 단위로만 집계하므로 계정당 poller 1개면 된다.

**동작 방식 — poller는 `claude -p /usage` 출력을 파싱한다.**

> raw `/api/oauth/usage` 엔드포인트는 rate limit(429)과 토큰 scope 문제로 쓸 수 없다.
> 대신 **CLI의 `/usage` 명령**을 비대화형으로 실행해 그 텍스트를 파싱한다. CLI가
> 자체 세션 토큰으로 인증하고, **호출할 때 토큰 갱신까지 자동으로** 해주므로
> 별도의 토큰 파일·refresh 로직이 전혀 필요 없다. 전제는 그 리눅스 계정에
> `claude auth login`이 돼 있는 것뿐이다.

`claude -p /usage` 출력 예:
```
Current session: 10% used · resets Aug 31, 9:09am (UTC)
Current week (all models): 13% used · resets Sep 2, 6:59pm (UTC)
Current week (Fable): 2% used · resets Sep 2, 6:59pm (UTC)
```
→ 각각 `five_hour`, `seven_day`, `seven_day_fable` window로 저장된다.

```bash
# 중앙 서버에서 1회:
sudo mkdir -p /opt/claude-usage
sudo cp limit-poller/limit-poller.sh /opt/claude-usage/

# Claude 계정마다:
sudo useradd -m claude-acct-a
sudo -iu claude-acct-a
claude   # 또는 claude auth login — /login 후 브라우저에서 그 계정으로 로그인
crontab -e
*/15 * * * * VM_URL=http://localhost:8428 ACCOUNT_LABEL=계정이메일 /opt/claude-usage/limit-poller.sh >> $HOME/poller.log 2>&1
```

- headless 서버면 로그인 URL을 다른 기기 브라우저에서 열어 승인하고 코드만 붙여넣는다.
- Claude 계정은 여러 기기 동시 로그인이 가능하므로 기존 PC 세션에 영향 없다.
- `ACCOUNT_LABEL`을 계정 이메일로 지정하면 대시보드 라벨이 명확해진다(생략 시
  `claude auth status`의 이메일 → `unknown`).
- **토큰 지속성**: `claude -p /usage`가 매 호출마다 CLI 토큰을 갱신하므로, 폴링이 도는
  한 토큰은 계속 살아 있다. (단, 그 계정이 세션/주간 한도 100%로 완전히 막히면 호출이
  실패할 수 있고, 그때는 health가 0으로 표시된다.)

생성되는 메트릭:

- `claude_limit_utilization{account, window}` — 사용률 % (window: `five_hour`, `seven_day`, `seven_day_fable` 등)
- `claude_limit_resets_at{account, window}` — 초기화 시각 (unix epoch)
- `claude_limit_up{account}` — **1=정상 / 0=오류** (아래 health 참고)
- `claude_limit_last_run_timestamp{account}` — 마지막 실행 시각(epoch), staleness 감지용

### 계정 오류 가시화 (health)

poller는 **성공·실패 어느 경우든 health 메트릭을 항상 push**한다. 그래서 특정 계정의
문제를 Overview 대시보드에서 바로 볼 수 있다:

- **🚦 계정 Poll 상태**: `claude_limit_up`이 0(빨강)이면 그 계정에 문제 있음
  (미로그인, 또는 한도 100%로 `/usage` 호출 실패 등)
- **마지막 수집 경과(초)**: 값이 크면 poller가 죽었거나 cron 미동작

`claude_limit_up == 0`이 되면 그 계정에서 `claude auth login`으로 재로그인하면 된다.
(poller가 `/usage` 호출 시마다 토큰을 갱신하므로 평상시엔 재로그인이 필요 없다.)

알림 추천: `claude_limit_up == 0` → Grafana Alerting으로 Slack/Discord 통지.

## 유용한 쿼리

```promql
# 최근 7일, 누가/어디서/어느 계정으로 얼마나 썼나
sum by (os_user, host_name, user_email) (increase(claude_code_token_usage_tokens_total[7d]))

# 계정별 시간당 비용
sum by (user_email) (increase(claude_code_cost_usage_USD_total[1h]))

# weekly limit 현황
claude_limit_utilization{window="seven_day"}
```

알림 추천: Grafana Alerting에서 `claude_limit_utilization{window="seven_day"} > 80`
→ Slack/Discord 연동.

## 주의사항

- **메트릭 이름 확인**: OTel→Prometheus 변환에서 monotonic sum은 unit+`_total` 접미사가
  붙는다 (예: `claude_code_token_usage` → `claude_code_token_usage_tokens_total`).
  실제 이름은 `curl -s 'http://localhost:8428/api/v1/label/__name__/values'`(서버에서)로 확인.
- **delta temporality**: Claude Code는 메트릭을 delta로 내보내므로 collector에
  `delta_to_cumulative` processor가 반드시 있어야 저장된다(없으면 조용히 drop됨).
- **limit은 `claude -p /usage` 파싱**: raw `/api/oauth/usage`는 429/scope로 불가.
  Claude Code 업데이트로 `/usage` 출력 형식이 바뀌면 poller의 파싱을 맞춰줄 것.
- **cardinality**: 세션 수가 아주 많아지면 `OTEL_METRICS_INCLUDE_SESSION_ID=false`로
  메트릭에서 session.id를 빼고, 세션 단위 분석은 VictoriaLogs의 이벤트로 대체.
- 이미지 태그는 편의상 `latest`로 두었다. 운영 안정성이 필요하면 동작 확인 후 버전을 고정할 것.
