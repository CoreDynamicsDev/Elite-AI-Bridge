# Privacy and API Keys

## Local application data
Elite AI Bridge stores preferences, mappings, logs, and related user data in the current
Windows user's local application-data area. Program files are installed separately so
upgrades do not intentionally erase user configuration.

The public release does not intentionally contain the developer's API keys, account
credentials, personal files, or development-machine paths.

## OpenAI API key
The optional AI Co-Pilot requires the user to provide their own OpenAI API key.

On Windows, the current Bridge setup stores the supplied key as the current user's
`OPENAI_API_KEY` environment value and Bridge reads that value when AI features are used.
This is local to the user's Windows profile, but users should still treat the key like a
password. It is not a credential supplied by Elite AI Bridge.

Do not share a key, publish it, commit it to source control, or include it in support
material. Users are responsible for their own OpenAI account, API usage, billing, limits,
and compliance with OpenAI's applicable terms.

OpenAI recommends keeping keys out of source code/public repositories, using secure
storage, monitoring usage and spending, and rotating/revoking keys if exposure is
suspected.

Official guidance:
https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety

## Information sent to AI services
When optional AI features are enabled, information required to fulfill an AI request may
be transmitted to the configured AI provider. Do not enter secrets or information you do
not want transmitted to that provider. Provider handling is governed by that provider's
applicable terms and privacy policies.

## Diagnostics
Diagnostic/support exports may contain technical information such as application state,
settings, logs, hardware/control names, game-state information, or local file paths.
Review a support package before sharing it. Secret API keys should never be intentionally
included in a support package.

## No developer-operated advertising/data-broker system
Elite AI Bridge is an independent companion application and does not include a
developer-operated advertising or data-broker system.
