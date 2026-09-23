#!/usr/bin/env bash
# Git/GitLab/GitHub utility script for local-only MR/PR review.
# Adapted from robin's .claude/skills/code-review-dev/scripts/git-utils.sh:
# same clone/review/summary commands, generalized to also accept GitHub PR
# URLs (via `gh`) alongside GitLab MR URLs (via `glab`). This script never
# posts anything anywhere — it only fetches metadata and produces a local
# diff for the calling skill to review and print in-chat.
#
# Usage: git-utils.sh <command> [args...]
#
# Commands:
#   clone       Clone a repo and optionally checkout an MR/PR branch
#   review      Create a worktree + diff for MR/PR review (when already in repo)
#   summary     Print MR/PR summary, comments, and related issues

set -euo pipefail
trap 'echo "Error on line $LINENO (exit $?)" >&2' ERR

WORKSPACE="${WORKSPACE:-$HOME/workspace}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: git-utils.sh <command> [args...]

Commands:
  clone <repo-url> [mr-or-pr-link]   Clone repo, optionally checkout MR/PR branch
  clone <mr-or-pr-link>              Clone repo derived from link, checkout branch
  review <MR-ID|MR-URL|PR-URL>       Worktree + diff for review (inside repo)
  summary <MR-ID|MR-URL|PR-URL>      Print summary, comments, related issues

Bare numeric IDs are assumed to be GitLab MR IIDs (resolved via `glab` against
the current repo's remote). GitHub PRs must be passed as a full URL
(https://github.com/<owner>/<repo>/pull/<number>) since a bare number is
ambiguous between the two providers.
EOF
  exit 1
}

repo_name_from_url() {
  basename "$1" .git
}

# ---------------------------------------------------------------------------
# Link parsing / provider detection
# ---------------------------------------------------------------------------

# Sets PROVIDER=gitlab|github and, for gitlab: MR_HOST/MR_PROJECT/MR_IID;
# for github: GH_OWNER/GH_REPO/GH_NUMBER.
parse_link() {
  local link="$1"
  if [[ "$link" =~ ^https?://([^/]+)/(.+)/-/merge_requests/([0-9]+) ]]; then
    PROVIDER="gitlab"
    MR_HOST="${BASH_REMATCH[1]}"
    MR_PROJECT="${BASH_REMATCH[2]}"
    MR_IID="${BASH_REMATCH[3]}"
  elif [[ "$link" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
    PROVIDER="github"
    GH_OWNER="${BASH_REMATCH[1]}"
    GH_REPO="${BASH_REMATCH[2]}"
    GH_NUMBER="${BASH_REMATCH[3]}"
  else
    echo "Error: Invalid MR/PR link format: $link" >&2
    echo "Expected: https://<host>/<project>/-/merge_requests/<id> (GitLab)" >&2
    echo "       or: https://github.com/<owner>/<repo>/pull/<number> (GitHub)" >&2
    exit 1
  fi
}

is_link() {
  [[ "$1" =~ merge_requests/[0-9]+ ]] || [[ "$1" =~ ^https?://github\.com/[^/]+/[^/]+/pull/[0-9]+ ]]
}

repo_url_from_link() {
  if [[ "$PROVIDER" == "gitlab" ]]; then
    echo "https://${MR_HOST}/${MR_PROJECT}.git"
  else
    echo "https://github.com/${GH_OWNER}/${GH_REPO}.git"
  fi
}

# Extract numeric MR ID from a GitLab URL or use directly (bare ID = GitLab)
normalize_mr_id() {
  local arg="$1"
  if [[ "$arg" =~ /merge_requests/([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$arg"
  fi
}

# ---------------------------------------------------------------------------
# Shared: print GitLab MR summary, comments, and related issues
# Args: MR_ID [--repo PROJECT]
# ---------------------------------------------------------------------------

print_mr_summary() {
  local mr_id="$1"; shift
  local repo_flag=()
  if [[ $# -ge 2 && "$1" == "--repo" ]]; then
    repo_flag=(--repo "$2")
  fi

  local mr_json
  mr_json=$(glab mr view "$mr_id" "${repo_flag[@]}" --comments --output json)

  local title state source target milestone is_draft labels changes conflicts description author url repo_url assignees reviewers pipeline
  title=$(jq -r '.title' <<< "$mr_json")
  state=$(jq -r '.state' <<< "$mr_json")
  source=$(jq -r '.source_branch' <<< "$mr_json")
  target=$(jq -r '.target_branch' <<< "$mr_json")
  milestone=$(jq -r '.milestone.title' <<< "$mr_json")
  is_draft=$(jq -r '.draft' <<< "$mr_json")
  labels=$(jq -r '.labels[]' <<< "$mr_json")
  changes=$(jq -r '.changes_count' <<< "$mr_json")
  conflicts=$(jq -r '.has_conflicts' <<< "$mr_json")
  description=$(jq -r '.description // "(no description)"' <<< "$mr_json")
  author=$(jq -r '.author.username' <<< "$mr_json")
  url=$(jq -r '.web_url' <<< "$mr_json")
  repo_url=$(sed "s|/-/merge_requests/.*||" <<< "$url")
  assignees=$(jq -r '[.assignees[]?.username] | join(", ")' <<< "$mr_json")
  reviewers=$(jq -r '[.reviewers[]?.username] | join(", ")' <<< "$mr_json")
  pipeline=$(jq -r '.head_pipeline.status // "none"' <<< "$mr_json")

  echo "=== MR !${mr_id} SUMMARY ==="
  echo "Title:       $title"
  echo "Author:      $author"
  echo "Assignees:   ${assignees:-none}"
  echo "Reviewers:   ${reviewers:-none}"
  echo "Labels:      $labels"
  echo "Milestone:   $milestone"
  echo "Pipeline:    $pipeline"
  echo "Changes:     $changes"
  echo "Conflicts:   $conflicts"
  echo "State:       $state  |  Draft: $is_draft"
  echo "Branch:      $source -> $target"
  echo "URL:         $url"
  echo "Repo:        $repo_url"
  echo ""
  echo "Description:"
  printf '%s\n' "$description"
  echo ""

  echo "=== MR COMMENTS ==="
  echo ""
  local comments
  comments=$(jq -r '.Discussions[]?.notes[]? | select(.system == false) | "[\(.author.username) commented at \(.created_at)]\n\(.body)\n"' <<< "$mr_json" 2>/dev/null || true)
  if [[ -z "$comments" ]]; then
    echo "(no comments yet)"
  else
    printf '%s\n' "$comments"
  fi
  echo ""

  echo "=== RELATED ISSUES ==="
  echo ""

  local issue_ids=""

  local api_issues
  api_issues=$(glab mr issues "$mr_id" "${repo_flag[@]}" 2>/dev/null || true)
  if [[ -n "$api_issues" ]]; then
    issue_ids=$(echo "$api_issues" | grep -oE '[0-9]+' | head -20 || true)
  fi

  local branch_id
  branch_id=$(printf '%s' "$source" | grep -oE '[0-9]+' | head -1 || true)
  if [[ -n "$branch_id" ]]; then
    issue_ids=$(printf "%s\n%s" "$issue_ids" "$branch_id")
  fi

  local desc_ids
  desc_ids=$(printf '%s\n' "$description" | grep -oE '#[0-9]+' | tr -d '#' || true)
  if [[ -n "$desc_ids" ]]; then
    issue_ids=$(printf "%s\n%s" "$issue_ids" "$desc_ids")
  fi

  local unique_ids
  unique_ids=$(echo "$issue_ids" | grep -E '^[0-9]+$' | sort -u || true)

  if [[ -z "$unique_ids" ]]; then
    echo "(no linked issues found)"
  else
    echo "$unique_ids" | while read -r iid; do
      echo "--- Issue #$iid ---"
      glab issue view "$iid" "${repo_flag[@]}" --comments 2>/dev/null || echo "  (could not fetch issue #$iid)"
      echo ""
    done
  fi
  echo ""

  _STATE="$state"
  _IS_DRAFT="$is_draft"
  _SOURCE="$source"
  _TARGET="$target"
}

# ---------------------------------------------------------------------------
# Shared: print GitHub PR summary, comments, and related issues
# Args: owner repo number
# ---------------------------------------------------------------------------

print_pr_summary() {
  local owner="$1" repo="$2" number="$3"
  local repo_slug="${owner}/${repo}"

  local pr_json
  pr_json=$(gh pr view "$number" --repo "$repo_slug" \
    --json title,state,headRefName,baseRefName,milestone,isDraft,labels,changedFiles,mergeable,body,author,url,assignees,reviewRequests,statusCheckRollup,comments)

  local title state source target milestone is_draft labels changes conflicts description author url assignees reviewers pipeline
  title=$(jq -r '.title' <<< "$pr_json")
  state=$(jq -r '.state' <<< "$pr_json")
  source=$(jq -r '.headRefName' <<< "$pr_json")
  target=$(jq -r '.baseRefName' <<< "$pr_json")
  milestone=$(jq -r '.milestone.title // "none"' <<< "$pr_json")
  is_draft=$(jq -r '.isDraft' <<< "$pr_json")
  labels=$(jq -r '[.labels[]?.name] | join(", ")' <<< "$pr_json")
  changes=$(jq -r '.changedFiles' <<< "$pr_json")
  conflicts=$(jq -r 'if .mergeable == "CONFLICTING" then "true" else "false" end' <<< "$pr_json")
  description=$(jq -r '.body // "(no description)"' <<< "$pr_json")
  author=$(jq -r '.author.login' <<< "$pr_json")
  url=$(jq -r '.url' <<< "$pr_json")
  assignees=$(jq -r '[.assignees[]?.login] | join(", ")' <<< "$pr_json")
  reviewers=$(jq -r '[.reviewRequests[]?.login] | join(", ")' <<< "$pr_json")
  pipeline=$(jq -r '[.statusCheckRollup[]?.state] | join(", ")' <<< "$pr_json")

  echo "=== PR #${number} SUMMARY ==="
  echo "Title:       $title"
  echo "Author:      $author"
  echo "Assignees:   ${assignees:-none}"
  echo "Reviewers:   ${reviewers:-none}"
  echo "Labels:      ${labels:-none}"
  echo "Milestone:   $milestone"
  echo "Checks:      ${pipeline:-none}"
  echo "Changes:     $changes files"
  echo "Conflicts:   $conflicts"
  echo "State:       $state  |  Draft: $is_draft"
  echo "Branch:      $source -> $target"
  echo "URL:         $url"
  echo "Repo:        https://github.com/${repo_slug}"
  echo ""
  echo "Description:"
  printf '%s\n' "$description"
  echo ""

  echo "=== PR COMMENTS ==="
  echo ""
  local comments
  comments=$(jq -r '.comments[]? | "[\(.author.login) commented]\n\(.body)\n"' <<< "$pr_json" 2>/dev/null || true)
  if [[ -z "$comments" ]]; then
    echo "(no comments yet)"
  else
    printf '%s\n' "$comments"
  fi
  echo ""

  echo "=== RELATED ISSUES ==="
  echo ""
  local desc_ids unique_ids
  desc_ids=$(printf '%s\n' "$description" | grep -oE '#[0-9]+' | tr -d '#' || true)
  unique_ids=$(echo "$desc_ids" | grep -E '^[0-9]+$' | sort -u || true)

  if [[ -z "$unique_ids" ]]; then
    echo "(no linked issues found)"
  else
    echo "$unique_ids" | while read -r iid; do
      echo "--- Issue #$iid ---"
      gh issue view "$iid" --repo "$repo_slug" --comments 2>/dev/null || echo "  (could not fetch issue #$iid)"
      echo ""
    done
  fi
  echo ""

  # gh's state is OPEN/CLOSED/MERGED; normalize to lowercase so callers can
  # compare uniformly against the GitLab path's lowercase values.
  _STATE=$(tr '[:upper:]' '[:lower:]' <<< "$state")
  _IS_DRAFT="$is_draft"
  _SOURCE="$source"
  _TARGET="$target"
}

# ---------------------------------------------------------------------------
# Command: clone
# ---------------------------------------------------------------------------

cmd_clone() {
  [[ $# -lt 1 ]] && usage

  local repo_url link=""

  if [[ $# -eq 1 ]] && is_link "$1"; then
    link="$1"
    parse_link "$link"
    repo_url=$(repo_url_from_link)
    echo "Derived repo URL from link: ${repo_url}"
  elif [[ $# -eq 1 ]]; then
    repo_url="$1"
  else
    repo_url="$1"
    link="$2"
  fi

  local repo_name repo_dir
  repo_name=$(repo_name_from_url "$repo_url")
  repo_dir="${WORKSPACE}/${repo_name}"

  if [[ -d "$repo_dir/.git" ]]; then
    echo "Repo already exists at ${repo_dir}, skipping clone."
    cd "$repo_dir"
    git fetch origin --prune --quiet
  else
    echo "Cloning ${repo_url} into ${repo_dir}..."
    mkdir -p "$WORKSPACE"
    git clone --depth 1 "$repo_url" "$repo_dir" --quiet
    cd "$repo_dir"
  fi

  if [[ -n "$link" ]]; then
    [[ -z "${PROVIDER:-}" ]] && parse_link "$link"

    if [[ "$PROVIDER" == "gitlab" ]]; then
      echo "Checking out MR !${MR_IID} from project ${MR_PROJECT}..."
      echo ""
      print_mr_summary "$MR_IID" --repo "$MR_PROJECT"
    else
      echo "Checking out PR #${GH_NUMBER} from ${GH_OWNER}/${GH_REPO}..."
      echo ""
      print_pr_summary "$GH_OWNER" "$GH_REPO" "$GH_NUMBER"
    fi

    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Working tree is dirty -- refusing to reset onto the review branch. Use 'review' instead." >&2
      exit 1
    fi
    git fetch origin "$_SOURCE" --quiet
    if git show-ref --verify --quiet "refs/heads/$_SOURCE"; then
      git checkout "$_SOURCE" --quiet
    else
      git checkout -b "$_SOURCE" "origin/$_SOURCE" --quiet
    fi
    git reset --hard "origin/$_SOURCE" --quiet
  fi

  echo "Done. Working directory: $(pwd)"
}

# ---------------------------------------------------------------------------
# Command: review
# ---------------------------------------------------------------------------

cmd_review() {
  local mr_arg="${1:-}"
  if [[ -z "$mr_arg" ]]; then
    echo "Usage: git-utils.sh review <MR-ID|MR-URL|PR-URL>"
    exit 1
  fi

  local review_id
  if is_link "$mr_arg"; then
    parse_link "$mr_arg"
    if [[ "$PROVIDER" == "gitlab" ]]; then
      review_id="$MR_IID"
      print_mr_summary "$review_id" --repo "$MR_PROJECT"
    else
      review_id="$GH_NUMBER"
      print_pr_summary "$GH_OWNER" "$GH_REPO" "$review_id"
    fi
  else
    PROVIDER="gitlab"
    review_id=$(normalize_mr_id "$mr_arg")
    print_mr_summary "$review_id"
  fi

  if [[ "$_STATE" == "closed" || "$_STATE" == "merged" ]]; then
    echo "Review target is $_STATE -- skipping review."
    exit 0
  fi

  if [[ "$_IS_DRAFT" == "true" ]]; then
    echo "Review target is a draft -- skipping review."
    exit 0
  fi

  git fetch origin "$_SOURCE" "$_TARGET" --quiet

  local worktree="/tmp/review-${PROVIDER}-${review_id}"
  if [[ -d "$worktree" ]]; then
    git worktree remove --force "$worktree" 2>/dev/null || true
  fi
  git worktree add "$worktree" "origin/$_SOURCE" --quiet

  local diff_file="/tmp/review-diff-${PROVIDER}-${review_id}.diff"
  git -C "$worktree" diff "origin/${_TARGET}...origin/${_SOURCE}" > "$diff_file"

  if [[ ! -s "$diff_file" ]]; then
    echo "No commits or changes found between '$_TARGET' and '$_SOURCE' -- skipping review."
    git worktree remove --force "$worktree"
    exit 0
  fi

  git worktree remove --force "$worktree" 2>/dev/null || true

  echo "=== READY FOR REVIEW ==="
  echo "Diff: $diff_file  ($(wc -l < "$diff_file") lines)"
  echo "Read the diff file above to begin review."
}

# ---------------------------------------------------------------------------
# Command: summary
# ---------------------------------------------------------------------------

cmd_summary() {
  local mr_arg="${1:-}"
  if [[ -z "$mr_arg" ]]; then
    echo "Usage: git-utils.sh summary <MR-ID|MR-URL|PR-URL>"
    exit 1
  fi

  if is_link "$mr_arg"; then
    parse_link "$mr_arg"
    if [[ "$PROVIDER" == "gitlab" ]]; then
      print_mr_summary "$MR_IID" --repo "$MR_PROJECT"
    else
      print_pr_summary "$GH_OWNER" "$GH_REPO" "$GH_NUMBER"
    fi
  else
    local mr_id
    mr_id=$(normalize_mr_id "$mr_arg")
    print_mr_summary "$mr_id"
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  clone)   cmd_clone "$@" ;;
  review)  cmd_review "$@" ;;
  summary) cmd_summary "$@" ;;
  *)       usage ;;
esac
