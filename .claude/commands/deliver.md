---
description: Déploie la branche courante après vérification finale — staging puis prod (avec confirmation)
argument-hint: staging | prod (défaut: staging)
---

Tu es l'orchestrateur. Déploie EasyRent.

## Cible

$ARGUMENTS (défaut: staging)

## Pré-flight checklist (obligatoire avant deploy)

1. Vérifie que les rapports les plus récents sont verts :
   - `docs/qa-reports/` → dernier rapport = READY
   - `docs/reviews/` → dernier review = APPROVED
   - `docs/security-audits/` → dernier audit = SAFE TO DEPLOY
2. Vérifie l'état git : pas de fichiers non commités sur la branche
3. Pour **prod** : DEMANDE confirmation explicite à l'utilisateur en montrant :
   - La liste des commits qui vont être déployés
   - La liste des migrations qui vont être appliquées
   - Le résumé du release note proposé

## Exécution

- Invoque `deployer` avec la cible (staging ou prod)
- Surveille la sortie, surface les erreurs immédiatement
- Si déploiement échoue → propose un rollback automatique

## Post-deploy

- Affiche l'URL déployée
- Affiche le chemin du release note
- Propose un smoke test manuel (3-5 scénarios) si on est en prod
