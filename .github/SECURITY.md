# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities privately via
[GitHub's private vulnerability reporting](https://github.com/dpezto/ltex-utils.nvim/security/advisories/new)
rather than filing a public issue.

Since this is a Neovim plugin (no server component, no secrets handled at
runtime), the main risk surface is:

- A crafted per-document settings file or dictionary, for example one shipped
  in a cloned repository, being read and acted on when a document is opened
- Supply-chain issues in CI (GitHub Actions dependencies)

Expect an initial response within a few days; this is a solo-maintained project.
