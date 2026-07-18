# PowerShell Scripts

A range of PowerShell scripts designed for both individual and enterprise use, balanced between individual users, small/medium enterprises, and large scale organisations.

## Structure

Each script lives in its own subfolder, with its own `README.MD` and `CHANGELOG.MD` documenting that script specifically. This keeps each script's documentation, configuration examples, and version history self-contained, so folders can be added, removed, or picked up independently without needing to understand the rest of the repository.

```
├── LICENSE
├── README.MD                  (this file)
├── .gitignore                 (repo-wide exclusions)
└── <ScriptName>/
   ├── <ScriptName>.ps1
   ├── README.MD               (usage, parameters, requirements)
   ├── CHANGELOG.MD            (version history for this script)
   ├── .gitignore               (script-specific exclusions, where needed)
   ├─── .env.EXAMPLE             (example environment file, where applicable)
   └── <ScriptName>.json.EXAMPLE (example config file, where applicable)
```

## Scripts

| Script | Description |
|---|---|
| [`FileSigning`](./FileSigning/README.md) | Signs one or more files with a code signing certificate, obtained from an existing store entry, ADCS, or a self-signed fallback. |
| [`WSUS-ClientSync`](./WSUS/Client-Sync/README.md) | Forces a Windows client to check in against its configured WSUS server, collects diagnostic information, and optionally remediates common synchronisation and installation errors automatically. |
---


## Requirements

Requirements vary per script and are documented in each script's own README. As a general baseline, all scripts in this repository:

- Target Windows PowerShell 5.1 and/or PowerShell 7+, noted individually where a script is Windows-only versus cross-platform.

- Follow Microsoft's approved verb-noun naming convention.

- Include comment-based help (`Get-Help <ScriptName>.ps1 -Full`).

- Use `[CmdletBinding()]`, and `SupportsShouldProcess` on anything with a destructive or state-changing action, so `-WhatIf`/`-Confirm` are available where relevant.

## Contributing

This is primarily a collection of tooling which I have found useful. I intend to maintain this repo, and so will welcome issues and pull requests. Please open an issue for anything non-trivial before submitting a pull request.

I will guarantee no timelines on resolving issues, including those which are script breaking - this is a hobby project.

## License

MIT. See [`LICENSE`](./LICENSE) for the full text. This applies repository-wide unless a specific script's folder contains its own LICENSE file stating otherwise.