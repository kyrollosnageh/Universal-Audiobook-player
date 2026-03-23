# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Libretto, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. **Email**: Send a detailed report to the repository maintainers via GitHub's private vulnerability reporting feature.
2. **GitHub Security Advisories**: Use the "Report a vulnerability" button on the Security tab of this repository.

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 5 business days
- **Fix Target**: Within 30 days for critical/high severity

## Security Architecture

Libretto follows these security principles:

### Authentication & Credentials
- **No password storage**: Passwords are used once for authentication, then immediately discarded
- **Secure token storage**: All tokens stored via `flutter_secure_storage` (iOS Keychain / Android EncryptedSharedPreferences)
- **Token namespacing**: Each server's credentials isolated under `server:{url}:token`
- **Session revocation**: Logout clears tokens locally AND revokes server-side sessions

### Network Security
- **HTTPS enforced**: HTTP connections require explicit user acknowledgment and are limited to localhost/LAN
- **No certificate bypass**: We never disable certificate validation (`badCertificateCallback => true` is prohibited)
- **Trust-On-First-Use (TOFU)**: Self-signed certificates can be trusted per-fingerprint, validated on subsequent connections
- **Per-server Dio instances**: Each server connection is fully isolated

### Data Protection
- **PII stripping**: Crash reports and analytics never include server URLs, usernames, book titles, or file paths
- **Opt-in analytics only**: Usage tracking requires explicit user consent
- **Log redaction**: Auth headers and tokens are never logged in release builds

### CI/CD Security
- **Dependabot**: Automated dependency updates with grouped PRs
- **CodeQL SAST**: Static analysis on every push and weekly schedule
- **Gitleaks**: Secret scanning across full git history
- **Dependency Review**: New dependencies checked for vulnerabilities and license compliance on every PR
- **Hardcoded secret scan**: CI fails if potential secrets are detected in source code
- **Certificate validation audit**: CI fails if `badCertificateCallback => true` is found

## Security Scanning

The following automated security checks run on this repository:

| Check                      | Trigger               | Blocks PR |
|----------------------------|-----------------------|-----------|
| CodeQL SAST                | Push, PR, Weekly      | No*       |
| Gitleaks Secret Scan       | Push, PR, Weekly      | Yes       |
| Dependency Review          | PR only               | Yes (high/critical) |
| Hardcoded Secret Scan      | Push, PR              | Yes       |
| Certificate Validation     | Push, PR, Weekly      | Yes       |
| SharedPreferences Audit    | Push, PR, Weekly      | Yes       |
| License Compliance         | Push, PR, Weekly      | No        |

\* CodeQL results are uploaded to GitHub Security tab for review.
