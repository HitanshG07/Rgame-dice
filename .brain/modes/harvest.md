# .brain/modes/harvest.md - CROSS-PROJECT HARVEST PROTOCOL

*MODE CONTRACT: living document; Gate 6 may refine it under double veto, but the audit-before-merge rule and provenance annotation may never be weakened.*

## ENTRY CRITERIA
Runs in the MASTER brain repository only, on operator trigger ("harvest [child path]"), typically after a child project ships a phase or completes. Requires read access to the child's `.brain/` and its git history. Never runs inside a child.

## THE PRIME LAW
Audit before merge. A child's lessons are claims until verified against its artifacts; merging unaudited knowledge poisons every future project. Harvest only reads the child — nothing is deleted from it, and the child keeps its full memory.

## MANDATORY SEQUENCE
1. **Generation diff:** compare the child's brain version stamp and governance files against the master's; record drift, local mutations, and divergence.
2. **Compliance audit:** verify the child's scoreboard honesty (failures recorded as failures), Gate 6 presence (Evolution Reports exist), and hook armament. Findings go in the report — dishonest bookkeeping downgrades trust in everything else the child claims.
3. **Skill harvest:** skills forged in the child are audited to Matrix G standards (source corroboration, house conventions, security review) and merged with a provenance note (child name + date). Changes to existing skills merge only where they generalize beyond the child's specifics.
4. **Ledger harvest:** child ledger entries with value beyond the project (toolchain fixes, API quirks, binding corrections) merge into the master ledger with provenance notes, re-numbered into the master's Log ID sequence. Project-specific entries stay behind.
5. **Registry and report:** register any new skill mappings (additive); write the Harvest Report BEFORE committing and present it to the operator for the merge go-ahead.

## EXIT ARTIFACT
The Harvest Report: generation diff, compliance findings, merged items with provenance, and rejected items with reasons. The merge commit lands only after operator review.
