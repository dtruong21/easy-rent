#!/usr/bin/env bash
# Installe les git hooks du projet (pre-commit notamment).
# À lancer une fois après le clone.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

cat > "$HOOKS_DIR/pre-commit" <<'EOF'
#!/usr/bin/env bash
# Auto-installé par scripts/install-hooks.sh
exec "$(git rev-parse --show-toplevel)/scripts/check-secrets.sh"
EOF

chmod +x "$HOOKS_DIR/pre-commit"
chmod +x "$REPO_ROOT/scripts/check-secrets.sh"

echo "✅ Pre-commit hook installé."
echo "   Test : echo 'sb_secret_test1234567890123456' > /tmp/fake && git add /tmp/fake && git commit"
echo "   (le commit doit être bloqué)"
