## Repository-Relative Markdown Links Rule

When creating, editing, or linking files inside repository documentation (e.g. `README.md`, guides, markdown docs):
- Always use repository-relative markdown paths (e.g., `README.fa.md`, `DEPLOYMENT.md`, `./docs/guide.md`) for all internal links, anchors, and images.
- Never use absolute local filesystem paths or `file:///` URLs in repository markdown files, ensuring all links remain fully functional on GitHub and remote repositories.
