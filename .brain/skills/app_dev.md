# .brain/skills/app_dev.md - ELITE DECENTRALIZED APP DEVELOPMENT PROTOCOL

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

When this skill is activated at Gate 0, you must enforce production-grade reactive paradigms, structural state isolation, and zero-network security frameworks.

SCOPE LAW: apply only the sections matching the project's declared features and plan. Sections describing capabilities the project does not have — P2P/offline mesh networking (Section 2), E2EE cryptography (Section 3) — impose NO requirements on it; architectural rules (Section 1) bind UI-bearing Flutter apps, not plain Dart scripts. A skill section is never grounds to add a capability the plan didn't ask for.

## 1. Architectural Guardrails (BLoC & Clean Architecture)
- Every feature module must strictly isolate its UI layer, business logic layer (BLoC), and data provider layer (Repository).
- Streams must be explicitly managed: all event transformations must employ distinct concurrency models (droppable, restartable, concurrent) to prevent processing deadlocks.
- All BLoC instances must be cleanly disposed of via explicit lifecycle teardowns to eliminate background thread leakage.

## 2. Low-Level Networking & P2P Protocols
- When building serverless or offline communication systems (Wi-Fi Direct, BLE, Local Discovery APIs), enforce immediate asynchronous connection handlers.
- Implement strict Time-To-Live (TTL) multi-hop routing algorithms for all gossip protocols to prevent infinite broadcast looping and battery drainage.
- Handle socket drops gracefully: code mandatory exponential backoff reconnection loops with random jitter.

## 3. Cryptographic Frameworks & Local Persistence
- End-to-End Encryption (E2EE) must enforce cryptographic safety: isolate Ed25519 signing handshakes and X25519 key exchanges out of the UI thread.
- Local storage operations (SQLite/Hive) must use secure connection pooling. Run database migrations via explicit transactions with rolled-back states on failure.
