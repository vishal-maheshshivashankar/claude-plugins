<!-- code-review-local: append this block to the target repo's .github/copilot-instructions.md -->
## Local code review (code-review-local)

When asked to review an MR/PR (by URL, ID, or pasted description) or the local branch's
changes, and the request is for a **local-only review**, follow
`.github/prompts/code-review-local.prompt.md` (or run `/code-review-local` in Copilot Chat).
That flow never posts a comment, review, or approval back to the MR/PR — it only reports
findings in chat. Do not submit a PR review, post a comment, or approve/request-changes as a
side effect of this review unless the user separately and explicitly asks you to.
