# PowerShell Scripts

A range of PowerShell scripts designed for both individual and enterprise use, balanced between individual users, small/medium enterprises, and large scale organisations.

## Structure

Each script lives in its own subfolder, with its own `README.md` and `CHANGELOG.md` documenting that script specifically. This keeps each script's documentation, configuration examples, and version history self-contained, so folders can be added, removed, or picked up independently without needing to understand the rest of the repository.

```
/
├── LICENSE
├── README.md                  (this file)
├── .gitignore                 (repo-wide exclusions)
└── <ScriptName>/
    ├── <ScriptName>.ps1
    ├── README.md               (usage, parameters, requirements)
    ├── CHANGELOG.md            (version history for this script)
    ├── .gitignore               (script-specific exclusions, where needed)
    └── <ScriptName>.example.json (example config file, where applicable)
```

## Scripts

| Script | Description |
|---|---|
| [`FileSigning`](./FileSigning/README.md) | Signs one or more files with a code signing certificate, obtained from an existing store entry, ADCS, or a self-signed fallback. |

## Requirements

Requirements vary per script and are documented in each script's own README. As a general baseline, all scripts in this repository:

- Target Windows PowerShell 5.1 and/or PowerShell 7+, noted individually where a script is Windows-only versus cross-platform.
- Follow Microsoft's approved verb-noun naming convention.
- Include comment-based help (`Get-Help <ScriptName>.ps1 -Full`).
- Use `[CmdletBinding()]`, and `SupportsShouldProcess` on anything with a destructive or state-changing action, so `-WhatIf`/`-Confirm` are available where relevant.

## Versioning and releases

Releases are tagged per script, using the pattern `<scriptname>-v<semver>`, e.g. `filesigning-v1.0.0`, since GitHub Releases and tags are repository-wide rather than folder-scoped. Each script's `CHANGELOG.md` records what changed at each tagged version.

## Contributing

This is primarily a personal collection of tooling, but issues and pull requests are welcome. Please open an issue for anything non-trivial before submitting a pull request.

## License

MIT. See [`LICENSE`](./LICENSE) for the full text. This applies repository-wide unless a specific script's folder contains its own LICENSE file stating otherwise.
