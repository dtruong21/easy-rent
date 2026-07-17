# FEAT-051 – Feature Readiness Score

## Status

En cours — implémenté par `tool/feature_ready.dart` + `/feature-ready`.

> **Renumérotation FEAT-045 → FEAT-051** : le plan initial réutilisait
> `FEAT-045`, déjà attribué à « Suppression compte in-app + /delete-account »
> (✅ done, PR #69, cf. `docs/state/FEATURES.md`). Les suivis d'audit FEAT-046
> et FEAT-047 (`docs/BACKLOG.md`) référencent FEAT-045 dans ce sens-là ;
> l'ID de cette feature est donc passé à `FEAT-051`, premier libre.

---

# Goal

Provide an automated readiness evaluation for every feature before merge.

The objective is not to block development but to make feature quality visible and consistent across the project.

This feature gives Claude and developers a common Definition of Ready / Definition of Done checklist.

---

# Problem

As EasyRent grows, it becomes increasingly difficult to know whether a feature is truly ready.

Current questions include:

- Are business rules implemented?
- Are widget tests present?
- Are translations complete?
- Is documentation updated?
- Has accessibility been reviewed?
- Does the feature affect SEO?
- Does it require Store Compliance updates?
- Has docs/state been refreshed?

These checks are currently manual.

---

# User Story

As a developer,

I want a readiness report,

So that I know exactly what is still missing before merging a feature.

---

# Primary Users

- Developers
- Claude
- Future contributors

---

# Success Criteria

Running the readiness command produces a single report containing:

- Overall readiness score
- Category breakdown
- Missing items
- Suggested next actions

The report must be deterministic.

Running it twice without code changes must produce identical results.

---

# UX

Developer runs:

```bash
/feature-ready
```

Output example:

```
Feature Readiness

Overall Score
84 / 100

Documentation
✅

Tests
⚠ Missing widget tests

Accessibility
⚠ Not reviewed

Localization
✅

Analytics
❌ Missing events

State documentation
❌ Not updated

Recommendation

Ready after fixing:
- analytics
- state update
```

---

# Categories

## Documentation

Checks:

- FEAT plan exists
- backlog item exists (if applicable)
- documentation updated

Weight: 15%

---

## Testing

Checks:

- unit tests
- widget tests
- regression tests

Weight: 25%

---

## Localization

Checks:

- app_en.arb
- app_fr.arb

No missing keys.

Weight: 10%

---

## Accessibility

Checks:

- semantics
- keyboard navigation (Web)
- contrast review (manual acknowledgement)

Weight: 10%

---

## Product Completeness

Checks:

- acceptance criteria addressed
- edge cases considered

Weight: 15%

---

## Technical Health

Checks:

- analyzer clean
- formatting
- CI ready

Weight: 15%

---

## Project State

Checks:

- docs/state updated
- changelog updated (if needed)

Weight: 10%

---

# Business Rules

The readiness score must never modify project files.

The command is read-only.

The score is advisory.

It must not fail CI by default.

---

# Non Goals

This feature does not:

- deploy the application
- execute tests automatically
- replace code review
- replace QA

---

# Future Extensions

Future versions may include:

- Store Release Readiness
- Performance Readiness
- Security Readiness
- SEO Readiness
- AI-generated improvement suggestions

---

# Acceptance Criteria

- A readiness command exists.
- A readiness report is generated.
- Every category contributes to the total score.
- Missing items are clearly listed.
- The report is deterministic.
- The feature does not modify project files.

---

# Technical Notes

Implementation details are intentionally left to the engineering workflow.

The command should integrate naturally with the existing `.claude/commands` ecosystem and reuse existing project documentation where possible instead of introducing duplicate metadata.