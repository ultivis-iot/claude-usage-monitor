# Claude Code 텔레메트리 클라이언트 설치 (Windows)
#
# 원라이너 (PowerShell):
#   [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
#   $s = irm '<RAW_URL>/client/install-client.ps1'
#   & ([scriptblock]::Create($s)) -CentralHost <중앙서버IP> -Member kim
#
# 사용자 레벨 환경변수로 등록되므로 관리자 권한 불필요.
# 이 세션에는 즉시 반영되고, 새로 여는 터미널/VS Code에도 자동 적용됨.
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
    Set-Item -Path "Env:$($kv.Key)" -Value $kv.Value
    Write-Host "set $($kv.Key)=$($kv.Value)"
}

Write-Host ""
Write-Host "설치 완료 (CENTRAL_HOST=$CentralHost, member=$Member)."
Write-Host "이 창은 지금 바로 사용 가능하고, 새로 여는 터미널/VS Code에도 자동 적용됩니다."

Write-Host ""
Write-Host "중앙 서버(${CentralHost}:4317) 연결 확인 중..."
$conn = Test-NetConnection -ComputerName $CentralHost -Port 4317 -WarningAction SilentlyContinue
if ($conn.TcpTestSucceeded) {
    Write-Host "OK: ${CentralHost}:4317 연결 가능."
} else {
    Write-Host "경고: ${CentralHost}:4317 에 연결할 수 없습니다. 방화벽/VPN/사내망 분리를 확인하세요."
    Write-Host "      이 상태로는 텔레메트리가 서버에 도달하지 못해 Grafana에도 데이터가 표시되지 않습니다."
}
