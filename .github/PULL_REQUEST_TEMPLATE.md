<!--
PR titles must follow Conventional Commits, e.g.:
  feat: add windows-amd64 target
  fix: pin yao-pkg/pkg to 6.19.0
  ci: switch to ubuntu-24.04-arm runner
The pr-title workflow will fail otherwise (squash-merge uses the title as the commit message).
-->

## Summary

<!-- One or two sentences. What does this change and why? -->

## Type of change

- [ ] Build / packaging fix
- [ ] New target platform
- [ ] CI / workflow change
- [ ] Documentation
- [ ] Dependency bump
- [ ] Other

## Verification

<!-- How did you confirm this works? -->

- [ ] CI lint passed locally (`pre-commit run --all-files`)
- [ ] Build workflow tested on the affected target(s)
- [ ] Smoke test passes — binary reaches "Running in production"

## Linked issues

Closes #
