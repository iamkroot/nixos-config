---
name: brutal-review
description: >-
  Executes a ruthless, multi-perspective adversarial review on the current implementation plan
  or code diff. Activate this skill whenever the
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
> Always pass **paths by reference**. The subagent persona and instructions are maintained in [critic-prompt.md](critic-prompt.md) so the main chat prompt remains under ~40 tokens.

Spawn an isolated subagent using `invoke_subagent`:
- **TypeName**: `"self"` (or `"research"`)
- **Role**: `"Ruthless Architecture & Reliability Critic"`
- **Model**: `"inherit"` (or `"pro"` for complex systems)
- **Prompt**:
  ```text
  Execute the brutal review instructions located at file://<WORKSPACE>/.agents/skills/brutal-review/critic-prompt.md on target: file://<ABSOLUTE_PATH_TO_TARGET>. Write findings to file://<artifactDir>/brutal-review.md.
  ```

---

### Step 3: Deliver Verdict & Next Steps (Zero Chat Regurgitation)

> [!IMPORTANT]
> **DO NOT summarize, explain, or reprint findings tables in the chat response.**
> All findings live in the artifact. Regurgitating them burns 2,000–4,000 tokens and permanently bloats all subsequent chat turns.

When the subagent completes, output ONLY:
1. **Verdict**: `REJECT`, `REVISE`, or `PASS` with the subagent's one-line summary.
2. **Artifact Link**: `📄 **Review & Tweak Actions**: [brutal-review.md](file://<artifactDir>/brutal-review.md)`
3. **Interactive Prompt**:
   *"You can edit decisions/notes directly in [brutal-review.md](file://<artifactDir>/brutal-review.md) and reply 'Apply my tweaks', or tell me your adjustments in chat."*
