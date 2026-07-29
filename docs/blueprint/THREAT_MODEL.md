CONSUMED-BY: Gate 4 / Matrix E
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# THREAT MODEL — 2D BOUNCY BALL TYCOON (ROBLOX)

## 1. ASSETS
- **A-1: Currency & Progress (Cash Balance & Prestige Points)**: Direct player score and progression currency.
- **A-2: Saved Upgrades & Inventory**: Ball counts, ring spin speed, gap width levels, color unlocks, enchantments.
- **A-3: Robux Transactions**: Developer Product and GamePass purchase confirmations.
- **A-4: Leaderboard & Server Integrity**: Global stats, public rankings, and server stability.

---

## 2. TRUST BOUNDARIES
- **TB-1: Client-Server Network Boundary (RemoteEvents / RemoteFunctions)**: Messages sent between client ScreenGui/Physics engine and server scripts.
- **TB-2: Client Environment (Lua Sandbox on Player Device)**: All local scripts, UI renders, and local 2D ball physics predictions run in an untrusted client environment.
- **TB-3: Server-DataStore Boundary**: Serialization and deserialization of player data to Roblox DataStore service.

---

## 3. THREAT CENSUS & MITIGATIONS

### Boundary TB-1 & TB-2: Client Remote Spoofing & Exploits

#### T-1: Client Spoofs Ball Collision / Cash Grant Remote
- **Threat Vector**: A malicious client fires a `ClaimCash` RemoteEvent thousands of times per second claiming a ball bounced or escaped the ring.
- **Mitigation M-1**: The client does **NOT** decide cash gains via RPC calls. The server maintains an authoritative rate-limited tick engine based on the player's active stats (Ball Count, Ring Spin Speed, Coin Multipliers). Client physics is pure visual presentation; server calculates baseline passive income and validates periodic client collision sync batching within sanity bounds.

#### T-2: Client Manipulates Local Upgrades without Cash
- **Threat Vector**: Exploiter fires `PurchaseUpgrade` for "Add Ring" or "Ring Spin" without having sufficient cash.
- **Mitigation M-2**: All upgrade logic is strictly server-authoritative. The client requests `PurchaseUpgrade(upgradeId)`; the server checks player cash balance, verifies price scaling math, deducts cash server-side, increments upgrade level, and replicates updated state back to client.

#### T-3: Speed Hacks & Physics Injection
- **Threat Vector**: Exploiter speeds up client frame rate (FPS unlocker or Cheat Engine speed hack) to artificially trigger faster ball collisions.
- **Mitigation M-3**: Visual physics rates on client do not dictate financial yield directly; server calculates income using server timestamps (`os.clock()`) and strict delta caps.

#### T-4: Fake Robux Purchase Replay
- **Threat Vector**: Client fires purchase event claiming a Developer Product was bought.
- **Mitigation M-4**: Server handles Robux purchases exclusively via Roblox `MarketplaceService.ProcessReceipt`. No client RPC can grant Robux items or premium passes directly.

### Boundary TB-3: Data Store Corruption & Loss

#### T-5: Rapid Re-entry Data Overwrite / Race Conditions
- **Threat Vector**: Player leaves and re-joins quickly; older server session overwrites newer saved data.
- **Mitigation M-5**: Implement session-locking via `ProfileService` or data version tags (`DataStore2` / atomic `UpdateAsync` with session GUID check).

#### T-6: Data Corrupted by Invalid Schema
- **Threat Vector**: Code update changes save data format; old data loads as `nil` or crashes player state.
- **Mitigation M-6**: Strict schema migration layer with default fallback tables for every versioned key.

---

## 4. RISK REGISTER
- **R-1: Minor Visual Physics Desync**: Local 2D ball position on Client A may differ slightly from Client B's view (if observing).
  - *Risk Decision*: Accepted. Each player's workspace canvas is strictly local/single-player visual isolation, so client visual desync has zero gameplay impact.
- **R-2: Roblox DataStore Service Outages**: Roblox API outage causes save failures.
  - *Risk Decision*: Mitigated via retry queueing and autosave caching in memory during session duration.
