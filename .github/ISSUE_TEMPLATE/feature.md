---
name: Feature
about: Propose a new feature or enhancement
title: ''
labels: feature
assignees: ''
---

<!--
Title guidance: Describe the problem being solved, not the solution
Example: "Can't export user data to CSV"
Avoid conventional commit format for issues (no "feat:", "add:", etc.)
-->

## Summary

<One line overview.>

## The problem

<Why this matters to users or contributors.>

## Proposed solution

<How we'll solve it (keep distinct from the problem).>

## Acceptance criteria (testable)

- [ ] GIVEN … WHEN … THEN …
- [ ] …
- [ ] Documentation updated

## Testing strategy (test-first)

<!--
Follow test-first approach with meaningful behavioral tests
Avoid vanity tests that only verify framework behavior or trivial operations
-->

- **Unit tests**:
- **Integration/E2E tests**:
- **Edge cases**:

## Links

- **User stories**: `US-XXX`
- **ADRs**: `ADR-XXX`

<!--
Set these fields in GitHub's project interface after creating the issue
Issues start as Backlog and move to Todo after review

Using GitHub CLI to set fields after creating issue:

# Add repository labels (simple, repository-scoped)
gh issue edit ISSUE_NUM --add-label "type:feature,area:api"

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
    value: {singleSelectOptionId: "USEFUL_OPTION_ID"}
  }) { projectV2Item { id } }
}'

Project custom fields (project-scoped):
- Value (impact): Essential | Useful | Nice-to-have
- Effort (scope): Heavy | Moderate | Light
- Status: Backlog | Todo | Doing | Done
- Relationship: Parent | Child of #... | Standalone
- Blocked by: Dependencies preventing progress

Repository labels (repository-scoped):
- Type: bug | feature | chore | docs
- Area: frontend | backend | api | infra

Native GitHub fields:
- Labels: Apply with gh CLI
- Parent issue: Link if this is a sub-issue
- Assignees: Assign team members responsible
-->
