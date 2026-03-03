<#
.SYNOPSIS
    Queries WorkIQ for client activity reports and saves results as Markdown files.

.DESCRIPTION
    Reads a client list from clients.csv (Name, AKA columns), queries WorkIQ for
    each client's activities during a specified time period, and saves the output
    to reports/{from}-{to}/{ClientName}.md.

.PARAMETER TimePeriod
    Optional. "last week" or "last month". If omitted, an interactive menu is shown.
    Mutually exclusive with -From/-To.

.PARAMETER From
    Optional. Start date (yyyy-MM-dd) for a custom date range. Must be used with -To.
    Mutually exclusive with -TimePeriod.

.PARAMETER To
    Optional. End date (yyyy-MM-dd) for a custom date range. Must be used with -From.
    Mutually exclusive with -TimePeriod.

.PARAMETER ClientsFile
    Optional. Path to the CSV file. Defaults to clients.csv in the script directory.

.PARAMETER KeepLog
    Optional switch. When specified, saves a transcript log to logs/ with a timestamp filename.

.EXAMPLE
    .\Generate-Insights.ps1 -TimePeriod "last week"
    .\Generate-Insights.ps1 -From 2026-01-15 -To 2026-01-31
    .\Generate-Insights.ps1 -TimePeriod "last month" -KeepLog
    .\Generate-Insights.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TimePeriod,

    [Parameter()]
    [string]$From,

    [Parameter()]
    [string]$To,

    [Parameter()]
    [string]$ClientsFile,

    [Parameter()]
    [switch]$KeepLog
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# --- Start logging if requested ---
if ($KeepLog) {
    $logDir = Join-Path $scriptDir "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logFile = Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    Start-Transcript -Path $logFile | Out-Null
}

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

# --- Validate parameter combinations ---
if ($TimePeriod -and ($From -or $To)) {
    Write-Error "-TimePeriod cannot be used together with -From/-To. Use one or the other."
    exit 1
}
if (($From -and -not $To) -or ($To -and -not $From)) {
    Write-Error "Both -From and -To must be specified together."
    exit 1
}

# --- Time period selection ---
if ($From -and $To) {
    # Custom date range provided via parameters
    $fromDate = [datetime]::ParseExact($From, "yyyy-MM-dd", $null)
    $toDate   = [datetime]::ParseExact($To,   "yyyy-MM-dd", $null)
    if ($fromDate -gt $toDate) {
        Write-Error "-From ($From) must be on or before -To ($To)."
        exit 1
    }
    $TimePeriod = "custom"
} elseif (-not $TimePeriod) {
    Write-Host ""
    Write-Host "Select a time period:"
    Write-Host "  1) Last Week"
    Write-Host "  2) Last Month"
    Write-Host "  3) Custom Range"
    Write-Host ""
    $choice = Read-Host "Enter choice (1, 2, or 3)"
    switch ($choice) {
        "1" { $TimePeriod = "last week" }
        "2" { $TimePeriod = "last month" }
        "3" {
            $fromInput = Read-Host "Enter start date (yyyy-MM-dd)"
            $toInput   = Read-Host "Enter end date   (yyyy-MM-dd)"
            $fromDate = [datetime]::ParseExact($fromInput, "yyyy-MM-dd", $null)
            $toDate   = [datetime]::ParseExact($toInput,   "yyyy-MM-dd", $null)
            if ($fromDate -gt $toDate) {
                Write-Error "Start date ($fromInput) must be on or before end date ($toInput)."
                exit 1
            }
            $TimePeriod = "custom"
        }
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
        $fromDate = $thisMonday.AddDays(-7)
        $toDate = $thisMonday.AddDays(-1)
    }
    "last month" {
        $firstOfThisMonth = Get-Date -Year $today.Year -Month $today.Month -Day 1
        $fromDate = $firstOfThisMonth.AddMonths(-1)
        $toDate = $firstOfThisMonth.AddDays(-1)
    }
    "custom" {
        # $fromDate and $toDate already set from parameter parsing above
    }
    default {
        Write-Error "Unsupported time period: '$TimePeriod'. Use 'last week', 'last month', or -From/-To for a custom range."
        exit 1
    }
}

$fromStr = $fromDate.ToString("yyyyMMdd")
$toStr = $toDate.ToString("yyyyMMdd")
$reportDir = Join-Path (Join-Path $scriptDir "reports") "$fromStr-$toStr"
$periodLabel = if ($TimePeriod -eq "custom") { "$fromStr - $toStr" } else { "$TimePeriod ($fromStr - $toStr)" }

Write-Host ""
Write-Host "Time period : $periodLabel"
Write-Host "Report folder: $reportDir"
Write-Host ""

# --- Create output directory ---
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

# --- Load prompt template ---
$promptFile = Join-Path (Join-Path $scriptDir "prompts") "client-insights.md"
if (-not (Test-Path $promptFile)) {
    Write-Error "Prompt template not found: $promptFile"
    exit 1
}
$promptTemplate = Get-Content $promptFile -Raw

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

    # Build prompt from template
    if ($aka) {
        $clientLabel = "$name (also known as $aka)"
    } else {
        $clientLabel = $name
    }
    $prompt = $promptTemplate -replace '\{\{CLIENT\}\}', $clientLabel -replace '\{\{FROM\}\}', $fromDate.ToString("yyyy-MMM-dd") -replace '\{\{TO\}\}', $toDate.ToString("yyyy-MMM-dd")

    $safeName = $name -replace '\s+', '-'
    $outFile = Join-Path $reportDir "$safeName.md"
    Write-Host "[$name] Querying WorkIQ..." -NoNewline

    try {
        $result = & workiq ask --question $prompt 2>&1
        $resultText = $result -join "`n"

        # Write markdown file
        $header = "# $name - Activity Report`n"
        $header += "**Period:** $periodLabel`n"
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

# --- Internal insights (single run, no client substitution) ---
$internalPromptFile = Join-Path (Join-Path $scriptDir "prompts") "internal-insights.md"
if (Test-Path $internalPromptFile) {
    $internalPrompt = (Get-Content $internalPromptFile -Raw) -replace '\{\{FROM\}\}', $fromDate.ToString("yyyy-MMM-dd") -replace '\{\{TO\}\}', $toDate.ToString("yyyy-MMM-dd")
    $internalOutFile = Join-Path $reportDir "Internal.md"
    Write-Host "[Internal] Querying WorkIQ..." -NoNewline

    try {
        $result = & workiq ask --question $internalPrompt 2>&1
        $resultText = $result -join "`n"

        $header = "# Internal - Activity Report`n"
        $header += "**Period:** $periodLabel`n"
        $header += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
        $header += "`n---`n`n"

        Set-Content -Path $internalOutFile -Value ($header + $resultText) -Encoding UTF8
        Write-Host " Done -> $internalOutFile"
        $successes += "Internal"
    }
    catch {
        Write-Host " FAILED: $_" -ForegroundColor Red
        $failures += "Internal"
    }
} else {
    Write-Host "[Internal] Skipped - prompt not found: $internalPromptFile" -ForegroundColor Yellow
}

# --- Summarize all reports ---
$summarizePromptFile = Join-Path (Join-Path $scriptDir "prompts") "summarize.md"
if (Test-Path $summarizePromptFile) {
    $summarizePrompt = (Get-Content $summarizePromptFile -Raw) -replace '\{\{REPORT_FOLDER\}\}', $reportDir
    $summarizeOutFile = Join-Path $reportDir "Summary.md"
    $fullPrompt = "$summarizePrompt`n`nOutput the full summary as Markdown to stdout. Do not write any files."
    Write-Host "[Summary] Running Copilot summarization..." -NoNewline

    try {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $copilotOutput = & copilot -p $fullPrompt --allow-tool read_file --allow-all-paths 2>&1
        $ErrorActionPreference = $prevEAP

        # Extract only the markdown content: from the first heading/separator to before the session stats footer
        $allOutput = $copilotOutput -join "`n"
        $mdMatch = [regex]::Match($allOutput, '(?s)(^#{1,6} |^---\s*\n)(.*?)(?=\nTotal usage est:|\nSystem\.Management|$)')
        $summaryText = if ($mdMatch.Success) { $mdMatch.Value.Trim() } else { "" }

        if ($summaryText.Trim()) {
            $header = "# Summary - Activity Report`n"
            $header += "**Period:** $periodLabel`n"
            $header += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n"
            $header += "`n---`n`n"
            Set-Content -Path $summarizeOutFile -Value ($header + $summaryText.Trim()) -Encoding UTF8
            Write-Host " Done -> $summarizeOutFile"
            $successes += "Summary"
        } else {
            Write-Host " FAILED: Copilot returned no output" -ForegroundColor Red
            if ($copilotOutput) { Write-Host ($copilotOutput -join "`n") -ForegroundColor Yellow }
            $failures += "Summary"
        }
    }
    catch {
        Write-Host " FAILED: $_" -ForegroundColor Red
        $failures += "Summary"
    }
} else {
    Write-Host "[Summary] Skipped - prompt not found: $summarizePromptFile" -ForegroundColor Yellow
}

# --- Summary ---
Write-Host ""
Write-Host "=== Summary ==="
Write-Host "Successes: $($successes.Count) / $($clients.Count + 1)"
if ($failures.Count -gt 0) {
    Write-Host "Failures : $($failures -join ', ')" -ForegroundColor Red
}
Write-Host "Reports  : $reportDir"

# --- Update reports index ---
$indexScript = Join-Path $scriptDir "Update-ReportsIndex.ps1"
if (Test-Path $indexScript) {
    Write-Host ""
    Write-Host "Updating reports index..."
    & $indexScript
} else {
    Write-Host "Update-ReportsIndex.ps1 not found, skipping index update." -ForegroundColor Yellow
}

# --- Stop logging ---
if ($KeepLog) {
    Stop-Transcript | Out-Null
    Write-Host "Log saved   : $logFile"
}
