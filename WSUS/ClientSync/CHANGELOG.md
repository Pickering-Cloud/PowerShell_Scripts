\# Changelog



All notable changes to this script are documented here.



The format follows \[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and version numbers follow \[Semantic Versioning](https://semver.org/).



\## \[1.0.0] - Initial release



\### Added

\- Initial release.

\- Read-only-protected log file with configurable level (Debug through Critical, or None), interactive prompt for local sessions, automatic Info default for remote/unattended sessions.

\- Application Event Log integration under source "WSUS Client Sync Script", with a documented, unique event ID per condition (see README).

\- Collection of the currently configured WSUS server/status server from Group Policy, with a forced `gpupdate` and re-check for policy drift.

\- Configuration testing: DNS resolution, network reachability (ping and port), and HTTPS certificate trust validation (skipped cleanly if WSUS isn't using SSL).

\- Prerequisite checks: pending reboot (component servicing, Windows Update, pending rename, SCCM client), free disk space on the system drive, and disabled/stopped prerequisite services.

\- Synchronisation attempts via Windows Update Agent COM API, `UsoClient`, and legacy `wuauclt`, with configurable retry count and success detection via `LastSuccessTime`.

\- Update history review, scoped to errors that occurred since the script started, avoiding stale historical noise.

\- `-AutomaticallyRemediate` switch enabling automatic fixes for recognised error codes, using a shared library of idempotent repair actions (SFC, DISM, SoftwareDistribution/catroot2 reset, BITS queue reset with file-level fallback).

\- Deliberate non-remediation of policy-managed misconfigurations (malformed WSUS URL, Windows Update disabled by policy), logged with guidance rather than auto-corrected.

\- Post-remediation synchronisation retry, gated to only run when the initial attempt failed and remediation was actually attempted.

