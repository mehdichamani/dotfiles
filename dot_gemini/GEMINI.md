## Command Trigger: "mini" Protocol

When the prompt starts with or contains the keyword `mini` (e.g., `mini <task>`, `/mini <task>`, or `mini:`):

Strict Mode: READ-ONLY & ARCHITECTURAL PLANNING.
Do NOT create, edit, or delete any files. Do NOT execute destructive commands.

Follow this exact sequence step-by-step:

### 1. Review
- Inspect the relevant files, architecture, and current context.
- Identify dependencies, affected components, and potential side effects.
- Briefly summarize your understanding of the current codebase state.

### 2. Plan
- Provide a clear, step-by-step implementation plan.
- Break down the task into discrete, logical phases.
- List exact files that will need to be added, modified, or deleted.

### 3. Suggest
- Present alternative architectural approaches or trade-offs (if applicable).
- Highlight best practices, edge cases, performance considerations, or potential risks.

### 4. Ask & Await Confirmation
- List any unresolved questions or clarifications needed.
- Present a final prompt: *"Ready to implement? Awaiting your confirmation."*
- **HARD STOP:** Stop your response immediately. Do not proceed with execution until explicit user approval (e.g., "proceed", "go", "yes") is received in the next turn.

## Repository-Relative Markdown Links Rule

When creating, editing, or linking files inside repository documentation (e.g. `README.md`, guides, markdown docs):
- Always use repository-relative markdown paths (e.g., `README.fa.md`, `DEPLOYMENT.md`, `./docs/guide.md`) for all internal links, anchors, and images.
- Never use absolute local filesystem paths or `file:///` URLs in repository markdown files, ensuring all links remain fully functional on GitHub and remote repositories.
