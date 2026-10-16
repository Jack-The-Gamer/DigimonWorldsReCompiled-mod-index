#!/usr/bin/env bash
# Releases each mod hosted in this index whose mod.toml version has no
# release yet: tag <id>-v<version>, asset <id>-<version>.zip holding an
# <id>/ folder (the committed contents of mods/<Author>@<id>/mod/).
# The release notes are the message of the last commit that changed the mod.
set -euo pipefail
"$TOOL" hosted > "$RUNNER_TEMP/hosted.tsv"
while IFS=$'\t' read -r folder id version name; do
  tag="$id-v$version"
  if git ls-remote --exit-code --tags origin "refs/tags/$tag" > /dev/null; then
    echo "$tag is already released"
    continue
  fi
  work="$RUNNER_TEMP/pack/$id"
  rm -rf "$RUNNER_TEMP/pack"
  mkdir -p "$work"
  git archive "HEAD:mods/$folder/mod" | tar -x -C "$work"
  zip_path="$RUNNER_TEMP/pack/$id-$version.zip"
  (cd "$RUNNER_TEMP/pack" && zip -qr -X "$id-$version.zip" "$id")
  notes="$RUNNER_TEMP/notes.md"
  git log -1 --format=%B -- "mods/$folder/mod" \
    | grep -v -E '^(Co-Authored-By|Co-authored-by|Signed-off-by|Claude-Session):' > "$notes" || true
  if [ -z "$(tr -d '[:space:]' < "$notes")" ]; then
    echo "$name $version" > "$notes"
  fi
  gh release create "$tag" "$zip_path" --target "$GITHUB_SHA" --title "$name $version" --notes-file "$notes" --latest=false
  echo "Released $tag"
  echo "- released \`$tag\` ($name $version)" >> "$GITHUB_STEP_SUMMARY"
done < "$RUNNER_TEMP/hosted.tsv"
