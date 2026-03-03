# Reports Index Generator
# Scans the reports/ folder and generates reports/index.json
# Run this after adding new report folders or files.

$reportsPath = Join-Path $PSScriptRoot "reports"
$reports = @{}

Get-ChildItem -Path $reportsPath -Directory | ForEach-Object {
    $period = $_.Name
    $files = Get-ChildItem -Path $_.FullName -Filter "*.md" | ForEach-Object { $_.Name }
    if ($files.Count -gt 0) {
        $reports[$period] = @($files)
    }
}

$json = $reports | ConvertTo-Json -Depth 3
$indexPath = Join-Path $reportsPath "index.json"
[System.IO.File]::WriteAllText($indexPath, $json, [System.Text.UTF8Encoding]::new($false))

$total = ($reports.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
Write-Host "Updated $indexPath - $($reports.Count) period(s), $total report(s)"
