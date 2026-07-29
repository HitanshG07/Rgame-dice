CONSUMED-BY: Gate 0 / Matrix A
STATUS: LIVING — amend on divergence; every amendment cites its triggering fact

# SOFTWARE REQUIREMENTS SPECIFICATION (SRS) — 2D BOUNCY BALL TYCOON

## 1. PRODUCT OVERVIEW & PURPOSE
2D Bouncy Ball Tycoon is a high-performance, single-player isolated 2D physics idle simulator on Roblox. Players spawn colored bouncing balls inside a rotating ring with an opening gap. As balls bounce off ring walls, they generate cash, and when they escape through the gap, extra bonuses trigger. Earned cash is spent on upgrading ball count, ring spin speed, widening the gap, coin multipliers, luck, and spikes.

---

## 2. FUNCTIONAL REQUIREMENTS

### FR-1: 2D Physics & Canvas Engine
- **FR-1.1**: The game must render a circular ring container in 2D space (using Roblox `ScreenGui` / custom UI canvas or fixed orthographic 2D viewport).
- **FR-1.2**: Balls must maintain 2D velocity vectors, gravity, elasticity (bounciness), and accurate wall collision detection against circular ring arcs.
- **FR-1.3**: The ring must rotate at a speed determined by the `Ring Spin` upgrade level.
- **FR-1.4**: The ring must feature an opening gap of variable angular width (upgradable via `Widen Gap`). When a ball hits the gap, it exits the ring and respawns at the center with bonus cash.

### FR-2: Upgrades System & Economy
- **FR-2.1**: **Add Ring / Add Ball**: Increases maximum active balls bouncing in the ring.
- **FR-2.2**: **Ring Spin**: Increases rotation RPM of the outer ring.
- **FR-2.3**: **Widen Gap**: Expands the angular gap opening for easier escapes.
- **FR-2.4**: **Coin Bonus**: Multiplies cash earned per bounce.
- **FR-2.5**: **Increase Luck**: Increases probability of spawning higher-tier colored balls with higher multipliers.
- **FR-2.6**: **Ring Spikes**: Adds spikes along ring border that double bounce payout when hit.
- **FR-2.7**: Price scaling must follow exponential growth curves: `Cost(level) = BaseCost * (GrowthFactor ^ level)`.

### FR-3: User Interface & HUD Layout
- **FR-3.1**: Left Panel: Scrollable Upgrades drawer (Add Ring, Ring Spin, Widen Gap, Coin Bonus, Increase Luck, Ring Spikes, Color Picker).
- **FR-3.2**: Right Panel: Drawer menu (Balls, Prestige, Shop, Limited Event, Leaderboard, Settings, Rewards, Help, Statistics, Minigames, Nebulas, Enchants, Ultra, Quests, Codes).
- **FR-3.3**: Top Header: Live Cash counter, 2X boost status, FPS/performance stats, Daily Spin timer, Starter Bundle widget.
- **FR-3.4**: Bottom Bar: Primary action button ("Buy Ball"), claim free cash button, Prestige progress bar.

### FR-4: Data Persistence & Save System
- **FR-4.1**: Automatically save player cash, prestige level, total bounces, unlocked ball colors, and upgrade levels every 60 seconds and upon leaving.
- **FR-4.2**: Restore player state seamlessly upon joining.

---

## 3. NON-FUNCTIONAL REQUIREMENTS

### NFR-1: Performance & FPS
- **NFR-1.1**: Maintains smooth **60 FPS** on PC, Mobile, and Console devices with up to 50 simultaneous active 2D physics balls.
- **NFR-1.2**: Client 2D physics calculations must consume less than 15% of frame time (under 2.5ms per frame).

### NFR-2: Responsiveness & Display Scaling
- **NFR-2.1**: UI components must use relative scaling (`Scale` instead of static `Offset`) to render correctly on all screen resolutions (Mobile phones, Tablets, 1080p PC, 4K monitors).
- **NFR-2.2**: UI button clicks must respond within 50ms with visual micro-animations (hover scaling, click depression).

### NFR-3: Security & Server Authority
- **NFR-3.1**: All economy transactions (purchases, balance additions) are validated server-side to eliminate client manipulation.
