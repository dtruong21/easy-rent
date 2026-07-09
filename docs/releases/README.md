# Notes de version

Miroir **optionnel** des releases. La source de vérité des notes reste la
**GitHub Release** de chaque tag `vX.Y.Z` (voir [`../VERSIONING.md`](../VERSIONING.md)).

Un fichier `vX.Y.Z-<codename>.md` est généré par
`tool/release/release.sh … --notes-file`. Comme `main` est verrouillée, ces
fichiers se committent **via `develop`**, jamais directement sur `main`.
