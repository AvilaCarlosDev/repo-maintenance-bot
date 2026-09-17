# Security Policy

## Supported code

Until the first tagged release, security fixes are applied to the latest commit on the main branch only.

| Version | Supported |
|---|---|
| main | Yes |
| Older commits and forks | No |

## Reporting a vulnerability

Do not publish credentials, exploit details, private repository paths, or proof-of-concept payloads in a public issue.

Use the repository Security tab and select **Report a vulnerability** when private vulnerability reporting is available. If that option is unavailable, open a public issue containing no sensitive details and ask the maintainer for a private reporting channel.

Include:

- affected commit;
- operating system and Bash version;
- minimal reproduction;
- expected and observed behavior;
- potential impact;
- whether credentials, repositories, or remotes were affected.

## Relevant security areas

Reports are especially useful when they involve:

- unexpected files staged or committed;
- mutation during dry-run;
- unsafe temporary-directory cleanup;
- command or path injection;
- credential leakage in logs;
- unintended push behavior;
- bypasses of test/build validation;
- execution of dependency lifecycle scripts without opt-in.

## Disclosure

Please allow time to reproduce and remediate a confirmed issue before publishing technical details. A report may be declined when it cannot be reproduced, affects unsupported modifications, or depends on explicitly disabled safeguards.
