# Screen Agent Guide

Screen is a native tvOS Jellyfin client built from Swiftfin foundations.
This file is the entry point and map; deeper documents are loaded only as needed.

## Instruction priority

1. The current explicit user task.
2. This `AGENTS.md`.
3. Relevant repository documentation.
4. Existing implementation where documentation is silent.

Current-task requirements win over stale guidance. Describe disagreements between
implementation and product intent; do not silently turn a bug into a specification.
Within repository docs, current Screen contracts in `docs/` take precedence over
legacy `Documentation/` guidance. Implementation descriptions are observations,
not new product requirements or authorization to fix unrelated discrepancies.

## Read the relevant map

Start with [ARCHITECTURE.md](ARCHITECTURE.md) when ownership is unfamiliar.
Select only the documents needed for the task:

| Task | Read |
| --- | --- |
| Product scope | [Product principles](docs/PRODUCT.md) |
| UI or remote interaction | [Design conventions](docs/DESIGN.md) |
| Validation or build failure | [Quality and build commands](docs/QUALITY.md) |
| Workflow or substantial planning | [Codex workflow](docs/CODEX_WORKFLOW.md) |
| Navigation or dismissal | [Navigation contract](docs/product-specs/navigation.md), [implementation](docs/design-docs/navigation-stack.md) |
| Focus, remote input, screen transitions, or dismissal | [Authoritative tvOS focus/navigation contract](docs/design-docs/focus-navigation-contract.md), plus the owning product spec and implementation map |
| Home content | [Home](docs/product-specs/home.md), [Continue Watching](docs/product-specs/continue-watching.md) |
| Episode details | [Episode Details](docs/product-specs/episode-details.md) |
| Playback | [Playback contract](docs/product-specs/playback.md), [lifecycle](docs/design-docs/playback-lifecycle.md) |
| Play Next | [Play Next](docs/product-specs/play-next.md) |
| Focus | [Restoration contract](docs/product-specs/focus-restoration.md), [focus system](docs/design-docs/focus-system.md) |
| Models, services, watched state | [State management](docs/design-docs/state-management.md) |
| Ongoing or deferred work | [Active plans](docs/exec-plans/active/), [tech debt](docs/exec-plans/tech-debt.md) |

Do not load this entire table's destinations for every task.
Follow further links only when needed to answer the task; links are not a reading checklist.

For any tvOS task involving focus, remote input, screen transitions, menus, or
dismissal, consult [the focus/navigation contract](docs/design-docs/focus-navigation-contract.md)
as the authoritative app-wide directional and restoration reference. It separates
intended behavior from observed implementation and unresolved runtime evidence; use
the linked product spec for product intent and implementation docs/source for current
ownership.

## Focus and navigation contract discipline

`docs/design-docs/focus-navigation-contract.md` is the source of truth for expected
tvOS focus, navigation, Back behavior, restoration, and layered-surface behavior.

By default, treat this contract as read-only. Do not edit it merely because the
implementation differs from it; an implementation/contract mismatch is a regression
unless Jamie explicitly requested that behavior change. Update the contract only when
Jamie explicitly requests a behavior change and explicitly authorizes updating the
contract for that change.

Before editing any task that changes UI structure, focusable controls, navigation,
shelf/card geometry, route hierarchy, overlays, Details screens, Settings, Home,
Search, libraries, or playback surfaces:

1. Read the relevant contract section.
2. Identify the documented behaviors that could be affected.
3. Preserve those behaviors unless the task explicitly changes them.

After implementation:

1. Runtime-test the affected contract paths on the Apple TV simulator where practical.
2. Report each relevant behavior as `PASS`, `FAIL`, or `UNVERIFIED`.
3. Do not call the task complete if a relevant contract behavior fails.
4. If runtime verification is not possible, state exactly what remains unverified.

Run only the relevant regression checks; do not broaden testing to unrelated app areas.
When applicable, check initial focus, directional focus boundaries, exact target
restoration, deterministic fallback, one-layer-at-a-time Back dismissal, focusability
of hidden/inactive controls, parent context across child routes/surfaces, return from a
child to the expected control/card, at most one navigation-layer transition per remote
press, and the absence of delay-based corrective focus jumps.

When Jamie explicitly requests a behavior change that supersedes the existing
contract, update both implementation and contract. Describe the new expected user
behavior in the contract, not implementation details. Everything outside that
explicitly changed behavior remains authoritative and must still pass regression
testing.

## Scope discipline

Make the smallest coherent change that solves the task.

- Do not refactor unrelated code or rename unrelated types/files.
- Do not rewrite working systems or add speculative abstractions.
- Do not change unrelated product behavior.
- Preserve existing uncommitted work; inspect the diff before and after edits.
- Keep work scoped to Screen, the tvOS Jellyfin application; preserve iOS behavior unless asked otherwise.

## Investigation

Trace the relevant call path and state ownership before editing. Use relevant docs as
entry points, then identify the smallest responsible set of files. Stop broad
exploration once that set is known; prefer the existing mechanism over a parallel one.

## Two-pass rule

For a non-crashing UI or behavioral bug, allow at most two focused implementation passes.
After two unsuccessful passes, stop expanding the fix. Record useful evidence in
[tech debt](docs/exec-plans/tech-debt.md) when appropriate and move to other requested work.
Report the unresolved behavior; do not claim completion of a failed fix.
Crashes, data corruption, introduced build failures, and severe regressions may
exceed this limit when necessary to restore a working state.

## Verification

Use [QUALITY.md](docs/QUALITY.md) to select proportional verification.
Prefer focused checks; do not repeatedly run broad suites without new changes,
a failure, or a concrete unresolved concern. Avoid tests that duplicate implementation
or exist solely to inflate coverage. A build does not prove tvOS focus behavior.
For runtime work, physical Apple TV behavior is authoritative. See
[QUALITY.md](docs/QUALITY.md) for focus, scrolling, playback, and performance validation.

## Model roles and delegation

Use GPT-6 Luna (`gpt-6-luna`) as Screen's default lead and orchestrator. The lead
plans and delegates, maintains project context, integrates and reviews returned
changes, and decides whether escalation is warranted. The lead may handle small
changes directly; delegate implementation when doing so is more efficient.

Project-scoped agent definitions live in `.codex/agents/`:

- `screen_worker` uses GPT-6.1 Terra (`gpt-6.1-terra`) at medium reasoning for
  Swift/SwiftUI implementation, UI changes, refactors, routine bug fixes, semantic
  themes and tokens, sidebar animations, and visual adjustments. Keep changes
  focused and return changed files plus verification results to the lead.
- `screen_explorer` uses GPT-6 Luna at low reasoning for repository searches,
  call-chain tracing, quick diagnostics, and lightweight investigation. It does
  not edit files.
- `screen_escalation_sol` uses GPT-6.1 Sol for difficult architecture decisions,
  persistent lifecycle bugs, complex playback or focus issues, and targeted
  follow-up when a normal implementation pass is stuck.
- `screen_escalation_astra` uses GPT-6 Astra for the hardest root causes and
  cross-cutting decisions. Escalation is deliberate, not automatic; pass the
  concrete failure and prior findings rather than restarting the whole task.
- `screen_worker_luna_fallback` uses GPT-6 Luna at medium reasoning only when
  Codex cannot select Terra. State that fallback clearly; never report the Luna
  fallback as a Terra run.

Use one implementation worker by default. A second concurrent subagent is allowed
only for genuinely independent, bounded work that does not overlap the worker's
edits. Keep delegated prompts concise and scoped. Before delegating and in the final
report, identify the agent role and model that actually handled the work; distinguish
the configured model from the model actually invoked if selection could not be
verified. The lead integrates and reviews all returned changes.

Do not add model or reasoning recommendations to normal task prompts; use these
project defaults unless the user explicitly asks otherwise. Preserve the two-pass
limit for stubborn non-crashing UI bugs and all Screen focus, navigation, playback,
and presentation behavior. Follow [QUALITY.md](docs/QUALITY.md): no automatic Xcode
builds for routine changes, review the diff, and run `git diff --check`. Jamie
performs physical Apple TV runtime verification when needed.

## Completion

Confirm the requested behavior was addressed and inspect the affected flow for regressions.
Report what changed, verification performed, and material unresolved limits concisely.
Update the owning document when a task changes a stable contract or ownership boundary.
Keep product intent in product specs and implementation mechanics in design docs.
