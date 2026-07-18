# Contributing

Thanks for your interest in contributing. This is primarily a personal collection of PowerShell tooling, but issues and pull requests are genuinely welcome, whether that's a bug report, a suggestion, or a new script entirely.

By participating in this project, you agree to abide by the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Before you start

For anything non-trivial, especially a new script or a significant change to an existing one, please open an issue first to discuss the approach before submitting a pull request. This saves everyone time if the idea needs adjusting, or if something similar is already planned.

Small fixes (typos, broken links, a genuine bug with an obvious correct fix) don't need an issue first, a pull request on its own is fine.

## Repository structure

Each script lives in its own subfolder with its own `README.md` and `CHANGELOG.md`. If you're adding a new script, please follow the same pattern:

```
<ScriptName>/
├── <ScriptName>.ps1
├── README.md
├── CHANGELOG.md
└── <ScriptName>.example.json   (if the script uses a config file)
```

See an existing script folder for the expected shape of each file.

## Coding standards

- Use Microsoft's [approved verbs](https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands) for all function names.
- Every function needs comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` for each parameter, `.OUTPUTS`, and at least one `.EXAMPLE`).
- Use `[CmdletBinding()]` on functions and scripts, and `SupportsShouldProcess` on anything that changes system state, so `-WhatIf`/`-Confirm` work correctly.
- Explicit parameter types throughout, avoid untyped parameters where a real type applies.
- Wrap operations that can fail (registry access, service control, network calls, file operations) in `try`/`catch`, and log or report failures clearly rather than letting them fail silently.
- Match the logging/error-handling patterns already used in the script you're editing, consistency matters more than personal preference here.
- Run [`PSScriptAnalyzer`](https://github.com/PowerShell/PSScriptAnalyzer) against your changes before opening a pull request, and resolve anything it flags:
  ```powershell
  Install-Module -Name PSScriptAnalyzer -Scope CurrentUser
  Invoke-ScriptAnalyzer -Path .\YourScript.ps1
  ```

## Testing

Not every script in this repo can be fully tested by the maintainer alone (some require enterprise infrastructure like ADCS or WSUS that isn't always available in a personal environment). If you're able to test a change against real infrastructure that the maintainer can't access, please say so in your pull request description, this is genuinely valuable and will speed up review considerably.

If a script can't be fully tested end-to-end, please note clearly in the pull request which parts are verified and which aren't, consistent with how untested sections are already flagged in this repo's existing scripts and READMEs.

## Versioning and releases

Each script has its own `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) conventions and [Semantic Versioning](https://semver.org/). If your change is significant enough to warrant a version bump (anything beyond a typo fix), please add an entry to the relevant script's changelog under an `[Unreleased]` heading, describing what changed.

Releases are tagged per script using the pattern `<scriptname>-v<semver>` (e.g. `filesigning-v1.0.1`), since GitHub tags and releases are repository-wide rather than folder-scoped. Tagging and publishing releases is handled by the maintainer.

## Submitting a pull request

1. Fork the repository and create a branch from `main`.
2. Make your changes, following the structure and standards above.
3. Update the relevant script's `README.md` and `CHANGELOG.md` if your change affects usage, parameters, or behaviour.
4. Confirm `Invoke-ScriptAnalyzer` runs clean against anything you've changed.
5. Open a pull request with a clear description of what changed and why, and note any testing you were able to perform (see **Testing** above).

## Reporting bugs or requesting features

Please open an issue and include:

- The script name and version (or commit) you're using.
- What you expected to happen, and what actually happened.
- Relevant log output, if applicable, with anything sensitive (hostnames, internal server names, credentials) redacted first.
- Your PowerShell version (`$PSVersionTable`) and OS.

## Reporting a security issue

Please do not open a public issue for anything that could be a security concern (e.g. a way to bypass a policy check, or a flaw in certificate/credential handling). Instead, use GitHub's private security advisory feature for this repository, or see the reporting contact in the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Questions

If something's unclear, open an issue, questions that improve this document are a welcome contribution in their own right.
