# .brain/skills/game_dev.md - ELITE 3D GRAPHICS & GAME ENGINEERING PROTOCOL

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

When this skill is activated at Gate 0, you must enforce rigorous performance standards, deterministic math structures, and optimized object lifecycles.

SCOPE LAW: engine-specific rules (UE5/C++, Sections 1 and 3) bind only projects on that engine; other engines take the general principles here (memory safety, event-driven updates over polling) and route engine specifics through Skill Genesis.

## 1. Unreal Engine 5 & C++ Architecture
- Maintain a strict hierarchy boundary: Core computational logic, heavy calculations, and interface structures live in optimized C++. Blueprint scripting is reserved purely for visual execution, UI updates, and runtime component initialization.
- Enforce strict memory safety: utilize smart pointers (TSharedPtr, TUniquePtr) or explicit UPROPERTY() macro references to protect objects from unexpected Garbage Collection sweeps.

## 2. 3D Graphics, Rigging, and Component Architecture
- Validate skeletal meshes, asset rig bounds, and customized 3D models (e.g., Shapr3D exports) prior to component attachments.
- Component attachments (props, collision triggers, motion-captured animation tracks) must specify exact socket offsets and transform parameters to guarantee frame-rate independent updates.

## 3. High-Performance Frame Loop Optimizations
- Keep Tick functions disabled (`bCanEverTick = false`) on all background actors unless absolutely necessary.
- Use event-driven delegates, timers, and localized spatial grid polling instead of constant polling to keep the main rendering loop executing at a locked frame rate.
