<#
.SYNOPSIS
    Queries WorkIQ for client activity reports and saves results as Markdown files.

.DESCRIPTION
    Reads a client list from clients.csv (Name, AKA columns), queries WorkIQ for
    each client's activities during a specified time period, and saves the output
    to reports/{from}-{to}/{ClientName}.md.

.PARAMETER TimePeriod
    Optional. "last week" or "last month". If omitted, an interactive menu is shown.

.PARAMETER ClientsFile
    Optional. Path to the CSV file. Defaults to clients.csv in the script directory.

.EXAMPLE
    .\Get-ClientInsights.ps1 -TimePeriod "last week"
    .\Get-ClientInsights.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TimePeriod,

    [Parameter()]
    [string]$ClientsFile
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# --- Pre-flight: check workiq is available ---
if (-not (Get-Command workiq -ErrorAction SilentlyContinue)) {
    Write-Error "workiq CLI not found on PATH. Install it with: npm install -g @microsoft/workiq"
    exit 1
}

# --- Resolve clients file ---
if (-not $ClientsFile) {
    $ClientsFile = Join-Path $scriptDir "clients.csv"
}
if (-not (Test-Path $ClientsFile)) {
    Write-Error "Clients file not found: $ClientsFile"
    exit 1
}

# --- Time period selection ---
if (-not $TimePeriod) {
    Write-Host ""
    Write-Host "Select a time period:"
    Write-Host "  1) Last Week"
    Write-Host "  2) Last Month"
    Write-Host ""
    $choice = Read-Host "Enter choice (1 or 2)"
    switch ($choice) {
        "1" { $TimePeriod = "last week" }
        "2" { $TimePeriod = "last month" }
        default {
            Write-Error "Invalid choice: $choice"
            exit 1
        }
    }
}

# --- Calculate date range for folder name ---
$today = Get-Date

switch ($TimePeriod.ToLower()) {
    "last week" {
        $daysSinceMonday = ([int]$today.DayOfWeek + 6) % 7  # Monday = 0
        $thisMonday = $today.AddDays(-$daysSinceMonday)
        $from = $thisMonday.AddDays(-7)
        $to = $thisMonday.AddDays(-1)
    }
    "last month" {
        $firstOfThisMonth = Get-Date -Year $today.Year -Month $today.Month -Day 1
        $from = $firstOfThisMonth.AddMonths(-1)
        $to = $firstOfThisMonth.AddDays(-1)
    }
    default {
        Write-Error "Unsupported time period: '$TimePeriod'. Use 'last week' or 'last month'."
        exit 1
    }
}

$fromStr = $from.ToString("yyyyMMdd")
$toStr = $to.ToString("yyyyMMdd")
$reportDir = Join-Path (Join-Path $scriptDir "reports") "$fromStr-$toStr"

Write-Host ""
Write-Host "Time period : $TimePeriod ($fromStr - $toStr)"
Write-Host "Report folder: $reportDir"
Write-Host ""

# --- Create output directory ---
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

# --- Read clients ---
$clients = Import-Csv $ClientsFile
if ($clients.Count -eq 0) {
    Write-Error "No clients found in $ClientsFile"
    exit 1
}

Write-Host "Found $($clients.Count) client(s) to process."
Write-Host ""

# --- Process each client ---
$successes = @()
$failures = @()

foreach ($client in $clients) {
    $name = $client.Name.Trim()
    $aka = if ($client.AKA) { $client.AKA.Trim() } else { "" }

    if (-not $name) { continue }

    # Build prompt
    if ($aka) {
        $prompt = "What are the main $name (also known as $aka) activities I had on for $TimePeriod"
    } else {
        $prompt = "What are the main $name activities I had on for $TimePeriod"
    }

    $outFile = Join-Path $reportDir "$name.md"
    Write-Host "[$name] Querying WorkIQ..." -NoNewline

    try {
        $result = & workiq ask --question $prompt 2>&1
        $resultText = $result -join "`n"

        # Write markdown file
        $header = "# $name - Activity Report`n"
        $header += "**Period:** $TimePeriod ($fromStr - $toStr)`n"
        if ($aka) { $header += "**Also known as:** $aka`n" }
        $header += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
        $header += "`n---`n`n"

        $content = $header + $resultText
        Set-Content -Path $outFile -Value $content -Encoding UTF8

        Write-Host " Done -> $outFile"
        $successes += $name
    }
    catch {
        Write-Host " FAILED: $_" -ForegroundColor Red
        $failures += $name
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Successes: $($successes.Count) / $($clients.Count)"
if ($failures.Count -gt 0) {
    Write-Host "Failures : $($failures -join ', ')" -ForegroundColor Red
}
Write-Host "Reports  : $reportDir"
