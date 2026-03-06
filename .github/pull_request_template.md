<!--
PR title guidance: Summarize the solution, not the problem
Use clear, solution-oriented title describing what the commits accomplish
Example: "Add input validation for empty usernames"
Avoid conventional commit format for PR titles (no "feat:", "fix:", etc.)
-->

## Summary

Brief description of the changes and the problem being solved:

- Main changes implemented
- Problem or issue addressed
- Approach taken and rationale

## Test plan

### Automated testing

- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Full test suite passes
- [ ] All quality checks pass (linting, type checking, etc.)

### Manual testing

- [ ] Tested with representative data
- [ ] Edge cases and error conditions verified
- [ ] Performance impact assessed (if applicable)

### Test coverage

- [ ] New functionality has comprehensive tests
- [ ] Test coverage maintained or improved
- [ ] Tests follow behavioral naming (`test_should_X_when_Y`)
- [ ] Tests focus on meaningful behavior, not implementation details

## Breaking changes

- List any breaking changes to public APIs
- Include migration steps or configuration changes needed
- Document deprecation timeline if applicable

## Performance and reliability

- [ ] Memory usage impact considered
- [ ] Retry patterns and error handling implemented where appropriate
- [ ] Logging added for debugging and monitoring

## Code quality

- [ ] Type annotations added for new code (if applicable to language)
- [ ] Documentation added for public APIs
- [ ] Error handling implemented with clear messages
- [ ] Functions maintain single responsibility
- [ ] Code quality hooks pass without modification

## Documentation

- [ ] Updated relevant documentation
- [ ] Added/updated documentation for public APIs
- [ ] Updated configuration examples if needed
- [ ] Created or updated ADR for significant architectural decisions
- [ ] Updated changelog if user-facing changes made

## Conventional commit compliance

- [ ] PR title uses solution-oriented summary (not conventional commit format)
- [ ] Individual commits follow conventional commit format: `<type>[scope]: <description>`
- [ ] Scope indicates module/component affected
- [ ] Semantic versioning impact: **PATCH** / **MINOR** / **MAJOR**

## Additional context

- Link to related issues or user stories
- Screenshots or examples (if applicable)
- Notes for reviewers about specific areas of focus
- Dependencies on other PRs or external changes
