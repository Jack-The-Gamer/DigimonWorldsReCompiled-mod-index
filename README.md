# Digimon Worlds Re:Compiled — mod index

The mod index built into [Digimon Worlds Re:Compiled](https://github.com/Jack-The-Gamer/DigimonWorldsReCompiled):
the mods made for the project, which every launcher lists in **Mods → Find
mods**. Players install a listed mod with one click and are offered its
updates.

This index lists the project's own mods; it does not take submissions. To
share mods of your own, run **your own mod index**: it is a copy of this
repository with your mods in it, and players add it to their launcher in
**Find mods → Indexes…**. This repository is set up to be copied: see
[Your own mod index](#your-own-mod-index).

* **The feed:** `https://jack-the-gamer.github.io/DigimonWorldsReCompiled-mod-index/data/index.json`,
  rebuilt on every push and nightly.

## How an index works

An index is a GitHub repository that publishes one JSON **feed** listing mods.
The launcher reads it from GitHub Pages:

```
https://<owner>.github.io/<repo>/data/index.json
```

falling back to the `gh-pages` branch on `raw.githubusercontent.com` while
Pages deploys. The Re:Compiled index (this one) is always listed; players add
others in **Find mods → Indexes…** by typing the index's `owner/repo`, pasting
its GitHub link, or giving a feed URL. Each index's listings are fetched when
the launcher starts and every six hours, with the last copy shown offline.

Nothing in the feed is written by hand. Each mod is a folder under `mods/`, and
the **Build and publish** workflow (`.github/workflows/publish.yml`), on every
push to `main` and nightly:

1. checks every mod hosted in the index with `dwrc-cli mod validate` from the
   latest Re:Compiled release (the same reader the launcher uses);
2. releases each hosted mod whose `mod.toml` version has no release yet (see
   [Hosting a mod in an index](#hosting-a-mod-in-an-index));
3. builds the feed with `tools/build-index`, reading every listed mod's GitHub
   Releases for its newest installable `.zip` and download counts;
4. publishes the feed, the descriptions and thumbnails, and a plain HTML
   listing to the `gh-pages` branch.

A mod can live in one of two places, and the launcher treats both the same:

* **In the index itself** (`mods/<Author>@<id>/mod/`): the index repository
  releases it. No other repository is needed.
* **In its own repository** (`mods/<Author>@<id>/meta.json`): the entry says
  where the mod is, and the nightly build follows that repository's releases.

Installing a listed mod downloads its release `.zip` and installs it exactly as
**Import .zip…** would, so a listing grants a mod no extra trust. Updates come
from the GitHub repository named by `github` in the mod's `mod.toml`. Mod
scripts run in Re:Compiled's sandbox either way.

## Your own mod index

1. **Make the repository.** Create a public GitHub repository, for example
   `you/my-dwrc-mods`, and put a copy of this repository in it: download this
   repository as a ZIP (or clone it), and push its contents to your
   repository's `main` branch (GitHub Desktop's **Publish repository** does
   it). Keep `.github/`, `tools/`, `schema/` and `examples/`, and delete the
   folders inside `mods/`: those are the Re:Compiled mods, which stay in this
   index.
2. **Add your mods**, one folder each, as described below: either the mod
   itself in `mods/<You>@<id>/mod/` with `github = "you/my-dwrc-mods"` in its
   `mod.toml`, or a `meta.json` pointing at the mod's own repository. Check
   them with the build tool (see [Working on it](#working-on-it)).
3. **Push to `main`.** The **Build and publish** workflow runs (watch it under
   **Actions**). It releases your hosted mods and creates the `gh-pages`
   branch.
4. **Turn on GitHub Pages:** **Settings → Pages → Build and deployment**,
   *Deploy from a branch*, branch `gh-pages`, folder `/ (root)`. Your feed is
   then at `https://you.github.io/my-dwrc-mods/data/index.json`.
5. **Tell players** to add `you/my-dwrc-mods` in **Mods → Find mods →
   Indexes…**. Your mods then appear in Find mods next to the built-in ones,
   with one-click installs and updates.

From then on, releasing a new version of a hosted mod is: bump `version` in
its `mod.toml` and push. Mods listed from their own repositories are picked up
by the nightly build whenever they publish a release.

## Layout

```
mods/
  <Author>@<mod id>/
    meta.json        the entry (optional for a mod hosted in the index)
    description.md   required — shown in the launcher's details view
    thumbnail.png    optional — PNG, at most 1024×1024 and 2 MB
    mod/             optional — the mod itself, hosted in the index (mod.toml at its top)
examples/            a template entry to copy
schema/              mod.schema.json (for editors; the build tool is the source of truth)
tools/build-index/   validates entries and builds the feed (Rust)
```

The id half of the folder name must equal the `id` in the mod's `mod.toml`,
so a listing and an installed mod always name the same thing. Nothing else may
live in the folder.

## Hosting a mod in an index

Put the mod in `mods/<Author>@<mod id>/mod/`, exactly as it is in your mods
folder (`mod.toml`, scripts, `files/`…), next to `description.md` and, if you
like, `thumbnail.png`. In `mod.toml`, set `github` to the index's repository,
for example

```toml
github = "you/my-dwrc-mods"
```

so installed copies check the index for updates. That is all: every
`meta.json` field comes from `mod.toml` (`name` becomes the title, `description`
the summary, `game`/`games`, `categories`, `tags`, `license`, `engine`,
`dependencies`, `conflicts`, `experimental` carry over), and the source link
points at the folder. A `meta.json` is still allowed, to add or override
listing fields such as a shorter `summary`, but it may not contradict
`mod.toml` (`id`, `version`, `github`).

**Releasing:** bump `version` in `mod.toml` and push to `main`. The **Build and
publish** workflow then

1. checks the mod with `dwrc-cli mod validate` from the latest Re:Compiled release;
2. if `<id>-v<version>` has no release yet, packs the committed contents of
   `mod/` as `<id>-<version>.zip` (an `<id>/` folder) and publishes it as a
   GitHub Release of the index tagged `<id>-v<version>`. Its notes are the
   message of the last commit that changed the mod, so write that commit
   message for players;
3. rebuilds the feed, which now lists the new version.

Players are offered the update in the launcher. Old releases stay, so
**Version History** can still roll back. Releases are never marked "latest" (the
repository holds many mods); don't create plain `v1.2.0` tags in an index.
Because every hosted mod shares the index's tags, an id may not be another
hosted id followed by `-<number>` (`pack` and `pack-2`); the check says so if
it happens.

## Listing a mod from its own repository

Copy `examples/YourName@example-mod/` into `mods/`, rename it, and fill in
`meta.json` (below) and `description.md`. In the mod's own repository, set
`github = "owner/repo"` in its `mod.toml` too, and publish each version as a
**GitHub Release** whose tag is the version (`v1.2.0`, or `<id>-v1.2.0` if one
repository holds several mods), with the mod attached as
**`<id>-<version>.zip`** containing an `<id>/` folder. `dwrc-cli mod pack`
builds exactly that file, and the Re:Compiled repository has a ready-made
workflow (`docs/templates/release-mod.yml`) that publishes a release whenever the
`version` in `mod.toml` changes.

The launcher's Mods page reads those releases to offer **Update** and
**Version History** (install any release, including rolling back). The index
reads them nightly and records the newest installable release, so the entry
only needs changing when the listing itself changes.

Asset choice, in order: `<id>-<version>.zip`, then a `.zip` starting with the
id, then the first `.zip`. Drafts are ignored; the newest stable release wins
over a newer pre-release.

### meta.json

For a mod hosted in the index these all come from its `mod.toml` (above).

| Field | | Meaning |
|---|---|---|
| `id` | required | the mod's id, as in `mod.toml` |
| `title` | required | display name |
| `author` | required | creator or maintainer |
| `version` | required | version of the release this entry describes |
| `categories` | required | 1–4 of `GAMEPLAY`, `CONTENT`, `BALANCE`, `ART`, `AUDIO`, `UI`, `QOL`, `TRANSLATION`, `TOTAL_CONVERSION`, `LIBRARY`, `TOOL`, `OTHER` |
| `games` | required | `dw1`, `dw2`, `dw3` and/or `any` |
| `repo` | required | where the source lives |
| `github` | recommended | `owner/repo` — turns on version tracking in the index and update checks in the launcher |
| `downloadURL` | | direct link to an installable `.zip`; required when there is no `github` |
| `summary`, `tags`, `license` | | listing polish |
| `engine`, `experimental`, `dependencies`, `conflicts` | | copied from `mod.toml` so the launcher can warn before installing |
| `automatic_version_check`, `fixed_release_tag` | | follow the newest release (default), or pin one tag |

## The feed

`data/index.json`:

```jsonc
{
  "schema_version": 1,
  "generated_at": "2026-10-16T04:23:00Z",
  "count": 1,
  "categories": ["GAMEPLAY", "..."],
  "games": ["dw1", "dw2", "dw3"],
  "mods": [{
    "folder": "YourName@example-mod",
    "id": "example-mod",
    // ...every meta.json field...
    "thumbnail": "data/mods/YourName@example-mod/thumbnail.png",
    "description_url": "data/mods/YourName@example-mod/description.md",
    "latest": { "version": "1.2.0", "tag": "v1.2.0", "prerelease": false, "published_at": "…",
                "zip": { "name": "example-mod-1.2.0.zip", "url": "https://github.com/…", "size": 48213 } },
    "update_check": "ok",          // ok | off | pending | no installable release | error: …
    "downloads": { "total": 1578, "recent": 388, "window_days": 30, "as_of": "…" },
    "first_release": "2026-08-01", "last_release": "2026-10-10"
  }]
}
```

`schema_version` is compared for equality by the launcher: a change that would
break old readers gets a new version; anything else is only ever **added** as a
new key. Paths are relative to the published site. Download counts are summed
over every `.zip` of every release, never go down (the highest count seen per tag
is kept in `data/history.json`), and `recent` covers the last 30 days once that
much history exists.

## Working on it

Install Rust (https://rustup.rs), then:

```sh
cargo run --manifest-path tools/build-index/Cargo.toml -- validate --examples
cargo run --manifest-path tools/build-index/Cargo.toml -- validate mods/You@your-mod
cargo run --manifest-path tools/build-index/Cargo.toml -- build              # offline
cargo run --manifest-path tools/build-index/Cargo.toml -- build --releases   # reads GitHub (set GITHUB_TOKEN to avoid rate limits)
```

`build` writes `site/` (the feed, the copied descriptions and thumbnails, and a
plain HTML listing). `hosted` lists the mods hosted in the index (what the
release step works through); `--repo owner/repo` names the index's repository
when there is no `origin` remote or `GITHUB_REPOSITORY` to tell.

## Rules

* No game data: nothing copied from the discs, the BIOS or other copyrighted material, in an index, in hosted mods or in listed mods.
* A listing is not an endorsement. Re:Compiled runs mod scripts in a sandbox (no file, network or OS access), but read a mod's source if in doubt.
* Entries whose repository disappears or stops publishing installable releases show that state (`update_check`) and may be removed.

The build tool is MIT/Apache-2.0, like Re:Compiled.
