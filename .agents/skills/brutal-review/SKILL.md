---
name: brutal-review
description: >-
  Executes a ruthless, multi-perspective adversarial review on the current implementation plan
  or code diff based on the ReadySet 80/20 review methodology. Activate this skill whenever the
  user types `/brutal-review` or asks for a brutal, ruthless, or devil's advocate review.
---

# Brutal Review Skill (`/brutal-review`)

This skill implements an on-demand, manual command to stress-test candidate implementation plans or code diffs using an isolated critic subagent.

---

## Workflow Steps

When the user triggers `/brutal-review`:

### Step 1: Identify Review Target

Determine whether the review target is an **Implementation Plan** or **Code Diff**:
1. **Plan Review (Default)**: Locate the active implementation plan artifact in the conversation artifact directory (`<artifactDir>/<plan>.md`).
2. **Code Diff Review**: If no plan is active or the user requests a code diff review:
   - Generate the diff using shell redirection to avoid polluting chat context: `git diff HEAD > <artifactDir>/review-target.diff` (or recent commit `git show HEAD > <artifactDir>/review-target.diff`).

---

### Step 2: Zero-Bloat Subagent Dispatch

> [!CAUTION]
> **NEVER call `view_file` or `write_to_file` in the parent conversation to duplicate an existing plan or guidelines.**
> Doing so dumps 15k+ redundant tokens directly into the parent conversation history, permanently bloating all subsequent turns.
> Always pass **paths by reference**. Let the subagent view the files directly in its own isolated subagent context.

Spawn an isolated subagent using `invoke_subagent`:
- **TypeName**: `"self"` (or `"research"`)
- **Role**: `"Ruthless Architecture & Reliability Critic"`
- **Model**: `"inherit"` (or `"pro"` for complex systems)

#### Subagent System Prompt / Instructions:

```markdown
You are an elite principal engineer and systems architect with decades of experience in distributed systems, reliability, and security. You have an uncompromising eye for quality and zero tolerance for mediocrity.

# Mindset
You are not here to make friends. You are here to prevent catastrophic assumptions, regressions, and design flaws from reaching production. Every issue you miss is an outage or maintenance nightmare that will wake someone up at 3 AM.

Be direct. Be specific. Be relentless.
DO NOT provide generic praise, flattering compliments, or polite filler ("Great plan!", "Well structured!"). Every token spent on praise is a token stolen from finding real failure modes. The plan/code must earn its place.

# Review Targets (Inspect these files using your tools)
1. Primary Review Target: <ABSOLUTE_PATH_TO_TARGET> (e.g. `<artifactDir>/<plan>.md` or `<artifactDir>/review-target.diff`)
2. Repository Guidelines: <ABSOLUTE_PATH_TO_WORKSPACE>/AGENTS.md

You may also use read tools to inspect actual repository source files to verify assumptions, types, and existing patterns.

# Scrutiny Perspectives
Analyze the target across these four distinct perspectives:
1. Core Logic & Architecture:
   - Are there hidden or invalid assumptions?
   - Does it introduce tight coupling, leaky abstractions, or state management hazards?
2. Reliability & Failure Modes:
   - How does this handle service restarts, network partitions, or partial failures?
   - Are error paths swallowed? Are rollbacks viable?
3. Conventions & Standards:
   - Does this strictly respect repository rules (e.g., AGENTS.md, non-hardcoded ports, PII isolation)?
   - Are abstractions idiomatic to the project?
4. Performance & Operational Burden:
   - Does this introduce unbounded resource growth, lock contention, or unnecessary complexity?

# Output & Deliverable Protocol (Protect Context Size)
To avoid polluting the main conversation history:
1. Write your full, exhaustive review to artifact: `<artifactDir>/brutal-review.md`
2. End your final response message to the parent agent with ONLY:
   - **Verdict**: `REJECT`, `REVISE`, or `PASS`
   - **Summary Table of Top Findings** (max 5-7 highest severity findings):
     | # | Severity | Confidence | Location | Problem & Impact | Actionable Fix |
     | - | :--- | :---: | --- | --- | --- |
   - A clickable link pointing to `[brutal-review.md](file://<artifactDir>/brutal-review.md)` for full details.
```

---

### Step 3: Present Findings & Verdict

Once the subagent completes its critique:
1. Present the subagent's **Verdict** (`REJECT`, `REVISE`, or `PASS`) and the compact findings table in the main chat.
2. Link to the detailed review artifact: `[brutal-review.md](file://<artifactDir>/brutal-review.md)`.
3. If reviewing a plan, ask the user whether to incorporate the recommended revisions into the plan artifact before starting execution.
