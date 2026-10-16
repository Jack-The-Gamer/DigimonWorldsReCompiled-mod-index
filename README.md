# Digimon Worlds Re:Compiled — mod index

The community list of mods for [Digimon Worlds Re:Compiled](https://github.com/Jack-The-Gamer/DigimonWorldsReCompiled).
Every Re:Compiled launcher reads this index in **Mods → Find mods**; players
install a listed mod with one click and are offered its updates.

A mod can live in one of two places, and the launcher treats both the same:

* **In its author's own repository.** The entry is a `meta.json` saying where
  it is and what it needs. The design follows
  [Gen1Recomp's mod index](https://github.com/bryanthaboi/gen1recomp-mod-index).
* **Here, in the index.** The entry holds the mod itself in a `mod/` folder,
  and this repository releases it. No repository of your own is needed: see
  [Hosting a mod here](#hosting-a-mod-here).

Never anything taken from the games, either way.

* **Add your mod:** open a pull request adding one folder to `mods/` (below).
* **Read the index:** `https://jack-the-gamer.github.io/DigimonWorldsReCompiled-mod-index/data/index.json`,
  rebuilt on every push and nightly.

## Layout

```
mods/
  <YourName>@<mod id>/
    meta.json        the entry (optional for a mod hosted here)
    description.md   required — shown in the launcher's details view
    thumbnail.png    optional — PNG, at most 1024×1024 and 2 MB
    mod/             optional — the mod itself, hosted here (mod.toml at its top)
examples/            a template entry to copy
schema/              mod.schema.json (for editors; the build tool is the source of truth)
tools/build-index/   validates entries and builds the feed (Rust)
```

The id half of the folder name must equal the `id` in your mod's `mod.toml`,
so a listing and an installed mod always name the same thing. Nothing else may
live in the folder.

## Hosting a mod here

Put the mod in `mods/<YourName>@<mod id>/mod/`, exactly as it is in your mods
folder (`mod.toml`, scripts, `files/`…), next to `description.md` and, if you
like, `thumbnail.png`. In `mod.toml`, set

```toml
github = "Jack-The-Gamer/DigimonWorldsReCompiled-mod-index"
```

so installed copies check this repository for updates. That is all: every
`meta.json` field comes from `mod.toml` (`name` becomes the title, `description`
the summary, `game`/`games`, `categories`, `tags`, `license`, `engine`,
`dependencies`, `conflicts`, `experimental` carry over), and the source link
points at the folder. A `meta.json` is still allowed, to add or override
listing fields such as a shorter `summary`, but it may not contradict
`mod.toml` (`id`, `version`, `github`).

**Releasing:** bump `version` in `mod.toml` and push to `main` (or merge the
pull request). The **Build and publish** workflow then

1. checks the mod with `dwrc-cli mod validate` from the latest Re:Compiled release;
2. if `<id>-v<version>` has no release yet, packs the committed contents of
   `mod/` as `<id>-<version>.zip` (an `<id>/` folder) and publishes it as a
   GitHub Release of this repository tagged `<id>-v<version>` — its notes are
   the message of the last commit that changed the mod, so write that commit
   message for players;
3. rebuilds the feed, which now lists the new version.

Players are offered the update in the launcher. Old releases stay, so
**Versions…** can still roll back. Releases are never marked "latest" (the
repository holds many mods); please don't create plain `v1.2.0` tags here.
Because every hosted mod shares this repository's tags, an id may not be
another hosted id followed by `-<number>` (`pack` and `pack-2`); the check
says so if it happens.

## meta.json

For a mod hosted here these all come from its `mod.toml` (above).

| Field | | Meaning |
|---|---|---|
| `id` | required | your mod's id, as in `mod.toml` |
| `title` | required | display name |
| `author` | required | creator or maintainer |
| `version` | required | version of the release this entry describes |
| `categories` | required | 1–4 of `GAMEPLAY`, `CONTENT`, `BALANCE`, `ART`, `AUDIO`, `UI`, `QOL`, `TRANSLATION`, `TOTAL_CONVERSION`, `LIBRARY`, `TOOL`, `OTHER` |
| `games` | required | `dw1`, `dw2`, `dw3` and/or `any` |
| `repo` | required | where the source lives |
| `github` | recommended | `owner/repo` — turns on version tracking here and update checks in the launcher |
| `downloadURL` | | direct link to an installable `.zip`; required when there is no `github` |
| `summary`, `tags`, `license` | | listing polish |
| `engine`, `experimental`, `dependencies`, `conflicts` | | copied from `mod.toml` so the launcher can warn before installing |
| `automatic_version_check`, `fixed_release_tag` | | follow the newest release (default), or pin one tag |

## Releases: how versions are picked up

For a mod in its own repository: set `github = "owner/repo"` in your `mod.toml` too, and publish each version
as a **GitHub Release** whose tag is the version (`v1.2.0`, or
`<id>-v1.2.0` if one repository holds several mods), with the mod attached as
**`<id>-<version>.zip`** containing an `<id>/` folder. `dwrc-cli mod pack`
builds exactly that file, and the Re:Compiled repository has a ready-made
workflow (`docs/templates/release-mod.yml`) that publishes a release whenever the
`version` in `mod.toml` changes.

The launcher's Mods page reads those releases to offer **Update** and
**Versions** (install any release, including rolling back). This index reads
them nightly and records the newest installable release, so **you do not open a
pull request per version** — only when the listing itself changes.

Asset choice, in order: `<id>-<version>.zip`, then a `.zip` starting with the
id, then the first `.zip`. Drafts are ignored; the newest stable release wins
over a newer pre-release.

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
plain HTML listing). `hosted` lists the mods hosted here (what the release step
works through); `--repo owner/repo` names this repository when there is no
`origin` remote or `GITHUB_REPOSITORY` to tell. The **Build and publish** workflow runs it on every push to
`main` and nightly, and publishes `site/` to the `gh-pages` branch.

### Setting up the repository (maintainers, once)

1. Create the repository as `Jack-The-Gamer/DigimonWorldsReCompiled-mod-index` (public) and push this folder to `main`; GitHub Desktop's **Publish repository** does both.
2. Run **Actions → Build and publish the index** once (or push); it creates the `gh-pages` branch.
3. **Settings → Pages → Build and deployment:** *Deploy from a branch*, branch `gh-pages`, folder `/ (root)`.

The launcher reads `https://jack-the-gamer.github.io/DigimonWorldsReCompiled-mod-index/data/index.json`,
and falls back to the `gh-pages` branch on raw.githubusercontent.com while Pages deploys.

## Rules

* No game data: nothing copied from the discs, the BIOS or other copyrighted material, in the index, in hosted mods or in listed mods.
* A listing is not an endorsement. Re:Compiled runs mod scripts in a sandbox (no file, network or OS access), but read a mod's source if in doubt.
* Entries whose repository disappears or stops publishing installable releases show that state (`update_check`) and may be removed.

The build tool is MIT/Apache-2.0, like Re:Compiled. Listings are contributed by mod authors.
