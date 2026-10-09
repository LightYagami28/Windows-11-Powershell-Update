# Security

`Update-Windows11.ps1` requires administrator privileges and can change Windows Update services, caches, packages and system state. Review the source and run `-WhatIf` first from an elevated PowerShell session. Preview writes logs/transcript files but does not install modules or winget, alter services, clear caches, or apply updates. Never pipe unreviewed remote code to `Invoke-Expression`.

`updatew11.ps1` is an unsafe legacy script kept in the repository for provenance only. It elevates with `ExecutionPolicy Bypass`, stops services, deletes the Windows Update download cache, installs software and may auto-reboot; it has no preview/confirmation contract. Do not execute it.

Report vulnerabilities privately to the repository maintainer and do not
include real logs, tokens or machine identifiers in public issues.
