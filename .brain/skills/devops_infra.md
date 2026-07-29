# .brain/skills/devops_infra.md - SECURE SYSTEMS ADMINISTRATION & AUTOMATION INFRASTRUCTURE

*COGNITIVE DIRECTIVE: This is a living evolutionary document. If you encounter a more optimized methodology, a newer API standard, or a superior architectural pattern during development, you are strictly mandated to activate the Cognitive Evolutionist persona during Gate 6 and rewrite these rules to permanently upgrade this skill.*

When this skill is activated at Gate 0, you must enforce a zero-trust script runtime environment, robust logging systems, and isolated infrastructure layouts.

SCOPE LAW: apply only the sections matching what the project actually contains — kernel-module rules (Section 1) bind only projects with kernel sources; CI/CD rules (Section 2) bind projects with workflow definitions. Matching on a marker file loads the skill; the project's real contents decide which sections govern.

## 1. Linux/Ubuntu Systems and Kernel Architecture
- When configuring system automation or interacting with custom hardware modules (e.g., custom network interface kernel modules on Ubuntu 22.04 LTS), all bash scripts must declare strict execution wrappers (`set -euo pipefail`).
- Implement descriptive, structured logging targets (`stderr`/`stdout`) with systematic, automated rotation paths for all telemetry records.

## 2. Version Control & Continuous Integration (CI/CD)
- GitHub Action workflows and deployment runners must employ granular, locked permissions (`contents: read`).
- Pin every single baseline step action to its specific cryptographic SHA hash value rather than a mutable branch tag to mitigate upstream supply-chain compromise vectors.

## 3. Environment Scoping & Secret Enforcement
- Maintain absolute separation between host configurations and target development spaces. Scripts handling local environment settings or package lockfiles must validate execution constraints before altering files.
