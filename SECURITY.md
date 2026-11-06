# Security policy

## Supported versions

Snippet is in alpha. Security fixes are made on `main` and shipped in the next release, so only the latest release is supported.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through [GitHub security advisories](https://github.com/intellinesia/snippet-app/security/advisories/new). If the problem turns out to sit in the daemon, report it [there](https://github.com/intellinesia/snippet/security/advisories/new) or say so in your report and it will be moved.

A useful report includes:

- the version or commit affected, and the operating system;
- the steps to reproduce the problem;
- what an attacker gains, and what access they need first;
- a suggested fix, if you have one.

Remove any real API keys, tokens or personal data from logs before sharing them.

## What happens next

We aim to acknowledge a report within seven days, and will keep you informed while a fix is prepared. Once a fix has shipped we will publish an advisory and credit you, unless you prefer to remain anonymous.

Please give us reasonable time to release a fix before disclosing the problem publicly. This is a volunteer-run project and no bounty is offered.

## Scope

In scope:

- exposing the `serve` token or other credentials through the app, its logs, notifications or backups;
- accepting a connection or a deep link in a way that lets someone else control the daemon;
- other apps or websites reading sessions, transcripts or files through the app;
- audio or transcripts being captured or shown when the user has turned listening off.

Out of scope:

- attacks that already need an unlocked device or the user's `serve` token;
- problems in the daemon itself, which belong in the snippet repository;
- issues that only appear on a modified or rooted build.
