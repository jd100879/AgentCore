# ADR 002: Canonical Interface Implementation Strategy

**Status:** Proposed
**Date:** 2026-02-13
**Context:** Phase 2 complete, Phase 3 planning

## Context

The `agentcore/tools/` directory serves as the canonical coordination interface for AgentCore's infrastructure. As part of the folder organization project, we established this canonical location to provide a clean, stable API for coordination scripts that are used across the project and potentially by other projects via `flywheel_tools/install.sh`.

Currently, `agentcore/tools/` is implemented as a collection of symlinks pointing to the actual script implementations in `scripts/`. This works, but we need to decide on the long-term strategy for this interface as we move into Phase 3.

The decision matters because:
- The interface needs to be stable and reliable for both human and automated users
- Scripts may be invoked from various contexts (direct call, via symlink, from different CWD)
- We want to balance simplicity with maintainability
- The choice affects how we handle path resolution, environment setup, and future refactoring

## Decision Question

Should `agentcore/tools/*` remain as pure symlinks to scripts in `scripts/`, or should they be converted to wrapper scripts that provide an interface layer?

## Options

### Option A: Pure Symlinks (Current)

Keep `agentcore/tools/` as symlinks to actual script implementations.

**Pros:**
- Minimal maintenance burden - no wrapper code to maintain
- Direct execution with no wrapper overhead
- Scripts remain in their original location (`scripts/`)
- Simple and transparent - what you see is what you get
- Changes to scripts immediately reflected in canonical interface
- No risk of wrapper/script version mismatch

**Cons:**
- No interface enforcement layer between canonical path and implementation
- Cannot inject consistent environment variables, flags, or logging
- Path resolution logic must be embedded in each individual script
- Symlink semantics can be confusing (requires `readlink`/`realpath` handling)
- Scripts must be symlink-aware (adding complexity to each script)
- No ability to intercept calls for debugging, telemetry, or policy enforcement
- Future relocations or refactoring require updating scripts themselves

### Option B: Wrapper Scripts

Convert `agentcore/tools/*` to thin wrapper scripts that exec the real implementations.

**Pros:**
- Strong interface guarantee - canonical path is independent of implementation location
- Can enforce consistent environment, flags, and behavior across all tools
- Clear separation of interface (stable) vs implementation (can move/refactor)
- Single place to add consistent logging, telemetry, or error handling
- Scripts in `scripts/` don't need to be symlink-aware
- Future-proof for potential script relocations or reorganization
- Can version the interface independently from implementation

**Cons:**
- Additional maintenance overhead (N wrapper scripts to keep in sync)
- Indirection layer adds conceptual complexity
- Must exec correctly to preserve signals, exit codes, and stdio
- Wrappers could get out of sync with underlying scripts if not careful
- Slightly more complex to trace execution path during debugging
- Initial work to create N wrapper scripts

### Option C: Hybrid Approach

Use wrappers for complex/critical scripts, symlinks for simple utilities.

**Pros:**
- Pragmatic - apply engineering effort where it matters most
- Simple scripts get simple solution (symlinks)
- Complex scripts get interface layer benefits

**Cons:**
- Inconsistent interface - users must know which is which
- More complex mental model
- Maintenance burden of tracking which approach applies where

## Consequences

### If Option A (Pure Symlinks)

- Keep current symlink-based approach
- All coordination scripts must implement symlink-aware path resolution
- Recommended: Create shared `scripts/lib/paths.sh` library for DRY path resolution
- Scripts own their initialization logic
- Interface stability depends on script stability
- Phase 3 cleanup work is minimal (just verify symlinks)

### If Option B (Wrapper Scripts)

- Create N wrapper scripts in `agentcore/tools/` (one per coordination tool)
- Each wrapper execs the real script in `scripts/`
- Wrapper template handles common setup (env, logging, error handling)
- Stronger interface contract and stability guarantee
- More upfront work but better long-term maintainability
- Phase 3 includes wrapper creation and testing work

### If Option C (Hybrid)

- Document criteria for when to use wrappers vs symlinks
- Maintain both patterns in parallel
- Risk of inconsistency and confusion

## Status

**Proposed** - Deferred to Phase 3 planning discussion.

Phase 2 works with either approach. The current symlink-aware path resolution (using Python's `os.path.realpath()`) in coordination scripts provides adequate functionality for Phase 2 completion.

This ADR frames the decision space for future Phase 3 work. The actual decision should be made based on:
- Experience from Phase 2 usage
- Feedback from users of the canonical interface
- Maintenance burden observed with symlink-aware scripts
- Future requirements for telemetry, policy, or interface evolution

## References

- Phase 1: Created `agentcore/` structure with outward symlinks
- Phase 2: Made `agentcore/` authoritative, flipped symlinks inward
- Phase 3: Complete cleanup and canonical interface hardening
- Related bead: bd-1ip (Fix coordination scripts to be symlink-aware)
