# Local development only. Production uses Laravel's hourly scheduled command.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$phpPath = (Get-Command php -CommandType Application -ErrorAction Stop).Source
$artisanPath = Join-Path $projectRoot 'artisan'
$logPath = Join-Path $projectRoot 'storage/logs/premium-expiry-worker.log'
$pidPath = Join-Path $projectRoot 'storage/app/private/premium-expiry-worker.pid'
$hash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($projectRoot))).Replace('-', '')
$mutex = [System.Threading.Mutex]::new($false, "Local\FarmSpotPremiumExpiry-$hash")
$acquired = $false
try {
    try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) { exit 0 }
    Set-Content -LiteralPath $pidPath -Value $PID
    while ($true) {
        try {
            $result = & $phpPath $artisanPath premium:notify-expiry 2>&1
            if ($LASTEXITCODE -ne 0) {
                Add-Content -LiteralPath $logPath -Value ("{0:o} {1}" -f [DateTime]::UtcNow, ($result -join ' '))
            }
        } catch {
            Add-Content -LiteralPath $logPath -Value ("{0:o} Worker error: {1}" -f [DateTime]::UtcNow, $_.Exception.Message)
        }
        Start-Sleep -Seconds 3600
    }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
