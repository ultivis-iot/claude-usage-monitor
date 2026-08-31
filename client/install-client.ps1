# Claude Code 텔레메트리 클라이언트 설치 (Windows)
#
# 원라이너 (PowerShell):
#   & ([scriptblock]::Create((irm '<RAW_URL>/client/install-client.ps1'))) -CentralHost <중앙서버IP>
#   (선택) -Member kim  으로 리눅스 쪽 member와 통일
#
# 사용자 레벨 환경변수로 등록되므로 관리자 권한 불필요. 열린 터미널/VS Code 재시작 후 적용.
param(
    [Parameter(Mandatory = $true)]
    [string]$CentralHost,
    [string]$Member = ""
)

if (-not $Member) { $Member = $env:USERNAME.ToLower() }

$vars = [ordered]@{
    "CLAUDE_CODE_ENABLE_TELEMETRY" = "1"
    "OTEL_METRICS_EXPORTER"        = "otlp"
    "OTEL_LOGS_EXPORTER"           = "otlp"
    "OTEL_EXPORTER_OTLP_PROTOCOL"  = "grpc"
    "OTEL_EXPORTER_OTLP_ENDPOINT"  = "http://${CentralHost}:4317"
    "OTEL_RESOURCE_ATTRIBUTES"     = "host.name=$($env:COMPUTERNAME.ToLower()),os.user=$($env:USERNAME.ToLower()),member=$Member"
}

foreach ($kv in $vars.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "User")
    Write-Host "set $($kv.Key)=$($kv.Value)"
}

Write-Host ""
Write-Host "설치 완료 (CENTRAL_HOST=$CentralHost, member=$Member)."
Write-Host "열려 있는 터미널/VS Code를 재시작해야 적용됩니다."
