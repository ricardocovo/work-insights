# work-insights

A personal productivity tool that queries your Microsoft 365 activity via the **WorkIQ CLI** and generates Markdown reports for each client — plus internal and summary reports — then lets you browse them in a local web viewer.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Report generation | PowerShell 7+ |
| AI querying (client & internal) | [WorkIQ CLI](https://www.npmjs.com/package/@microsoft/workiq) (`workiq`) |
| AI querying (summary) | [GitHub Copilot CLI](https://docs.github.com/en/copilot/github-copilot-in-the-cli) (`copilot`) |
| Markdown rendering | [Marked.js](https://marked.js.org/) (CDN) |
| Report viewer | Vanilla HTML / CSS / JavaScript |
| Report index | JSON (`reports/index.json`) |

---

## Prerequisites

- **PowerShell 7+** — `pwsh` on PATH
- **Node.js** — to install the WorkIQ CLI
- **WorkIQ CLI** — install once globally:

  ```powershell
  npm install -g @microsoft/workiq
  ```

- **GitHub Copilot CLI** — required for the Summary report:

  ```powershell
  npm install -g @githubnext/github-copilot-cli
  ```

  Authenticate with `github-copilot-cli auth` if prompted on first run.

- A `clients.csv` file in the repo root (see [Setup](#setup))

---

## Setup

1. Clone or download this repository.

2. Copy the sample clients file and fill it in:

   ```powershell
   Copy-Item clients.sample.csv clients.csv
   ```

3. Edit `clients.csv` — one row per client you want reports for:

   ```csv
   Name,AKA
   Contoso,
   Fabrikam,Fab
   ```

   - **Name** — used as the report filename and heading.
   - **AKA** — optional alias passed to WorkIQ to improve activity matching.

---

## Running Reports

Run the main script from the repo root:

```powershell
# Interactive — choose Last Week, Last Month, or Custom Range from a menu
.\Generate-Insights.ps1

# Non-interactive — predefined periods
.\Generate-Insights.ps1 -TimePeriod "last week"
.\Generate-Insights.ps1 -TimePeriod "last month"

# Non-interactive — custom date range
.\Generate-Insights.ps1 -From 2026-01-15 -To 2026-01-31

# Keep a log of the run
.\Generate-Insights.ps1 -TimePeriod "last week" -KeepLog

# Use a different clients file
.\Generate-Insights.ps1 -TimePeriod "last week" -ClientsFile ".\my-other-clients.csv"
```

The script will:

1. Query **WorkIQ** for each client in `clients.csv` using `prompts/client-insights.md`.
2. Query **WorkIQ** for an **Internal** report using `prompts/internal-insights.md` (non-client time analysis).
3. Query **GitHub Copilot CLI** for an overall **Summary** using `prompts/summarize.md` — this synthesizes all reports in the output folder.
4. Save all reports to `reports/{from}-{to}/` as Markdown files.
5. Automatically run `Update-ReportsIndex.ps1` to rebuild `reports/index.json`.

---

## Visualizing Reports

Open `reportviewer/index.html` in any modern browser. The easiest way is with the **Live Server** extension in VS Code:

1. Right-click `reportviewer/index.html` in the Explorer and choose **Open with Live Server**.
2. Or open it directly in a browser:

   ```powershell
   start reportviewer/index.html
   ```

> **Note:** The index is updated automatically at the end of each `Generate-Insights.ps1` run. If you manually add or remove report files, run `Update-ReportsIndex.ps1` to rebuild it.

The viewer lets you:

- Browse reports grouped by time period in the sidebar, newest first.
- Read each Markdown report rendered as formatted HTML.
- Navigate with keyboard: `↑` / `↓` or `j` / `k` to move between reports.
- Deep-link to any report via the URL hash (e.g. `index.html#20260223-20260301/BMO.md`).

---

## Project Structure

```
work-insights/
├── clients.csv               # Your client list (gitignored)
├── clients.sample.csv        # Template — copy to clients.csv
├── Generate-Insights.ps1     # Main report generation script
├── Update-ReportsIndex.ps1   # Regenerates reports/index.json (auto-called by Generate-Insights.ps1)
├── logs/                     # Transcript logs (created with -KeepLog, gitignored)
├── prompts/
│   ├── client-insights.md    # Prompt template for client reports
│   ├── internal-insights.md  # Prompt for non-client time analysis
│   └── summarize.md          # Prompt for the weekly/monthly summary
├── reports/
│   ├── index.json            # Auto-generated — do not edit manually
│   └── {from}-{to}/          # One folder per reporting period
│       ├── ClientName.md
│       ├── Internal.md
│       └── Summary.md
└── reportviewer/
    ├── index.html            # Report browser UI
    ├── app.js                # Navigation, fetching, and rendering logic
    └── styles.css            # Styling
```

---

## Prompt Templates

Prompt files in `prompts/` use `{{PLACEHOLDER}}` tokens substituted at runtime:

| Placeholder | Description |
|---|---|
| `{{CLIENT}}` | Client name and alias (client reports only) |
| `{{FROM}}` | Period start date (`yyyy-MMM-dd`) |
| `{{TO}}` | Period end date (`yyyy-MMM-dd`) |
| `{{REPORT_FOLDER}}` | Absolute path to the output folder (Summary only) |

To change what WorkIQ is asked, edit the relevant file in `prompts/`.

---

## Contributing

- Keep prompt templates focused and outcome-oriented.
- The report viewer has no build step — keep it dependency-free.
- `clients.csv` is gitignored — never commit real client names.