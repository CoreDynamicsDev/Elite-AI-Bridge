# Security

Elite AI Bridge is distributed as a Windows application and its source is published in this repository for community inspection.

## Reporting a security issue

Please do not publish exploit details, credentials, API keys, tokens, passwords, or other sensitive information in a public GitHub issue.

If GitHub Security Advisories are enabled for this repository, use the private security reporting workflow. Otherwise, contact the maintainer through the GitHub profile and request a private channel.

## API keys

Elite AI Bridge does not ship with a developer OpenAI API key. AI users supply their own key. Never commit an API key to the repository.

If a key is accidentally exposed, revoke or rotate it immediately with the service provider and then remove the secret from the repository history.

## Support packages

Diagnostic exports may contain application state, settings, logs, hardware/control names, game-state information, or local paths. Review a diagnostic package before sharing it publicly.
