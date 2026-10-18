.pragma library

// Parse collector JSON output safely
function parseGitOutput(stdoutText) {
  var emptyState = {
    repos: [],
    totalCount: 0,
    dirtyCount: 0,
    syncCount: 0,
    cleanCount: 0,
    errorCount: 0,
    attentionCount: 0
  };

  if (!stdoutText || !stdoutText.trim()) return emptyState;

  try {
    var data = JSON.parse(stdoutText.trim());
    return {
      repos: data.repos || [],
      totalCount: data.totalCount || 0,
      dirtyCount: data.dirtyCount || 0,
      syncCount: data.syncCount || 0,
      cleanCount: data.cleanCount || 0,
      errorCount: data.errorCount || 0,
      attentionCount: data.attentionCount || 0
    };
  } catch (e) {
    return emptyState;
  }
}

// Color mapping for repository badges and status
function statusBadgeColor(repo, foreground, accent, urgent, dim) {
  if (repo.isError) return urgent;
  if (repo.isDirty || repo.hasSync) return accent;
  return dim;                          // Clean
}

// Status text summary for repo
function statusSummary(repo) {
  if (repo.isError) return repo.error || "Git error";
  var parts = [];
  if (repo.ahead > 0) parts.push("↑" + repo.ahead);
  if (repo.behind > 0) parts.push("↓" + repo.behind);
  if (repo.staged > 0) parts.push("●" + repo.staged);
  if (repo.unstaged > 0) parts.push("*" + repo.unstaged);
  if (repo.untracked > 0) parts.push("?" + repo.untracked);
  if (parts.length === 0) return "Clean";
  return parts.join(" ");
}
