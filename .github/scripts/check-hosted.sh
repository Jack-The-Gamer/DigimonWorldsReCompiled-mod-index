#!/usr/bin/env bash
# Checks every mod hosted in this index with `dwrc-cli mod validate` from
# the latest Re:Compiled release: the same reader the launcher uses.
set -euo pipefail
"$TOOL" hosted > "$RUNNER_TEMP/hosted.tsv"
if [ ! -s "$RUNNER_TEMP/hosted.tsv" ]; then
  echo "No mods are hosted here."; exit 0
fi
dir="$RUNNER_TEMP/dwrc"
mkdir -p "$dir"
if ! gh release download --repo Jack-The-Gamer/DigimonWorldsReCompiled --pattern '*-linux-x64.zip' --dir "$dir" --clobber; then
  echo "::warning::Could not download dwrc-cli from the latest Re:Compiled release; hosted mods were checked by build-index only."
  exit 0
fi
unzip -q -o "$dir"/*-linux-x64.zip -d "$dir"
cli=$(find "$dir" -type f -name dwrc-cli | head -1)
chmod +x "$cli"
status=0
while IFS=$'\t' read -r folder id version name; do
  echo "== $folder ($id $version)"
  if ! "$cli" mod validate "mods/$folder/mod"; then
    echo "::error file=mods/$folder/mod/mod.toml::$name: dwrc-cli mod validate found problems (see the log)"
    status=1
  fi
done < "$RUNNER_TEMP/hosted.tsv"
exit $status
