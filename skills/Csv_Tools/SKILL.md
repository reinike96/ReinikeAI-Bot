---
name: csv-tools
description: Inspect local CSV files to summarize schema, row counts, missing values, and sample rows without needing OpenCode.
---

# CSV Tools

Use this skill for quick deterministic inspection of CSV files.

## Inspect a CSV file

```powershell
powershell -File ".\skills\Csv_Tools\Inspect-Csv.ps1" -Path ".\archives\data.csv"
```

Choose a larger sample:

```powershell
powershell -File ".\skills\Csv_Tools\Inspect-Csv.ps1" -Path ".\archives\data.csv" -SampleRows 10
```

## Notes

- The output is JSON.
- Use this to understand a dataset quickly before summarizing it.
- Escalate to OpenCode when the user needs transformations, joins, charting, or multi-step analysis.
