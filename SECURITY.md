# Security

Elite AI Bridge is distributed as a Windows application and its source is published in this repository for community inspection.

## Reporting a security issue

Please do not publish exploit details, credentials, API keys, tokens, passwords, or other sensitive information in a public GitHub issue.

Email coredynamicsdev@gmail.com with the details instead, and you'll get a reply there.

## API keys

Elite AI Bridge does not ship with a developer OpenAI API key. AI users supply their own key. Never commit an API key to the repository.

If a key is accidentally exposed, revoke or rotate it immediately with OpenAI and then remove it from wherever it was posted.

## Support files

Support files (Setup > Status > MAKE SUPPORT FILE) never include your API key, but they may contain settings, logs, controller names, game-state information, or local paths. Review a support file before sharing it publicly.

## Checking a download

Each release lists the SHA256 checksum of its installer. To check your download, run this in the folder that holds it and compare the result:

    certutil -hashfile Elite_AI_Bridge_Setup_2.0.0.exe SHA256
