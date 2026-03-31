# WezTerm Agent Session Signaling Plan

## Purpose

WezTerm already detects when a tab contains a Claude Code or OpenCode session.
What it cannot reliably infer from process inspection alone is whether the agent is:

1. actively working, or
2. paused and waiting for human input.

This plan defines a simple signaling contract so WezTerm can show three clear tab states:

- empty: no Claude/OpenCode session detected
- running: agent is present and actively working
- waiting: agent is present and waiting for the user

## Why This Is Needed

Foreground-process detection is enough to answer "is an agent present?"
It is not enough to answer "is the agent still working or is it waiting for me?"

For both Claude Code and OpenCode, the foreground process often remains the same while the agent is either thinking or waiting. That means WezTerm needs an explicit state signal from the agent side.

## What WezTerm Needs

WezTerm needs a pane-level signal that communicates session state changes in real time.

Recommended contract:

- user var name: `session_state`
- canonical values:
  - `running`
  - `waiting`
  - empty string to clear state on exit

WezTerm should treat those values as follows:

- no tracked agent process -> show no icon
- tracked agent process + no explicit waiting signal -> show running icon
- tracked agent process + `session_state=waiting` -> show waiting icon
- tracked agent process + `session_state=running` -> show running icon
- tracked agent exits -> clear icon and clear session state

## Current UI Contract

The current tab behavior should converge on:

- empty icon: no Claude/OpenCode detected
- play icon: Claude/OpenCode is active and in `running`
- waiting icon: Claude/OpenCode is active and in `waiting`

This keeps the UI simple and directly useful for attention management.

## Responsibility Split

### WezTerm side

WezTerm is responsible for:

- detecting whether Claude/OpenCode is present in the tab
- listening for pane state changes via `user-var-changed`
- mapping those state changes to the tab icon
- clearing stale state when the tracked process exits

WezTerm is not responsible for guessing when the agent wants user input.

### Claude / OpenCode side

Claude Code and OpenCode are responsible for sending state transitions.

Minimal expected behavior:

- send `session_state=running` when the agent starts or resumes work
- send `session_state=waiting` when the agent needs human input
- clear `session_state` when the session exits

The exact integration point can vary by tool:

- wrapper script
- hook
- plugin
- shell helper

The implementation detail is less important than honoring the contract consistently.

## Suggested Agent-Side Guidance

### Claude Code

Claude Code should emit:

- `running` when a session begins or resumes after user input
- `waiting` when it stops and expects the next user response
- empty value when the session ends

If Claude Code cannot emit those signals natively, use a thin wrapper or hook around the interactive session lifecycle.

### OpenCode

OpenCode should emit the same values:

- `running`
- `waiting`
- empty on exit

If OpenCode already has plugin or hook support around session lifecycle events, prefer that over process heuristics.

## Transport Recommendation

Use WezTerm user vars as the signaling path.

The implementation should send `session_state` to the current pane using the WezTerm `SetUserVar` escape sequence. On the WezTerm side, `user-var-changed` should remain the single source of truth for `running` vs `waiting`.

## Acceptance Criteria

- no icon when no Claude/OpenCode process is present
- running icon appears when Claude/OpenCode is active
- waiting icon appears when Claude/OpenCode is paused for user input
- switching between running and waiting works multiple times in the same session
- icon clears when the session exits
- behavior works independently per tab/pane

## Non-Goals

- inferring waiting state from subprocesses
- inferring waiting state from shell return alone
- building a larger plugin/config framework before this contract is proven

## Next Implementation Agent

The next agent should implement this contract end-to-end:

1. keep WezTerm as the receiver and UI renderer
2. add or polish the `user-var-changed` handling for `session_state`
3. add the minimal Claude/OpenCode-side signal sender
4. verify the three UI states with real sessions

The implementation should prioritize reliable signaling over clever detection.
