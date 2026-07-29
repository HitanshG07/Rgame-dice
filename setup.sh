#!/bin/sh
# One-time arming of the brain's tamper-evidence layer + deployment completeness check.
# Run once per clone, from the repo root.

# 1. DEPLOYMENT COMPLETENESS CHECK — a partial copy is the most common real
#    failure (3 deployments shipped incomplete). Verify every required file
#    arrived before arming, so a half-deployed brain is caught loudly, not later.
REQUIRED="AI_WORKSPACE_RULES.md CLAUDE.md AGENTS.md GEMINI.md .github/copilot-instructions.md .githooks/pre-commit .claude/settings.json .brain/BOOT_DIGEST.md .brain/PERSONAS.md .brain/PIPELINE.md .brain/CHECKLISTS.md .brain/LEDGER.md .brain/SCOREBOARD.md .brain/DRILL.md .brain/DRILL_KEY.md .brain/skills/INDEX.md .brain/modes/INDEX.md"
missing=""
for f in $REQUIRED; do
    [ -e "$f" ] || missing="$missing
  $f"
done
if [ -n "$missing" ]; then
    echo "DEPLOYMENT INCOMPLETE: the brain is missing required files:$missing" >&2
    echo "" >&2
    echo "Copy the missing files from the master brain repository before arming." >&2
    echo "An incomplete deployment has no working enforcement layer." >&2
    exit 1
fi
echo "Deployment complete: all required brain files present."

# 2. ARM THE HOOK
if git config core.hooksPath .githooks; then
    echo "Brain hook armed: core.hooksPath -> $(git config core.hooksPath)"
else
    echo "ARMING FAILED: run this from the repository root (a git repository is required)." >&2
    exit 1
fi
