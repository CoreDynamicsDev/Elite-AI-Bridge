# Public Repository Structure

The repository separates readable source, documentation, installer definitions, and branding.

```text
Elite-AI-Bridge/
├── .github/
│   └── ISSUE_TEMPLATE/
├── branding/
├── docs/
├── installer/
├── src/
│   └── Elite AI Bridge/
│       ├── backend/
│       ├── frontend/
│       ├── assets/
│       └── docs/
├── README.md
├── SOURCE_CODE.md
├── SECURITY.md
├── LICENSE.txt
├── DISCLAIMER.md
├── PRIVACY_AND_API_KEYS.md
├── THIRD_PARTY_NOTICES.md
└── CONTRIBUTING.md
```

Compiled installers belong in GitHub Releases, not in the source tree. Virtual environments, diagnostics, logs, and build output do not belong in the public repository.
