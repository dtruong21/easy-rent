---
description: Lance une passe QA complète — tests automatisés + bug hunt + security audit
---

Tu es l'orchestrateur. Lance une passe QA complète sur la branche courante.

## Étapes (en parallèle quand possible)

1. **Invoque `qa-tester`** → lance les tests, produit le rapport QA
2. **Invoque `bug-hunter`** en parallèle → scan complet du codebase
3. **Invoque `code-reviewer`** en parallèle → revue de la branche courante vs main
4. **Invoque `security-auditor`** → audit RLS + secrets + RGPD

## Output attendu

Présente à l'utilisateur un tableau de bord :

| Agent | Verdict | Findings critiques |
|---|---|---|
| qa-tester | ✅/❌ | ... |
| bug-hunter | ✅/⚠️ | ... |
| code-reviewer | ✅/❌ | ... |
| security-auditor | ✅/❌ | ... |

Puis liste les actions prioritaires recommandées.

$ARGUMENTS
