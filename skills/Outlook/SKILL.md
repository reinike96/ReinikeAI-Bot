# Outlook Automation Skill

PowerShell scripts to manage Microsoft Outlook accounts, including reading, searching, sending, and deleting emails.

## Files

- `check-outlook-emails.ps1`: Basic reader for recent emails.
- `search-outlook-emails.ps1`: Advanced search with body preview.
- `send-outlook-email.ps1`: Compose and send emails.
- `delete-emails.ps1`: Filtered deletion of emails.
- `list-folders.ps1`: List all Outlook folders and accounts.

## Requirements

- **Microsoft Outlook Desktop** installed and configured.
- **PowerShell 5.1+**.
- Outlook must be open or accessible via COM.

---

## 1. Reading Emails (`check-outlook-emails.ps1`)

Used for quick checks of today's or recent emails.

```powershell
# Basic check (today)
[CMD: powershell -File ".\skills\Outlook\check-outlook-emails.ps1"]

# Check with body extraction and sync
[CMD: powershell -File ".\skills\Outlook\check-outlook-emails.ps1" -IncludeBody -Sync]

# Output as JSON for processing
[CMD: powershell -File ".\skills\Outlook\check-outlook-emails.ps1" -JSON]
```

## 2. Searching Emails (`search-outlook-emails.ps1`) [NEW]

Flexible search across accounts.

```powershell
# Search by keyword in subject/body
[CMD: powershell -File ".\skills\Outlook\search-outlook-emails.ps1" -Query "factura"]

# Search by sender and days back
[CMD: powershell -File ".\skills\Outlook\search-outlook-emails.ps1" -Sender "Amazon" -DaysBack 30]

# Search only unread
[CMD: powershell -File ".\skills\Outlook\search-outlook-emails.ps1" -UnreadOnly]
```

## 3. Sending Emails (`send-outlook-email.ps1`) [NEW]

Send emails via a specific account or the default one.

```powershell
# Send a simple text email
[CMD: powershell -File ".\skills\Outlook\send-outlook-email.ps1" -To "dest@example.com" -Subject "Reporte" -Body "Adjunto resultados."]

# Send with attachments and HTML body
[CMD: powershell -File ".\skills\Outlook\send-outlook-email.ps1" -To "boss@company.com" -Subject "Resumen" -Body "<h1>Hola</h1><p>Todo listo.</p>" -Attachments "C:\docs\reporte.pdf"]
```

## 4. Deleting Emails (`delete-emails.ps1`)

Delete emails matching specific criteria. **Use with caution.**

```powershell
# Delete by sender (WhatIf mode first recommended)
[CMD: powershell -File ".\skills\Outlook\delete-emails.ps1" -Sender "newsletter@spam.com" -WhatIf]

# Delete emails with specific keywords in the last 7 days
[CMD: powershell -File ".\skills\Outlook\delete-emails.ps1" -Keywords "oferta,descuento" -DaysBack 7]
```

---

## Important Rules for Orchestrator

1. **Wait for Results**: Outlook operations via COM can take a few seconds. Do not chain multiple Outlook commands in the same turn if they depend on each other.
2. **Sync**: If the user says "I just sent it" or "Why isn't it there?", use the `-Sync` parameter in `check-outlook-emails.ps1`.
3. **Paths**: Always use absolute paths for attachments in `send-outlook-email.ps1`.
4. **JSON**: If you need to perform complex logic (like "find the email from X and then reply to it"), use the `-JSON` flag to get data in a machine-readable format.