---
name: file-tools
description: Package generated files into a zip archive or list recent files in a directory when the user needs deterministic local file handling.
---

# File Tools

Use this skill for short local file packaging and inspection tasks.

## Pack files into a zip

```powershell
powershell -File ".\skills\File_Tools\Pack-Files.ps1" -Path ".\archives\report.pdf",".\archives\chart.png"
```

Optional custom output path:

```powershell
powershell -File ".\skills\File_Tools\Pack-Files.ps1" -Path ".\archives\*" -OutputPath ".\archives\bundle.zip" -Overwrite
```

## List recent files

```powershell
powershell -File ".\skills\File_Tools\List-RecentFiles.ps1"
```

List recent PDF files only:

```powershell
powershell -File ".\skills\File_Tools\List-RecentFiles.ps1" -Directory ".\archives" -Filter "*.pdf" -Top 5
```

## Notes

- Default output locations stay inside `archives/`.
- Prefer this skill for direct packaging or file listing. Escalate to OpenCode for workflows that need classification, transformation, or validation across many files.
