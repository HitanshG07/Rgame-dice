# Antigravity prompt — clear the orphaned MCP processes and stale proxy logs

Paste everything below the line into Antigravity. It is a maintenance task, not
a code change: it touches no file in `src/`, `tests/`, `.brain/` or `docs/`.

---

You are performing a one-time cleanup on a Windows 11 machine. Repo: `C:\RGame`.
Do exactly what is listed, report what you actually observed, and change no
project source file. If any step's precondition does not hold, say so and stop
rather than improvising.

## BACKGROUND — what happened and why this is needed

The machine suffered out-of-memory crashes on 2026-08-13, -18 and -19. The cause
was diagnosed from the language server's own logs: it was NOT workspace
indexing. `C:\RGame` is 266 files and 64MB, and `ls-main.log` records no
allocation failure of any kind.

The cause was the Roblox Studio MCP proxy
(`%LOCALAPPDATA%\Roblox\roblox_studio_mcp_proxy.js`), which had three defects:

1. It logged every MCP message verbatim with `appendFileSync`. Screen captures
   travel as multi-megabyte base64 strings, so each screenshot was buffered as a
   JS string and written synchronously. Its log reached 60MB.
2. It ignored `child.stdin.write` backpressure, so when StudioMCP stalled — it
   hit four three-minute timeouts on 2026-08-19 — Node queued messages in memory
   without limit.
3. It could exit without killing `StudioMCP.exe`, so restarts accumulated
   orphans. Antigravity logged `McpServers (unknown): failed to stop existing
   instance` nine times.

**The proxy has already been fixed and committed** (`a4704ed` on branch
`ui-rewamp-ongoing`). Logging is now truncated at 2KB per entry with base64
payloads summarised and rotation at 5MB; backpressure is honoured; every exit
path kills the child. Verified by test: a 400KB image passes through to the IDE
byte-for-byte intact while the log entry costs 934 bytes.

What remains is the debris the old version left behind. That is this task.

## STEP 1 — RESTART TO LOAD THE FIXED PROXY

The currently-running proxy is the OLD code, held in memory. Its log is still
growing. Restarting Antigravity is what loads the fixed version.

Confirm before proceeding: has Antigravity been fully closed and reopened since
`a4704ed` was committed? If not, do that first — every step below is undone by
a running old proxy.

## STEP 2 — COUNT THE ORPHANS

Run in PowerShell and report the raw output:

    Get-Process StudioMCP -ErrorAction SilentlyContinue |
      Select-Object Id, StartTime, @{N='MB';E={[math]::Round($_.WorkingSet64/1MB,1)}} |
      Format-Table -AutoSize

At the time of diagnosis there were **6** `StudioMCP.exe` processes holding
roughly 65MB combined. A healthy machine with Studio in use has one, or none.

## STEP 3 — KILL ONLY THE STALE ONES

A process whose `StartTime` predates your current Antigravity session is an
orphan: nothing is talking to it and nothing will.

    # Review first — this only LISTS what would be killed.
    $cutoff = (Get-Process -Id $PID).StartTime
    Get-Process StudioMCP -ErrorAction SilentlyContinue |
      Where-Object { $_.StartTime -lt $cutoff } |
      Select-Object Id, StartTime

Report that list. Then, and only then:

    Get-Process StudioMCP -ErrorAction SilentlyContinue |
      Where-Object { $_.StartTime -lt $cutoff } |
      Stop-Process -Force

**Do not** blanket-kill every `node.exe`. Several belong to Antigravity itself,
to the Claude Code extension, and possibly to a Rojo serve session; killing
those interrupts live work. Only `StudioMCP.exe` is targeted here.

## STEP 4 — TRUNCATE THE STALE PROXY LOGS

Two log files survive from the old proxy and will never be read again. The fixed
proxy rotates its own log, so these are the last manual cleanup needed:

    $logs = @(
      "$env:LOCALAPPDATA\Roblox\mcp_proxy.log",
      "$env:USERPROFILE\.gemini\config\mcp_proxy.log"
    )
    foreach ($p in $logs) {
      if (Test-Path $p) {
        "{0,12:N0} bytes  {1}" -f (Get-Item $p).Length, $p
        Remove-Item $p -Force
      }
    }

Expected sizes at diagnosis: roughly **60,654,887** and **9,555,921** bytes.
Report the actual figures. If either is dramatically larger, say so — that means
the old proxy was still running and Step 1 was not completed.

## WHAT NOT TO TOUCH

- **`C:\RGame\.brain\`** — project governance and memory. Off limits entirely.
- **`src/Client/UIMockPreview.luau`** — the operator is actively working in it.
- **`C:\RGame\tools\*.js`** — 32 live Studio automation scripts. Six spent
  one-offs were already removed in `0fcda4c`; the rest stay.
- **The Crashpad dumps** in `%APPDATA%\Antigravity IDE\Crashpad\reports\` —
  three `.dmp` files, ~108MB. These are the only forensic record of the actual
  crashes and the operator chose to keep them. Leave them.
- **Any `node.exe` you have not positively identified as an orphaned StudioMCP
  parent.**

## REPORT BACK

1. Whether Antigravity was restarted before you began (Step 1).
2. The `StudioMCP.exe` table from Step 2, verbatim.
3. Which PIDs you killed, and how many remain.
4. The byte sizes of both logs before deletion.
5. Anything you found that contradicts the background above.

Report what you observed, not what you expected. If a command returned nothing
or errored, say so plainly — a cleanup that reports success it did not verify is
worse than one that reports a partial result honestly.
