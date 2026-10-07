# Security

This script requires administrator privileges and changes Windows Update
services, caches, packages and potentially system state. Review the source,
run `-WhatIf` first, create a restore point, and execute only from a trusted
copy. Never pipe an unreviewed remote script directly to `Invoke-Expression`.

Report vulnerabilities privately to the repository maintainer and do not
include real logs, tokens or machine identifiers in public issues.
