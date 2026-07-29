@echo off
setlocal enabledelayedexpansion
rem One-time arming of the brain's tamper-evidence layer + deployment completeness check.
rem Run once per clone, from the repo root.

rem 1. DEPLOYMENT COMPLETENESS CHECK — a partial copy is the most common real
rem    failure (3 deployments shipped incomplete). Verify every required file
rem    arrived before arming, so a half-deployed brain is caught loudly.
set "MISSING="
for %%f in (
  "AI_WORKSPACE_RULES.md" "CLAUDE.md" "AGENTS.md" "GEMINI.md"
  ".github\copilot-instructions.md" ".githooks\pre-commit" ".claude\settings.json"
  ".brain\BOOT_DIGEST.md" ".brain\PERSONAS.md" ".brain\PIPELINE.md"
  ".brain\CHECKLISTS.md" ".brain\LEDGER.md" ".brain\SCOREBOARD.md"
  ".brain\DRILL.md" ".brain\DRILL_KEY.md" ".brain\skills\INDEX.md" ".brain\modes\INDEX.md"
) do (
  if not exist %%f set "MISSING=!MISSING! %%~f"
)
if not "!MISSING!"=="" (
  echo DEPLOYMENT INCOMPLETE: the brain is missing required files:!MISSING!
  echo Copy the missing files from the master brain repository before arming.
  echo An incomplete deployment has no working enforcement layer.
  exit /b 1
)
echo Deployment complete: all required brain files present.

rem 2. ARM THE HOOK
git config core.hooksPath .githooks
if errorlevel 1 (
    echo ARMING FAILED: run this from the repository root ^(a git repository is required^).
    exit /b 1
)
for /f "delims=" %%h in ('git config core.hooksPath') do echo Brain hook armed: core.hooksPath -^> %%h
