# Windows용 Claude Code 텔레메트리 설정 — 각 Windows 사용자당 1회 실행
#
# 실행:
#   powershell -ExecutionPolicy Bypass -File .\claude-otel-setup.ps1 -CentralHost "중앙서버주소"
#
# 사용자(HKCU) 레벨 환경변수로 등록되므로 관리자 권한이 필요 없고,
# 이후 여는 모든 터미널/VS Code/CMD 에서 Claude Code에 적용된다.
# COMPUTERNAME/USERNAME은 머신·계정마다 고정값이라 실행 시점에 박아 넣어도 안전하다.

param(
    [Parameter(Mandatory = $true)]
    [string]$CentralHost,

    # 머신/OS와 무관한 "사람" 식별자. 리눅스 쪽 member 값과 같게 지정하면
    # 윈도우·리눅스 사용량이 한 사람으로 묶여 집계된다. 생략 시 Windows 사용자명.
    [string]$Member = ""
)

if (-not $Member) { $Member = $env:USERNAME.ToLower() }

$vars = [ordered]@{
    "CLAUDE_CODE_ENABLE_TELEMETRY" = "1"
    "OTEL_METRICS_EXPORTER"        = "otlp"
    "OTEL_LOGS_EXPORTER"           = "otlp"
    "OTEL_EXPORTER_OTLP_PROTOCOL"  = "grpc"
    "OTEL_EXPORTER_OTLP_ENDPOINT"  = "http://${CentralHost}:4317"
    # 리눅스 쪽과 같은 라벨 체계(host.name, os.user).
    # Windows COMPUTERNAME은 대문자라서 리눅스 hostname과 라벨이 갈라지지 않게 소문자로 통일.
    "OTEL_RESOURCE_ATTRIBUTES"     = "host.name=$($env:COMPUTERNAME.ToLower()),os.user=$($env:USERNAME.ToLower()),member=$Member"
}

foreach ($kv in $vars.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "User")
    Write-Host "set $($kv.Key)=$($kv.Value)"
}

Write-Host ""
Write-Host "완료. 열려 있는 터미널/VS Code를 전부 재시작해야 적용됩니다."
Write-Host "해제하려면: 위 변수들을 [Environment]::SetEnvironmentVariable(이름, `$null, 'User') 로 삭제"
