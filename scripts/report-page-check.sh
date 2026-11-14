#!/usr/bin/env bash
# Reports the result of the daily page check (scripts/check-page-hooks.swift) as GitHub issues.
# Used by .github/workflows/page-check.yml. Needs gh and jq, and GH_TOKEN with issues: write.
#
#   OUTCOME   ok, broken, blocked, session or failed (the check's exit status)
#   REPORT    the check's report.md
#   RUN_URL   the link to the workflow run
#
# Each kind of problem has one issue with its own label. While the issue is open, a new run
# adds a comment only when the problem changes (for a page change: when other hooks break).
# When the problem goes away, the run closes the issue.
set -euo pipefail

: "${OUTCOME:?}" "${REPORT:?}" "${RUN_URL:?}" "${GH_REPO:?}"

title_of() {
  case "$1" in
    page-change) echo "ChatGPT changed its page: Quick Chat's page hooks broke" ;;
    page-check-session) echo "Page check: renew the test account's session" ;;
    page-check-blocked) echo "Page check: chatgpt.com blocked the check" ;;
    *) echo "Page check: the check could not run" ;;
  esac
}
about_of() {
  case "$1" in
    page-change) echo "The daily page check found broken ChatGPT page hooks" ;;
    page-check-session) echo "The page check's test account must sign in again" ;;
    page-check-blocked) echo "The site blocked the daily page check" ;;
    *) echo "The daily page check could not run" ;;
  esac
}
color_of() {
  case "$1" in
    page-change) echo d93f0b ;;
    page-check-session) echo fbca04 ;;
    *) echo c5def5 ;;
  esac
}

case "$OUTCOME" in
  ok) label="" ;;
  broken) label=page-change ;;
  session) label=page-check-session ;;
  blocked) label=page-check-blocked ;;
  *) label=page-check-failed ;;
esac

# What the check found, in one line. A page change lists the broken hooks.
marker="$OUTCOME"
if [ "$OUTCOME" = broken ] && [ -f "${RESULT:-}" ]; then
  marker="broken: $(jq -r '.broken | join(", ")' "$RESULT")"
fi

# The open issues with a label, oldest first. The REST list shows a new issue at once (the
# label filter of `gh issue list` can miss an issue for some seconds after it is made).
open_issues() {
  gh api "repos/$GH_REPO/issues?labels=$1&state=open&sort=created&direction=asc&per_page=100" \
    --jq '.[] | select(.pull_request == null) | .number'
}
open_issue() { open_issues "$1" | head -n 1; }

close_issues() { # label, reason
  local number
  for number in $(open_issues "$1"); do
    gh issue close "$number" --comment "$2 ([run]($RUN_URL))"
    echo "Closed issue #$number ($1)"
  done
}

# A problem that this run did not find is gone.
reached=(page-check-blocked page-check-failed)        # the check reached ChatGPT
case "$OUTCOME" in
  ok) for l in page-change page-check-session "${reached[@]}"; do close_issues "$l" "The daily page check passes again: all page hooks work, and the screen checks pass."; done ;;
  broken) for l in page-check-session "${reached[@]}"; do close_issues "$l" "The daily page check runs again."; done ;;
  session) for l in "${reached[@]}"; do close_issues "$l" "The daily page check reaches ChatGPT again."; done ;;
esac
[ -n "$label" ] || exit 0

gh label create "$label" --color "$(color_of "$label")" --description "$(about_of "$label")" --force >/dev/null

body_file=$(mktemp)
{
  cat "$REPORT"
  echo
  echo "Found by the daily page check: [run]($RUN_URL). Its artifact has an image of each page as the panel shows it, and a marked image of each failed screen check."
  echo
  echo "<!-- page-check: $marker -->"
} > "$body_file"

number=$(open_issue "$label")
if [ -z "$number" ]; then
  gh issue create --title "$(title_of "$label")" --label "$label" --body-file "$body_file"
  exit 0
fi

# The newest marker in the issue and its comments.
last=$(gh issue view "$number" --json body,comments \
  --jq '[.body, (.comments[].body)] | map(try capture("<!-- page-check: (?<m>.*) -->").m catch null) | map(select(. != null)) | last // ""')
if [ "$last" != "$marker" ]; then
  gh issue comment "$number" --body-file "$body_file"
  echo "Commented on issue #$number: $marker"
else
  echo "Issue #$number already reports this: $marker"
fi
