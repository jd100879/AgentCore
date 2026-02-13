# AgentCore Folder Structure Proposal

ChatGPT has provided a comprehensive folder structure proposal. Here's what you need to know:

## Proposed Directory Tree

```
agentcore/
  README.md
  docs/
    structure.md
    migration.md
  config/
    flywheel/
    agents/
    ntm/
    env.example
  schemas/
    mail/
    flywheel/
  runtime/
    pids/
    panes/
    sessions/
    logs/
    tmp/
  coordination/
    registry/
    profiles/
    workflows/
    active/
  mail/
    repo/
      inbox/
      outbox/
      processing/
      done/
      failed/
      dlq/
      _meta/
    tools/
  tools/
    scripts/
    lib/
  state/
    beads/
    notifications/
    disk/
    audit/
  integrations/
    mcp_agent_mail/
    flywheel_tools/
    beads_rust/
    beads_viewer/
    ntm/
  archive/
  review/
```

## Key Design Principles

1. **Lowercase only** - `agentcore/` not `AgentCore/` (reduces drift)
2. **No hidden dirs inside** - explicit directories, no `.agent-*` inside agentcore
3. **Single AGENTCORE_ROOT** - environment variable for all path resolution
4. **Clear separation**:
   - `config/` - declarative configuration only
   - `state/` - durable coordination state
   - `runtime/` - ephemeral (safe to wipe)
   - `integrations/` - symlinks to component directories

## Migration Plan (3 Phases)

### Phase 1: Non-Disruptive Bootstrap
- Create `agentcore/` alongside existing dirs (don't move anything yet)
- Add `AGENTCORE_ROOT` environment variable support
- Create symlinks under `agentcore/integrations/` to existing components
- Create `agentcore/mail/repo` as symlink to `$HOME/.mcp_agent_mail_local_repo`
- **Goal**: New structure exists, old structure still works

### Phase 2: Controlled Migration
- Move dotdirs into agentcore equivalents:
  - `.flywheel/` → `agentcore/config/flywheel/`
  - `.beads/` → `agentcore/state/beads/`
  - `.agent-profiles/` → `agentcore/coordination/profiles/`
- Keep old dotdirs as **symlinks** to new locations (backwards compat)
- Move runtime folders (pids/panes/tmp) into `agentcore/runtime/`
- Convert top-level `scripts/` to thin forwarders to `agentcore/tools/scripts/`
- **Goal**: Files moved, but old paths still resolve via symlinks

### Phase 3: Deprecation & Enforcement
- Update all scripts to use `AGENTCORE_ROOT` exclusively
- Add drift guard (CI check that fails if new dotdirs appear)
- Optionally migrate mail repo from `$HOME` into agentcore
- Remove legacy empty directories
- **Goal**: Clean structure, no legacy paths

### Rollback Strategy
- Phase 1: Just delete `agentcore/` (no files moved)
- Phase 2: Remove symlinks, restore from git
- Phase 3: Git revert or restore symlinks

## Investigation Results

I investigated ChatGPT's questions:

### ✅ 1. Hardcoded Paths
**Found**:
- 30 scripts reference `.beads/`
- 1 script references `.flywheel/` (start-orchestrator.sh)
- 30 scripts reference `.agent-*` patterns
- 6 files reference `mcp_agent_mail_local_repo`

**Key scripts affected**:
- `scripts/agent-mail-helper.sh`
- `scripts/agent-registry.sh`
- `flywheel_tools/scripts/core/agent-runner.sh`
- `beads_rust/` and `beads_viewer/` scripts

**Plan**: Phase 2 will add AGENTCORE_ROOT support to these scripts while keeping backward compat.

### ✅ 2. Symlinks on macOS
**Answer**: Yes, symlinks work fine on macOS. No issues expected.

### ✅ 3. Repository Root
**Confirmed**: Yes, `/Users/james/Projects/AgentCore/` is the repo root.
**Approach**: Create `agentcore/` alongside existing top-level dirs (preferred).

### ❓ 4. Mail Repo Location
**Question for you**: Is `$HOME/.mcp_agent_mail_local_repo/` required to stay outside the repo?
- **Reasons to keep outside**: Multi-repo use, security, performance?
- **Option**: Migrate into `agentcore/mail/repo/` in Phase 3?

ChatGPT suggests starting with a symlink in Phase 1, then deciding later.

### ✅ 5. Capital `AgentCore/` Directory
**Confirmed**: The `AgentCore/` directory (capital A) is **NOT referenced anywhere** in the codebase.
- It only contains `.gitattributes`
- Safe to deprecate/delete

**Plan**: Move `.gitattributes` to repo root (or delete if not needed), remove `AgentCore/`.

### ❓ 6. Component Relative Paths
**Question for you**: Do `beads_rust`, `ntm`, `flywheel_tools` expect relative paths from repo root?
- ChatGPT proposes symlinks under `agentcore/integrations/*` pointing to existing top-level dirs
- Need to verify this won't break build scripts or imports

### ❓ 7. Agent Name Casing
**Question for you**: Should agent names be lowercase or preserve case?
- **Current**: Mixed case (e.g., `TopazDeer`, `AgentA`)
- **ChatGPT recommends**: Lowercase for determinism (e.g., `topazdeer/`, `agenta/`)
- **Tradeoff**: Breaking change vs long-term consistency

## What I Need From You

Before proceeding with ChatGPT, please answer:

1. **Mail repo location**: Keep at `$HOME/.mcp_agent_mail_local_repo/` or OK to migrate into repo later?

2. **Component symlinks**: Are you comfortable with `agentcore/integrations/beads_rust` → `../../beads_rust` symlinks? Or prefer physical moves?

3. **Agent name casing**: Lowercase (recommended) or preserve case (current)?

4. **Phase 1 scope**: Should I start with Phase 1 (non-disruptive bootstrap), or do you want to review/adjust the plan first?

5. **Capital AgentCore/**: Confirm I can delete it after moving `.gitattributes`?

## Next Steps

Once you answer these questions, I'll:
1. Share your answers with ChatGPT
2. Get refined implementation plan for Phase 1
3. Create beads for the folder structure work
4. **Then** move to agent mail system (Phase 2+ of overall project)

The goal is: **Clean folder structure first, then make mail system deterministic.**
