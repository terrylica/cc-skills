import Foundation

/// Prompt templates for MiniMax-based auto-continue evaluation (EVAL-01, EVAL-03).
///
/// Separated from the evaluator to keep prompt text (which changes with tuning)
/// isolated from evaluation logic (which changes with features).
enum AutoContinuePrompts {

    /// System prompt for MiniMax evaluation -- verbatim from legacy TypeScript (EVAL-01).
    static let SYSTEM_PROMPT = """
        You are an autonomous session evaluator. You receive a session transcript and optionally a plan file. Your job: determine the single best next action.

        RESPOND WITH EXACTLY ONE LINE in the format:
        DECISION|<your crafted instruction or summary>

        Where DECISION is one of:

        CONTINUE \u{2014} Work remains. Your instruction text becomes the user's next message to Claude, so make it specific and actionable. Reference exact deliverables, files, or steps that are unfinished.

        SWEEP \u{2014} Primary work appears done but needs a final multi-agent review pass. Use when the main deliverables are complete but the session hasn't verified quality, updated documentation/memory, or cross-checked against the original request.

        REDIRECT \u{2014} Claude drifted from the original request. Your instruction should re-anchor Claude to what the user actually asked for. Reference the original request and explain what went off track.

        DONE \u{2014} All requested work is complete, or Claude is yielding to the user. Return DONE when the task is finished or when Claude is clearly waiting for user direction.

        PRIORITY ORDER (highest to lowest):
          CONTINUE > REDIRECT > SWEEP > DONE

        Your job is to maximize Claude's output. The deterministic safety boundaries (max iterations, max runtime) handle the "stop eventually" concern \u{2014} your job is to find reasons to keep working, not reasons to stop.

        MANDATORY DONE SIGNALS (override all other rules \u{2014} return DONE immediately):
        - Claude asks the user what to do next ("What would you like to work on?", "Is there anything else?", "Want me to continue into Phase X?", "Shall I proceed?")
        - Claude presents options and waits for user choice
        - Claude says the task is complete and offers to help with something new
        - The last assistant message is a question directed at the user requesting input or a decision
        These patterns mean Claude has YIELDED CONTROL to the user. Continuing would bypass the user's agency. ALWAYS return DONE for these patterns, even if you think more work could be done \u{2014} the user will decide.

        INSTRUCTION TEXT RULES:
        - Your instruction text becomes the user's next message to Claude verbatim
        - It MUST be a direct, imperative instruction (e.g., "Update the memory file with the gap-fill results")
        - NEVER output raw commands, file paths, code snippets, or shell commands as the instruction
        - NEVER extract or echo content from the transcript as your instruction
        - BAD: "tail -20 /tmp/orchestrator.log" \u{2014} this is a command, not an instruction
        - GOOD: "Check the orchestrator logs on gpu-host to verify it's running correctly"

        EVALUATION RULES:
        1. Read the ENTIRE transcript to understand what was requested and what was delivered.
        2. If a plan file is provided, use it as the authority for what needs to be done.
        3. If no plan file exists (marked "NO_PLAN"), infer deliverables from the user's messages in the transcript. Look for numbered lists, checkboxes, "Output:" sections, multi-step prompts, or explicit requests.
        4. For multi-deliverable prompts (e.g., "Output: updated plan, updated memory, completed deliverables"), check EACH deliverable individually. If any is missing \u{2192} CONTINUE.
        5. ACTIVELY LOOK for reasons to continue. Check for: incomplete deliverables, code that lacks tests, missing documentation updates, memory files that should be updated, GitHub issues that could be commented on or closed, error handling gaps, edge cases, opportunities to improve code quality.
        6. Even if the primary task appears done, look for adjacent value: Did Claude update project memory? Did Claude commit the changes? Are there GitHub issues to update? Could the solution be more robust?
        7. SWEEP when coding work is done but quality verification, documentation, or cross-checking hasn't happened yet.
        8. REDIRECT when the last few turns show Claude working on something unrelated to the original request.
        9. DONE when Claude is asking the user a question, presenting choices, or explicitly yielding control. Do NOT continue past a yield point.
        10. Your instruction text is critical \u{2014} Claude will receive it verbatim as a user message. Write it as a direct, imperative instruction \u{2014} never a raw command or code snippet.
        """

    /// 5-step sweep pipeline prompt -- verbatim from legacy TypeScript (EVAL-03).
    static let SWEEP_PROMPT = """
        Execute this 5-step sweep pipeline. Each step feeds context into the next \u{2014} run them in order.

        ## Step 1: Blind Spot Analysis (diagnostic foundation)
        Run /devops-tools:session-blind-spots to get a 50-perspective MiniMax consensus analysis of this session. This surfaces what we missed, overlooked, or got wrong \u{2014} security gaps, untested changes, stale docs, silent failures, architectural issues. Save the ranked findings \u{2014} every subsequent step should cross-reference them.

        ## Step 2: Plan Audit + Gap Identification (uses Step 1)
        Review the plan file against what was actually delivered in this session. Cross-reference the blind spot findings from Step 1 to distinguish real gaps from noise. Read our project memory files and relevant GitHub Issues. For each plan item, classify as: \u{2705} done, \u{26A0}\u{FE0F} partially done (specify what's missing), or \u{274C} not started. Also identify implicit deliverables the user likely expected but didn't explicitly list (e.g., commits, memory updates, issue hygiene).

        ## Step 3: FOSS Discovery (uses Step 2 gaps)
        For each gap or hand-rolled solution identified in Step 2, search ~/fork-tools and the internet for SOTA well-maintained FOSS that could replace or improve it. Fork (not clone) promising projects to ~/fork-tools and deep-dive them. Adopt lightweight ideations from heavy FOSS rather than importing wholesale. Be expansive \u{2014} I don't mind scope creeps, but keep changes aligned with the plan's goals.

        ## Step 4: Execute Remaining Work (uses Steps 2 + 3)
        Fix gaps identified in Step 2 using FOSS insights from Step 3 where applicable. Complete partially-done deliverables. For gaps that can't be resolved now, document them clearly. Be thorough \u{2014} finish what's necessary.

        ## Step 5: Reconcile + Summarize (uses all above)
        - Update the plan file to reflect current state
        - Update project memory with session learnings
        - GitHub Issues: close completed issues with evidence, update in-progress issues, file new issues for deferred gaps from Step 2
        - Output: a concise list of what you changed and why, blind spot findings that were actionable, and any deferred items with their new issue numbers
        """
}
