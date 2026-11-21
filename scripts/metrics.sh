#!/bin/bash
# Weekly numbers for Point, from GitHub. Usage: scripts/metrics.sh [log.csv]
# Prints one row; with a path, appends it to that CSV (adds a header if the file is new).
set -euo pipefail
REPO="sksareen/point"
stars=$(gh api "repos/$REPO" --jq .stargazers_count)
forks=$(gh api "repos/$REPO" --jq .forks_count)
issues=$(gh api "repos/$REPO" --jq .open_issues_count)
downloads=$(gh api "repos/$REPO/releases" --jq '[.[].assets[].download_count] | add // 0')
latest=$(gh api "repos/$REPO/releases/latest" --jq '.tag_name + ":" + ([.assets[].download_count] | add | tostring)')
views=$(gh api "repos/$REPO/traffic/views" --jq '"\(.count),\(.uniques)"')
clones=$(gh api "repos/$REPO/traffic/clones" --jq .uniques)
row="$(date +%F),$stars,$forks,$issues,$downloads,$latest,$views,$clones"
header="date,stars,forks,open_issues,total_downloads,latest_release:downloads,views_14d,unique_visitors_14d,unique_cloners_14d"
echo "$header"; echo "$row"
if [ "${1:-}" != "" ]; then
    [ -f "$1" ] || echo "$header" > "$1"
    echo "$row" >> "$1"
fi
