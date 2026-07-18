# Security Policy

## Supported Versions

This repository is a collection of independent PowerShell scripts, each versioned separately (see the `CHANGELOG.md` inside each script's own folder). Only the **latest tagged release of each individual script** is supported with security fixes. If you're running an older version of a script, please update to the latest tag before reporting an issue, in case it's already been addressed.

| Component | Supported |
|---|---|
| Latest tagged release of each script (e.g. `filesigning-v1.x.x`) | :white_check_mark: |
| Older tagged releases of a script | :x: |
| `main` branch (unreleased changes) | Best effort, not guaranteed stable |

## Reporting a Vulnerability

**Please do not open a public issue for a security vulnerability.** Publicly disclosing a vulnerability before a fix is available could put anyone currently using the affected script at risk.

Instead, please report it privately using one of the following:

- **GitHub's private vulnerability reporting** for this repository: go to the **Security** tab → **Report a vulnerability**. This creates a private advisory visible only to the maintainer until it's resolved, and is the preferred method.
- Alternatively, see the reporting contact listed in this repository's [Code of Conduct](./CODE_OF_CONDUCT.md).

When reporting, please include:

- The affected script name and version (or commit hash).
- A description of the vulnerability and its potential impact, for example, whether it could lead to privilege escalation, credential exposure, arbitrary code execution, or unintended changes to a target system.
- Steps to reproduce, or a proof of concept, if you have one.
- Any suggested remediation, if you have one, though this isn't required.

## What Counts as a Security Issue Here

Given the nature of this repository (PowerShell scripts intended for infrastructure and system administration use, some with elevated privilege requirements), examples of what should be reported privately include:

- A flaw that could allow a script to be tricked into running unintended or attacker-controlled code.
- Insecure handling of credentials, certificates, or private keys (e.g. a certificate or secret being logged, written to a world-readable location, or transmitted insecurely).
- A logic flaw that could cause a script to silently disable a security control (for example, weakening certificate trust validation, or bypassing an intended policy check) without clearly logging that it has done so.
- Any path by which a script could be induced to escalate privileges beyond what it was invoked with.

General bugs, incorrect behaviour, or missing functionality that don't have security implications should be reported as normal, public issues instead, see [`CONTRIBUTING.md`](./CONTRIBUTING.md).

## Response Expectations

This is a personal, single-maintainer project maintained outside of full-time work. I'll aim to acknowledge a report within a reasonable timeframe and keep you updated as an investigation progresses, but please understand response times may vary. If a report is confirmed as a genuine vulnerability, a fix will be prioritised and a new tagged release published, with credit given to the reporter in the release notes if they'd like it (and not if they'd rather remain anonymous, just let me know your preference when reporting).

## Disclosure

Once a fix is released, I'll publish a GitHub Security Advisory for the affected script summarising the issue and the fix, following [coordinated disclosure](https://docs.github.com/en/code-security/concepts/vulnerability-reporting-and-management/coordinated-disclosure) practice, giving users time to update before full technical details are made public.
