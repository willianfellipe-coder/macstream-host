# Security Policy

MacStream Host is not ready for production use.

## MVP Security Principles

- Do not open router ports automatically.
- Do not enable UPnP by default.
- Do not expose the Sunshine Web UI beyond local access by default.
- Do not request Full Disk Access unless a future feature has a specific public-API need.
- Do not install privileged helpers or audio drivers without explicit user confirmation and design review.
- Redact sensitive information before exporting diagnostics.

## Reporting Issues

Until a public repository and private disclosure channel exist, security-sensitive findings should be reported directly to the project maintainer.
