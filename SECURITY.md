# Security policy

## Scope

This project produces standalone binaries of [audiobookshelf](https://github.com/advplyr/audiobookshelf) from upstream source. Two kinds of issues belong here:

- **Packaging vulnerabilities** — anything that makes our binary less safe than upstream Docker (e.g. shipped library is older than declared, build pipeline tampering, supply-chain weakness in the workflow).
- **Build-pipeline vulnerabilities** — issues in this repo's GitHub Actions workflows, scripts, or release process.

**Vulnerabilities in audiobookshelf itself** (auth bypass, RCE, XSS in the web UI, etc.) belong upstream — please report at [advplyr/audiobookshelf](https://github.com/advplyr/audiobookshelf/security/advisories/new).

## Reporting

Please **do not** open a public issue. Use one of:

1. **GitHub private vulnerability reports** — open at <https://github.com/abhinandval/audiobookshelf-binary/security/advisories/new>.
2. Email the maintainer (address in the GitHub profile of [@abhinandval](https://github.com/abhinandval)).

Include:

- Affected release version(s)
- Affected target(s) (linux-arm64, etc.)
- Reproduction steps
- Impact assessment
- Your suggested fix, if any

## Response timeline

- **Acknowledgement**: within 5 business days
- **Triage decision**: within 14 days
- **Fix and release**: depends on severity; critical issues prioritised

## Verifying releases

Every release ships SHA256 checksums. SLSA provenance attestations are generated from the build workflow and can be verified with:

```sh
gh attestation verify <file> --owner abhinandval
```
