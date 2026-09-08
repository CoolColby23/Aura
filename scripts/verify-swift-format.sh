#!/bin/bash
set -euo pipefail

if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    git fetch --no-tags --depth=1 origin "${GITHUB_BASE_REF}"
    files="$(git diff --diff-filter=ACMR --name-only "origin/${GITHUB_BASE_REF}"...HEAD -- '*.swift')"
else
    files="$({
        git diff --diff-filter=ACMR --name-only HEAD -- '*.swift'
        git ls-files --others --exclude-standard -- '*.swift'
    } | sort -u)"
fi

if [[ -z "$files" ]]; then
    echo "No changed Swift files require format verification."
    exit 0
fi

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    xcrun swift-format lint --strict --configuration .swift-format "$file"
done <<< "$files"

echo "Verified Swift formatting for every changed file."
