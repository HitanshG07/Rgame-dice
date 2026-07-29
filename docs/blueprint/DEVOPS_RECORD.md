CONSUMED-BY: Gate 1 / Matrix B
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# DEVOPS DECISIONS RECORD — 2D BOUNCY BALL TYCOON

1. **Environment Setup**: Primary development environment is Roblox Studio running on Windows, synced with local file system via Rojo / structured Luau modular scripts.
2. **Repository & Directory Layout**: Root project layout with source code under `src/` or `ReplicatedStorage`/`ServerScriptService` modules, `.brain/` governance, and `docs/blueprint/`.
3. **Branching Strategy**: `main` branch holds deployment-ready production place scripts; feature work isolated in single-purpose topic branches.
4. **CI & Static Verification**: Local static syntax verification using Luau linter/analyzer tools and automated runtime smoke via Roblox Studio execution.
5. **Secret Storage**: No credentials or private API keys stored in source code. Roblox Open Cloud API keys kept in OS environment variables (`ROBLOX_API_KEY`), excluded from git via `.gitignore`.
6. **Deploy Target & Mechanism**: Roblox Studio Place publishing to active Roblox Experience place ID.
7. **Monitoring & Logging**: Client and server runtime errors captured via `ScriptContext.Error` logging and Roblox Experience Analytics dashboard.
8. **Alerting Thresholds**: Server script crash alerts logged at error level; DataStore save failure rates monitored during player session end.
9. **DataStore Backup & Resilience**: Automatic retry queue (3 exponential backoff retries on failed DataStore requests); player memory cache retained during session if DataStore is unresponsive.
10. **Access & Security**: Server scripts execute with full server authority; Client scripts operate under zero-trust sandboxing.
