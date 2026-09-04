# Claude Code 텔레메트리 클라이언트 제거 (Windows)
#
# install-client.ps1 / claude-otel-setup.ps1 로 설정한 사용자 레벨 환경변수를 모두 삭제한다.
#
# 원라이너 (PowerShell):
#   $s = irm '<RAW_URL>/client/uninstall-client.ps1'
#   & ([scriptblock]::Create($s))
#
# 또는 파일로 저장 후:
#   powershell -ExecutionPolicy Bypass -File .\uninstall-client.ps1

$names = @(
    "CLAUDE_CODE_ENABLE_TELEMETRY",
    "OTEL_METRICS_EXPORTER",
    "OTEL_LOGS_EXPORTER",
    "OTEL_EXPORTER_OTLP_PROTOCOL",
    "OTEL_EXPORTER_OTLP_ENDPOINT",
    "OTEL_RESOURCE_ATTRIBUTES"
)

foreach ($name in $names) {
    [Environment]::SetEnvironmentVariable($name, $null, "User")
    if (Test-Path "Env:$name") { Remove-Item "Env:$name" }
    Write-Host "removed $name"
}

Write-Host ""
Write-Host "제거 완료. 이 창에는 바로 반영되고, 새로 여는 터미널/VS Code에도 적용됩니다."
