---
name: Bug
about: Report a bug or issue
title: ''
labels: bug
assignees: ''
---

<!--
Title guidance: Use plain English to describe what's broken or unexpected
Example: "Crash when saving profile with empty username"
Avoid conventional commit format for issues (no "fix:", "bug:", etc.)
-->

## Summary

<One line description of the bug.>

## The problem

<What's broken and why it matters to users or contributors.>

## Expected behavior

<What should happen instead.>

## Actual behavior

<What actually happens (include error messages, logs, screenshots).>

## Proposed solution

<How we'll fix it (technical approach if known).>

## Acceptance criteria (testable)

- [ ] GIVEN … WHEN … THEN …
- [ ] …
- [ ] Documentation updated if needed

## Testing strategy (test-first)

<!--
Follow test-first approach with meaningful behavioral tests
Avoid vanity tests that only verify framework behavior or trivial operations
-->

- **Unit tests**:
- **Integration/E2E tests**:
- **Edge cases**:
- **Regression tests**:

## Links

- **User stories**: `US-XXX`
- **ADRs**: `ADR-XXX`
- **Related issues**: `#XXX`

## Project fields

<!--
Set these fields in GitHub's project interface after creating the issue
Issues start as Backlog and move to Todo after review

Using GitHub CLI to set fields after creating issue:

# Add repository labels (simple, repository-scoped)
gh issue edit ISSUE_NUM --add-label "type:bug,area:frontend"

# Add to project
gh issue edit ISSUE_NUM --add-project "Project Name"

# Set project custom fields (requires GraphQL, project-scoped)
# First, get field and option IDs from your project:
gh api graphql -f query='query($project: ID!) {
  node(id: $project) {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField { id name options { id name } }
        }
      }
    }
  }
}' -F project="PROJECT_ID"

# Then update field values:
gh api graphql -f query='mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "PROJECT_ID"
    itemId: "ITEM_ID"
    fieldId: "VALUE_FIELD_ID"
    value: {singleSelectOptionId: "ESSENTIAL_OPTION_ID"}
  }) { projectV2Item { id } }
}'
-->

**Project custom fields** (project-scoped, set via UI or GraphQL):

- **Value (impact)**: Essential (must-have, critical to success) | Useful (adds clear benefit but not critical) | Nice-to-have (optional, polish or long-term benefit)
- **Effort (scope)**: Heavy (large scope, multi-step or cross-cutting) | Moderate (medium scope, single feature/module) | Light (small, contained, quick to complete)
- **Status**: Backlog (awaiting review/prioritization) | Todo (ready to start) | Doing (actively being worked) | Done (completed and merged)
- **Relationship**: Parent (larger body of work containing sub-issues) | Child of `#…` (sub-issue of a parent issue) | Standalone (independent issue)
- **Blocked by**: Notes or links to dependencies preventing progress

**Repository labels** (repository-scoped, set via CLI):

- **Type**: bug | feature | chore | docs
- **Area**: frontend | backend | api | infra
- **Labels**: Apply with `gh issue edit NUM --add-label "type:bug,area:frontend"`

**Native GitHub fields**:

- **Parent issue**: Link if this is a sub-issue (use **Add sub-issue** in parent issue)
- **Assignees**: Assign team members responsible
