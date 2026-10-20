//! build-index: checks the Digimon Worlds Re:Compiled mod index and builds
//! the feed the launcher's **Find mods** tab reads.
//!
//! ```text
//! build-index validate [--examples] [--repo owner/repo] [mods/<Author>@<id> ...]
//! build-index build [--releases] [--previous <history.json>] [--out site]
//! build-index hosted [--repo owner/repo]
//! ```
//!
//! An entry either points at the mod's own repository, or **hosts** the mod
//! here: `mods/<Author>@<id>/mod/` is then the mod itself (`mod.toml` at its
//! top). A hosted mod is released from this repository as `<id>-v<version>`
//! with `<id>-<version>.zip` (see `.github/workflows/publish.yml`; `hosted`
//! lists what to release), and every meta.json field its mod.toml can answer
//! may be left out of meta.json.
//!
//! `build` writes `site/data/index.json` (the feed), copies each entry's
//! description and thumbnail next to it, and renders `site/index.html`.
//! With `--releases` it reads every listed repository's GitHub Releases,
//! picks the installable `.zip` the same way the launcher does, and records
//! the newest release and download counts, so a listing never has to change
//! just because its mod has a new version.
//!
//! Environment: `GITHUB_TOKEN` (optional; raises GitHub's rate limit),
//! `GITHUB_API_URL` (default `https://api.github.com`) and
//! `GITHUB_REPOSITORY` (this index's `owner/repo`; otherwise `--repo`, else
//! the `origin` remote).

use anyhow::{bail, Context, Result};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

const SCHEMA_VERSION: u64 = 1;
const CATEGORIES: &[&str] =
    &["GAMEPLAY", "CONTENT", "BALANCE", "ART", "AUDIO", "UI", "QOL", "TRANSLATION", "TOTAL_CONVERSION", "LIBRARY", "TOOL", "OTHER"];
const GAMES: &[&str] = &["dw1", "dw2", "dw3", "any"];
const FILES: &[&str] = &["meta.json", "description.md", "thumbnail.png", "mod"];
const FIELDS: &[&str] = &[
    "id",
    "title",
    "author",
    "version",
    "summary",
    "categories",
    "tags",
    "games",
    "repo",
    "github",
    "downloadURL",
    "license",
    "engine",
    "experimental",
    "dependencies",
    "conflicts",
    "automatic_version_check",
    "fixed_release_tag",
];

struct Entry {
    folder: String,
    dir: PathBuf,
    meta: Map<String, Value>,
    /// Set when the mod is hosted in this repository (`mod/`).
    hosted: Option<Hosted>,
    /// Problems found while reading the entry.
    problems: Vec<String>,
}

/// A mod kept in the index itself, read from `mod/mod.toml`.
struct Hosted {
    id: String,
    /// Normalised (`1.2.0`): the release is `<id>-v<version>`.
    version: String,
    name: String,
}

impl Entry {
    fn s(&self, k: &str) -> Option<&str> {
        self.meta.get(k).and_then(Value::as_str)
    }
}

fn valid_id(s: &str) -> bool {
    !s.is_empty() && s.len() <= 64 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
}

fn valid_repo(s: &str) -> bool {
    let mut p = s.split('/');
    let ok = |x: Option<&str>| x.is_some_and(|x| !x.is_empty() && !x.starts_with('.') && x.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.')));
    ok(p.next()) && ok(p.next()) && p.next().is_none()
}

/// Lenient semver: `v1.2`, `1.2`, `1.2.0`.
fn parse_version(s: &str) -> Option<semver::Version> {
    let s = s.trim().trim_start_matches(['v', 'V']);
    if let Ok(v) = semver::Version::parse(s) {
        return Some(v);
    }
    let (core, rest) = match s.find(['-', '+']) {
        Some(i) => (&s[..i], &s[i..]),
        None => (s, ""),
    };
    let parts: Vec<&str> = core.split('.').collect();
    if parts.is_empty() || parts.len() > 3 || parts.iter().any(|p| p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit())) {
        return None;
    }
    let mut padded = parts.join(".");
    for _ in parts.len()..3 {
        padded.push_str(".0");
    }
    semver::Version::parse(&format!("{padded}{rest}")).ok()
}

fn valid_range(r: &str) -> bool {
    let r = r.trim();
    r == "*" || semver::VersionReq::parse(r).is_ok() || semver::VersionReq::parse(&r.split_whitespace().collect::<Vec<_>>().join(", ")).is_ok()
}

fn http_url(s: &str) -> bool {
    s.starts_with("https://") || s.starts_with("http://")
}

// ---------------------------------------------------------------------------
// Loading and validation
// ---------------------------------------------------------------------------

fn load_dir(dir: &Path, repo: Option<&str>) -> Result<Vec<Entry>> {
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(dir) else { return Ok(out) };
    let mut dirs: Vec<PathBuf> = rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()).collect();
    dirs.sort();
    for d in dirs {
        out.push(load_entry(&d, repo)?);
    }
    Ok(out)
}

fn load_entry(d: &Path, repo: Option<&str>) -> Result<Entry> {
    let folder = d.file_name().context("entry folder")?.to_string_lossy().to_string();
    let mut problems = Vec::new();
    let meta = match std::fs::read_to_string(d.join("meta.json")) {
        Ok(text) => match serde_json::from_str::<Value>(&text) {
            Ok(Value::Object(m)) => m,
            Ok(_) => {
                problems.push("meta.json must be a JSON object".into());
                Map::new()
            }
            Err(e) => {
                problems.push(format!("meta.json is not valid JSON ({e})"));
                Map::new()
            }
        },
        Err(_) => Map::new(),
    };
    let mut e = Entry { folder, dir: d.to_path_buf(), meta, hosted: None, problems };
    if d.join("mod").is_dir() {
        load_hosted(&mut e, repo);
    } else if !d.join("meta.json").exists() {
        e.problems.push("meta.json is required (or a mod/ folder holding the mod itself)".into());
    }
    Ok(e)
}

/// The GitHub repository this index is (`owner/repo`).
fn this_repo(root: &Path, given: Option<String>) -> Option<String> {
    if let Some(r) = given.or_else(|| std::env::var("GITHUB_REPOSITORY").ok()).filter(|r| valid_repo(r)) {
        return Some(r);
    }
    let out = std::process::Command::new("git").arg("-C").arg(root).args(["config", "--get", "remote.origin.url"]).output().ok()?;
    let url = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let rest = url.split_once("github.com").map(|(_, r)| r.trim_start_matches([':', '/']))?;
    let r = rest.trim_end_matches('/').trim_end_matches(".git").to_string();
    valid_repo(&r).then_some(r)
}

fn toml_str(t: &toml::Table, k: &str) -> Option<String> {
    t.get(k).and_then(|v| v.as_str()).map(str::to_string)
}

/// A string or a list of strings.
fn toml_list(t: &toml::Table, k: &str) -> Option<Vec<String>> {
    match t.get(k)? {
        toml::Value::String(s) => Some(vec![s.clone()]),
        toml::Value::Array(a) => Some(a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect()),
        _ => None,
    }
}

/// `text` cut to at most `max` characters at a word boundary.
fn summarize(text: &str, max: usize) -> String {
    let t = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if t.chars().count() <= max {
        return t;
    }
    let cut: String = t.chars().take(max - 1).collect();
    let cut = cut.rsplit_once(' ').map(|(a, _)| a).unwrap_or(&cut);
    format!("{}…", cut.trim_end_matches([',', ';', ':', '.']))
}

fn fill(meta: &mut Map<String, Value>, k: &str, v: Option<Value>) {
    if let Some(v) = v {
        meta.entry(k.to_string()).or_insert(v);
    }
}

/// Reads a hosted mod's `mod/mod.toml` and fills in every meta.json field
/// it answers that meta.json leaves out, so the mod is described once.
fn load_hosted(e: &mut Entry, repo: Option<&str>) {
    let text = match std::fs::read_to_string(e.dir.join("mod").join("mod.toml")) {
        Ok(t) => t,
        Err(_) => return e.problems.push("mod/ must hold the mod itself, with its mod.toml at the top".into()),
    };
    let table: toml::Table = match text.parse() {
        Ok(t) => t,
        Err(err) => return e.problems.push(format!("mod/mod.toml: {}", err.message().trim())),
    };
    let Some(m) = table.get("mod").and_then(|v| v.as_table()) else {
        return e.problems.push("mod/mod.toml has no [mod] section".into());
    };
    let (Some(id), Some(version), Some(name)) = (toml_str(m, "id"), toml_str(m, "version"), toml_str(m, "name")) else {
        return e.problems.push("mod/mod.toml needs id, name and version in its [mod] section".into());
    };
    let Some(v) = parse_version(&version) else {
        return e.problems.push(format!("mod/mod.toml: version '{version}' is not a version number like 1.2.0"));
    };
    if let Some(mid) = e.s("id").filter(|x| *x != id) {
        e.problems.push(format!("meta.json says id '{mid}' but mod/mod.toml says '{id}'"));
    }
    if let Some(mv) = e.s("version") {
        if parse_version(mv).as_ref() != Some(&v) {
            e.problems.push(format!("meta.json says version {mv} but mod/mod.toml says {version}: leave version out of meta.json, a hosted mod's comes from its mod.toml"));
        }
    }
    let meta = &mut e.meta;
    meta.insert("version".into(), json!(v.to_string()));
    fill(meta, "id", Some(json!(id)));
    fill(meta, "title", Some(json!(name)));
    fill(meta, "author", toml_str(m, "author").map(Value::from));
    fill(meta, "summary", toml_str(m, "description").filter(|d| !d.trim().is_empty()).map(|d| json!(summarize(&d, 200))));
    fill(meta, "categories", toml_list(m, "categories").map(Value::from));
    fill(meta, "tags", toml_list(m, "tags").map(Value::from));
    fill(meta, "games", toml_list(m, "games").or_else(|| toml_list(m, "game")).map(Value::from));
    fill(meta, "license", toml_str(m, "license").map(Value::from));
    fill(meta, "engine", toml_str(m, "engine").map(Value::from));
    fill(meta, "dependencies", toml_list(m, "dependencies").map(Value::from));
    fill(meta, "conflicts", toml_list(m, "conflicts").map(Value::from));
    fill(meta, "experimental", m.get("experimental").and_then(|v| v.as_bool()).map(Value::from));
    match repo {
        Some(repo) => {
            if let Some(g) = meta.get("github").and_then(Value::as_str).filter(|g| !g.eq_ignore_ascii_case(repo)) {
                e.problems.push(format!("a mod hosted here is released from {repo}; meta.json's github ('{g}') must be left out"));
            }
            meta.insert("github".into(), json!(repo));
            fill(meta, "repo", Some(json!(format!("https://github.com/{repo}/tree/HEAD/mods/{}", e.folder))));
            match toml_str(m, "github") {
                Some(g) if g.eq_ignore_ascii_case(repo) => {}
                Some(g) => e.problems.push(format!("mod/mod.toml must say github = \"{repo}\" (it says \"{g}\"), so players are offered its updates")),
                None => e.problems.push(format!("add github = \"{repo}\" to mod/mod.toml, so players are offered its updates")),
            }
        }
        None => e.problems.push("can't tell which GitHub repository this index is: pass --repo owner/repo".into()),
    }
    if let Some(script) = toml_str(m, "script") {
        if !e.dir.join("mod").join(&script).is_file() {
            e.problems.push(format!("mod/mod.toml names script '{script}', which is not in mod/"));
        }
    }
    e.hosted = Some(Hosted { id, version: v.to_string(), name });
}

fn png_size(bytes: &[u8]) -> Option<(u32, u32)> {
    if bytes.len() < 24 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" || &bytes[12..16] != b"IHDR" {
        return None;
    }
    let w = u32::from_be_bytes(bytes[16..20].try_into().ok()?);
    let h = u32::from_be_bytes(bytes[20..24].try_into().ok()?);
    Some((w, h))
}

fn check(e: &Entry) -> (Vec<String>, Vec<String>) {
    let mut err = e.problems.clone();
    let mut warn = Vec::new();
    let m = &e.meta;
    if m.is_empty() {
        if err.is_empty() {
            err.push("meta.json is missing or is not a JSON object".into());
        }
        return (err, warn);
    }
    // Folder: <Author>@<id>, id matching meta.json.
    match e.folder.split_once('@') {
        Some((author, id)) => {
            if author.is_empty() || !author.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.')) {
                err.push("the folder's author half may only use letters, digits, '-', '_' and '.'".into());
            }
            if Some(id) != e.s("id") {
                err.push(format!("the folder's id half ('{id}') must equal meta.json's id"));
            }
        }
        None => err.push("the folder must be named <Author>@<mod id>".into()),
    }
    // Files.
    if let Ok(rd) = std::fs::read_dir(&e.dir) {
        for f in rd.flatten() {
            let n = f.file_name().to_string_lossy().to_string();
            if !FILES.contains(&n.as_str()) {
                err.push(format!("'{n}' is not allowed here (only meta.json, description.md, thumbnail.png and a mod/ folder)"));
            } else if (n == "mod") != f.path().is_dir() {
                err.push(format!("'{n}' must be {}", if n == "mod" { "a folder" } else { "a file" }));
            }
        }
    }
    match std::fs::read(e.dir.join("description.md")) {
        Ok(b) if b.len() > 64 * 1024 => err.push("description.md is larger than 64 KB".into()),
        Ok(b) if String::from_utf8(b.clone()).map(|t| t.trim().is_empty()).unwrap_or(true) => err.push("description.md must be non-empty UTF-8 text".into()),
        Ok(_) => {}
        Err(_) => err.push("description.md is required".into()),
    }
    if let Ok(b) = std::fs::read(e.dir.join("thumbnail.png")) {
        match png_size(&b) {
            None => err.push("thumbnail.png is not a PNG image".into()),
            Some((w, h)) if w > 1024 || h > 1024 => err.push(format!("thumbnail.png is {w}x{h}; at most 1024x1024")),
            Some(_) if b.len() > 2 << 20 => err.push("thumbnail.png is larger than 2 MB".into()),
            Some(_) => {}
        }
    }
    // Fields.
    for k in m.keys() {
        if !FIELDS.contains(&k.as_str()) {
            err.push(format!("unknown field '{k}'"));
        }
    }
    let req_str = |k: &str, max: usize, err: &mut Vec<String>| match m.get(k) {
        Some(Value::String(s)) if !s.trim().is_empty() && s.chars().count() <= max => {}
        Some(Value::String(s)) if s.chars().count() > max => err.push(format!("{k} is longer than {max} characters")),
        _ => err.push(format!("{k} is required (a non-empty string)")),
    };
    req_str("id", 64, &mut err);
    req_str("title", 80, &mut err);
    req_str("author", 64, &mut err);
    req_str("version", 64, &mut err);
    req_str("repo", 300, &mut err);
    if let Some(id) = e.s("id") {
        if !valid_id(id) {
            err.push("id may only use letters, digits, '-' and '_' (it must match the mod's mod.toml id)".into());
        }
    }
    if let Some(v) = e.s("version") {
        if parse_version(v).is_none() {
            err.push(format!("version '{v}' is not a version number like 1.2.0"));
        }
    }
    if let Some(r) = e.s("repo") {
        if !http_url(r) {
            err.push("repo must be an http(s) URL".into());
        }
    }
    let str_array = |k: &str| -> Option<Vec<String>> {
        match m.get(k) {
            None => Some(Vec::new()),
            Some(Value::Array(a)) => a.iter().map(|x| x.as_str().map(str::to_string)).collect(),
            _ => None,
        }
    };
    match str_array("categories") {
        Some(c) if (1..=4).contains(&c.len()) => {
            for x in c {
                if !CATEGORIES.contains(&x.as_str()) {
                    err.push(format!("unknown category '{x}' (use {})", CATEGORIES.join(", ")));
                }
            }
        }
        _ => err.push("categories must list 1 to 4 categories".into()),
    }
    match str_array("games") {
        Some(g) if !g.is_empty() => {
            for x in g {
                if !GAMES.contains(&x.as_str()) {
                    err.push(format!("unknown game '{x}' (use dw1, dw2, dw3 or any)"));
                }
            }
        }
        _ => err.push("games must list the games the mod runs on (dw1, dw2, dw3 or any)".into()),
    }
    match str_array("tags") {
        Some(t) if t.len() <= 8 && t.iter().all(|x| !x.is_empty() && x.len() <= 24) => {}
        _ => err.push("tags must be at most 8 short strings".into()),
    }
    for k in ["dependencies", "conflicts"] {
        match str_array(k) {
            Some(list) => {
                for d in list {
                    let (id, range) = d.split_once('@').map(|(a, b)| (a, Some(b))).unwrap_or((d.as_str(), None));
                    if !valid_id(id) || range.is_some_and(|r| !valid_range(r)) {
                        err.push(format!("{k}: '{d}' must be a mod id, optionally with @<version range>"));
                    }
                }
            }
            None => err.push(format!("{k} must be a list of strings")),
        }
    }
    let gh = m.get("github");
    match gh {
        None => {}
        Some(Value::String(s)) if valid_repo(s) => {}
        _ => err.push("github must be \"owner/repo\"".into()),
    }
    match m.get("downloadURL") {
        None => {}
        Some(Value::String(s)) if http_url(s) => {}
        _ => err.push("downloadURL must be an http(s) URL".into()),
    }
    if gh.is_none() && m.get("downloadURL").is_none() {
        err.push("give either github (recommended: turns on automatic updates) or downloadURL".into());
    }
    match m.get("summary") {
        None => warn.push("no summary: the launcher shows the summary on every card".into()),
        Some(Value::String(s)) if s.chars().count() <= 200 => {}
        _ => err.push("summary must be a string of at most 200 characters".into()),
    }
    if let Some(r) = m.get("engine") {
        if !r.as_str().is_some_and(valid_range) {
            err.push("engine must be a version range such as \">=0.2\"".into());
        }
    }
    for k in ["experimental", "automatic_version_check"] {
        if m.get(k).is_some_and(|v| !v.is_boolean()) {
            err.push(format!("{k} must be true or false"));
        }
    }
    if m.get("fixed_release_tag").is_some_and(|v| !v.is_string()) {
        err.push("fixed_release_tag must be a string".into());
    }
    if m.get("license").is_some_and(|v| !v.is_string()) {
        err.push("license must be a string".into());
    }
    if !e.dir.join("thumbnail.png").exists() {
        warn.push("no thumbnail.png".into());
    }
    (err, warn)
}

/// Whether mod `a`'s release tags could be read as releases of mod `b`
/// when both are released from one repository. Read for mod `pack`, the
/// tag `pack-2-v1.0.0` (mod `pack-2`) strips to `2-v1.0.0`, which parses
/// as version 2.0.0-v1.0.0; so there an id may not be another id followed
/// by `-<number>` or `-v<number>`.
fn tags_collide(a: &str, b: &str) -> bool {
    let Some(rest) = a.strip_prefix(b) else { return false };
    let mut c = rest.chars();
    matches!(c.next(), Some('-' | '@' | '_')) && {
        let rest: String = c.collect();
        let rest = rest.strip_prefix(['v', 'V']).unwrap_or(&rest);
        rest.starts_with(|ch: char| ch.is_ascii_digit())
    }
}

fn validate(entries: &[Entry], out: &mut dyn std::io::Write) -> usize {
    let mut errors = 0;
    let mut ids: BTreeMap<String, String> = BTreeMap::new();
    for e in entries {
        let (err, warn) = check(e);
        let mut err = err;
        if let Some(id) = e.s("id") {
            if let Some(other) = ids.insert(id.to_string(), e.folder.clone()) {
                err.push(format!("id '{id}' is already listed by {other}"));
            }
            for o in entries {
                let same_repo = matches!((e.s("github"), o.s("github")), (Some(x), Some(y)) if x.eq_ignore_ascii_case(y));
                if let Some(oid) = o.s("id").filter(|oid| same_repo && *oid != id && tags_collide(id, oid)) {
                    err.push(format!("id '{id}' would be mistaken for a version of '{oid}' in the release tags they share ({}): choose another id", e.s("github").unwrap_or("")));
                }
            }
        }
        let _ = writeln!(out, "{}  {}{}", if err.is_empty() { "ok  " } else { "FAIL" }, e.folder, if e.hosted.is_some() { "  (hosted here)" } else { "" });
        for w in &warn {
            let _ = writeln!(out, "        note: {w}");
        }
        for x in &err {
            let _ = writeln!(out, "        error: {x}");
            if std::env::var("GITHUB_ACTIONS").is_ok() {
                let file = if e.hosted.is_some() && x.contains("mod.toml") { "mod/mod.toml" } else { "meta.json" };
                let _ = writeln!(out, "::error file={}/{file}::{x}", e.dir.display());
            }
        }
        errors += err.len();
    }
    errors
}

// ---------------------------------------------------------------------------
// GitHub releases
// ---------------------------------------------------------------------------

struct Github {
    agent: ureq::Agent,
    api: String,
    token: Option<String>,
}

impl Github {
    fn new() -> Self {
        let config = ureq::Agent::config_builder().user_agent("dwrc-build-index").http_status_as_error(false).build();
        Self {
            agent: config.new_agent(),
            api: std::env::var("GITHUB_API_URL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| "https://api.github.com".into()),
            token: std::env::var("GITHUB_TOKEN").ok().filter(|s| !s.is_empty()),
        }
    }

    fn get(&self, path: &str) -> Result<Value> {
        let mut req = self.agent.get(format!("{}{path}", self.api.trim_end_matches('/'))).header("Accept", "application/vnd.github+json");
        if let Some(t) = &self.token {
            req = req.header("Authorization", format!("Bearer {t}"));
        }
        let mut resp = req.call()?;
        let status = resp.status().as_u16();
        let body = resp.body_mut().with_config().limit(32 << 20).read_to_string()?;
        match status {
            200 => Ok(serde_json::from_str(&body)?),
            404 => bail!("repository or release not found"),
            _ => bail!("GitHub answered HTTP {status}"),
        }
    }
}

fn tag_version(tag: &str, id: &str) -> Option<String> {
    let t = tag.trim();
    let t = t.strip_prefix(&format!("{id}-")).or_else(|| t.strip_prefix(&format!("{id}@"))).or_else(|| t.strip_prefix(&format!("{id}_"))).unwrap_or(t);
    parse_version(t).map(|v| v.to_string())
}

/// `<id>-<version>.zip`, else a `.zip` starting with the id, else the first `.zip`.
fn pick_zip<'a>(assets: &'a [Value], id: &str, version: &str) -> Option<&'a Value> {
    let name = |a: &Value| a.get("name").and_then(Value::as_str).unwrap_or("").to_ascii_lowercase();
    let zips: Vec<&Value> = assets.iter().filter(|a| name(a).ends_with(".zip") && a.get("browser_download_url").is_some()).collect();
    let exact = format!("{id}-{version}.zip").to_ascii_lowercase();
    zips.iter()
        .find(|a| name(a) == exact)
        .or_else(|| zips.iter().find(|a| name(a).starts_with(&id.to_ascii_lowercase())))
        .or_else(|| zips.first())
        .copied()
}

struct Resolved {
    latest: Option<Value>,
    check: String,
    per_tag: BTreeMap<String, u64>,
    first: Option<String>,
    last: Option<String>,
}

fn resolve(gh: &Github, repo: &str, id: &str, fixed: Option<&str>) -> Resolved {
    let fetched = match fixed {
        Some(tag) => gh.get(&format!("/repos/{repo}/releases/tags/{tag}")).map(|v| vec![v]),
        None => gh.get(&format!("/repos/{repo}/releases?per_page=100")).and_then(|v| match v {
            Value::Array(a) => Ok(a),
            _ => bail!("unexpected answer from GitHub"),
        }),
    };
    let releases = match fetched {
        Ok(r) => r,
        Err(e) => return Resolved { latest: None, check: format!("error: {e:#}"), per_tag: BTreeMap::new(), first: None, last: None },
    };
    let mut candidates: Vec<(semver::Version, Value)> = Vec::new();
    let mut per_tag = BTreeMap::new();
    let (mut first, mut last): (Option<String>, Option<String>) = (None, None);
    for r in &releases {
        if r.get("draft").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        let Some(tag) = r.get("tag_name").and_then(Value::as_str) else { continue };
        let Some(version) = tag_version(tag, id) else { continue };
        let assets = r.get("assets").and_then(Value::as_array).cloned().unwrap_or_default();
        let Some(zip) = pick_zip(&assets, id, &version) else { continue };
        let count: u64 = assets
            .iter()
            .filter(|a| a.get("name").and_then(Value::as_str).is_some_and(|n| n.to_ascii_lowercase().ends_with(".zip")))
            .filter_map(|a| a.get("download_count").and_then(Value::as_u64))
            .sum();
        per_tag.insert(tag.to_string(), count);
        let published = r.get("published_at").and_then(Value::as_str).map(|d| d.chars().take(10).collect::<String>());
        if let Some(p) = &published {
            if first.as_ref().is_none_or(|f| p < f) {
                first = Some(p.clone());
            }
            if last.as_ref().is_none_or(|l| p > l) {
                last = Some(p.clone());
            }
        }
        let latest = json!({
            "version": version,
            "tag": tag,
            "prerelease": r.get("prerelease").and_then(Value::as_bool).unwrap_or(false),
            "published_at": r.get("published_at").cloned().unwrap_or(Value::Null),
            "zip": {
                "name": zip.get("name").cloned().unwrap_or(Value::Null),
                "url": zip.get("browser_download_url").cloned().unwrap_or(Value::Null),
                "size": zip.get("size").cloned().unwrap_or(Value::Null),
            }
        });
        candidates.push((parse_version(&version).unwrap(), latest));
    }
    candidates.sort_by(|a, b| b.0.cmp(&a.0));
    let best = candidates.iter().find(|(v, _)| v.pre.is_empty()).or_else(|| candidates.first()).map(|(_, l)| l.clone());
    let check = if best.is_some() { "ok".to_string() } else { "no installable release".to_string() };
    Resolved { latest: best, check, per_tag, first, last }
}

// ---------------------------------------------------------------------------
// Download history (for "trending")
// ---------------------------------------------------------------------------

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn today() -> (i64, String) {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0) as i64;
    let days = secs.div_euclid(86400);
    let (y, m, d) = civil_from_days(days);
    (days, format!("{y:04}-{m:02}-{d:02}"))
}

fn day_number(date: &str) -> Option<i64> {
    let mut p = date.split('-').map(|x| x.parse::<i64>().ok());
    Some(days_from_civil(p.next()??, p.next()??, p.next()??))
}

fn now_iso() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    let (_, date) = today();
    let s = secs % 86400;
    format!("{date}T{:02}:{:02}:{:02}Z", s / 3600, s / 60 % 60, s % 60)
}

/// Updates one entry's history with today's per-tag counts. Returns
/// `{ total, recent, window_days, as_of }`.
fn track_downloads(history: &mut Map<String, Value>, folder: &str, per_tag: &BTreeMap<String, u64>) -> Value {
    let (today_n, today_s) = today();
    let h = history.entry(folder.to_string()).or_insert_with(|| json!({ "tags": {}, "samples": [] }));
    let tags = h["tags"].as_object_mut().unwrap();
    // download_count resets when an asset is re-uploaded and old releases
    // drop off the API's first page: keep the highest count ever seen.
    for (t, c) in per_tag {
        let prev = tags.get(t).and_then(Value::as_u64).unwrap_or(0);
        tags.insert(t.clone(), json!(prev.max(*c)));
    }
    let total: u64 = tags.values().filter_map(Value::as_u64).sum();
    let samples = h["samples"].as_array_mut().unwrap();
    samples.retain(|s| s["date"].as_str() != Some(today_s.as_str()));
    samples.push(json!({ "date": today_s, "total": total }));
    if samples.len() > 120 {
        let cut = samples.len() - 120;
        samples.drain(..cut);
    }
    let dated: Vec<(i64, u64)> = samples.iter().filter_map(|s| Some((day_number(s["date"].as_str()?)?, s["total"].as_u64()?))).collect();
    let base = dated.iter().filter(|(d, _)| today_n - d >= 30).max_by_key(|(d, _)| *d).or_else(|| dated.iter().filter(|(d, _)| today_n - d >= 1).min_by_key(|(d, _)| *d));
    let (recent, window) = match base {
        Some((d, t)) => (json!(total.saturating_sub(*t)), json!(today_n - d)),
        None => (Value::Null, Value::Null),
    };
    json!({ "total": total, "recent": recent, "window_days": window, "as_of": now_iso() })
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

fn render_html(mods: &[Value], generated: &str, repo: Option<&str>) -> String {
    // How a player gets this index into the launcher.
    let how = match repo {
        Some(r) if r.eq_ignore_ascii_case("Jack-The-Gamer/DigimonWorldsReCompiled-mod-index") => "This index is built into the launcher. ".to_string(),
        Some(r) => format!("To list them there, add <code>{}</code> under <b>Find mods → Indexes…</b>. ", esc(r)),
        None => String::new(),
    };
    let mut cards = String::new();
    for m in mods {
        let g = |k: &str| m.get(k).and_then(Value::as_str).unwrap_or("");
        let games: Vec<&str> = m.get("games").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
        let version = m.pointer("/latest/version").and_then(Value::as_str).unwrap_or(g("version"));
        let thumb = match m.get("thumbnail").and_then(Value::as_str) {
            Some(t) => format!("<img src=\"{}\" alt=\"\">", esc(t)),
            None => format!("<div class=\"ph\">{}</div>", esc(&g("title").chars().next().unwrap_or('?').to_string())),
        };
        let downloads = m.pointer("/downloads/total").and_then(Value::as_u64).map(|d| format!(" · {d} downloads")).unwrap_or_default();
        cards.push_str(&format!(
            "<article>{thumb}<div><h2><a href=\"{repo}\">{title}</a> <small>v{version} · by {author}</small></h2><p>{summary}</p><p class=\"meta\">{games} · {cats}{downloads}</p></div></article>\n",
            repo = esc(g("repo")),
            title = esc(g("title")),
            version = esc(version),
            author = esc(g("author")),
            summary = esc(g("summary")),
            games = esc(&games.join(", ").to_uppercase()),
            cats = esc(&m.get("categories").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", ")).unwrap_or_default()),
        ));
    }
    if mods.is_empty() {
        cards.push_str("<p>No mods are listed yet. Be the first!</p>");
    }
    format!(
        r#"<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Digimon Worlds Re:Compiled – mod index</title>
<style>
:root {{ color-scheme: dark; --bg:#0d0e12; --card:#1c1f26; --muted:#969ca8; --accent:#ff8c1a; }}
body {{ margin:0; background:var(--bg); color:#e8e8ea; font:16px/1.5 system-ui,sans-serif; }}
main {{ max-width:900px; margin:0 auto; padding:24px 16px; }}
h1 {{ margin:0 0 4px; }} h1 span {{ color:var(--accent); }}
article {{ display:flex; gap:16px; background:var(--card); border-radius:10px; padding:12px; margin:12px 0; }}
article img, .ph {{ width:128px; height:96px; object-fit:cover; border-radius:6px; flex:none; background:#161a22; }}
.ph {{ display:flex; align-items:center; justify-content:center; font-size:40px; color:#3a4150; }}
h2 {{ margin:0; font-size:18px; }} h2 small {{ color:var(--muted); font-weight:normal; font-size:14px; }}
a {{ color:#409cff; }} p {{ margin:4px 0; }} .meta, footer {{ color:var(--muted); font-size:14px; }}
code {{ background:#1c1f26; padding:1px 5px; border-radius:4px; }}
</style></head><body><main>
<h1>Digimon Worlds <span>Re:Compiled</span> mods</h1>
<p>Every mod listed here can be installed from the <b>Mods → Find mods</b> tab in Re:Compiled. {how}A mod lives either in the index itself or in its author's own repository. Listing is not vetting.</p>
<p>Anyone can run a mod index like this one for their own mods: see <a href="https://github.com/Jack-The-Gamer/DigimonWorldsReCompiled-mod-index#your-own-mod-index">Your own mod index</a>.</p>
{cards}
<footer><p>Feed: <a href="data/index.json">data/index.json</a> · generated {generated}</p></footer>
</main></body></html>
"#
    )
}

fn build(root: &Path, repo: Option<&str>, out: &Path, releases: bool, previous: Option<&Path>) -> Result<()> {
    let entries = load_dir(&root.join("mods"), repo)?;
    if validate(&entries, &mut std::io::stdout()) > 0 {
        bail!("fix the errors above first");
    }
    let gh = Github::new();
    let mut history: Map<String, Value> = previous
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|t| serde_json::from_str::<Value>(&t).ok())
        .and_then(|v| v.get("entries").and_then(Value::as_object).cloned())
        .unwrap_or_default();
    let data = out.join("data");
    if data.exists() {
        std::fs::remove_dir_all(&data)?;
    }
    std::fs::create_dir_all(data.join("mods"))?;
    let mut mods: Vec<Value> = Vec::new();
    for e in &entries {
        let dest = data.join("mods").join(&e.folder);
        std::fs::create_dir_all(&dest)?;
        let mut v = Map::new();
        v.insert("folder".into(), json!(e.folder));
        for (k, x) in &e.meta {
            v.insert(k.clone(), x.clone());
        }
        if e.hosted.is_some() {
            v.insert("hosted".into(), json!(true));
        }
        std::fs::copy(e.dir.join("description.md"), dest.join("description.md"))?;
        v.insert("description_url".into(), json!(format!("data/mods/{}/description.md", e.folder)));
        if e.dir.join("thumbnail.png").exists() {
            std::fs::copy(e.dir.join("thumbnail.png"), dest.join("thumbnail.png"))?;
            v.insert("thumbnail".into(), json!(format!("data/mods/{}/thumbnail.png", e.folder)));
        }
        let auto = e.meta.get("automatic_version_check").and_then(Value::as_bool).unwrap_or(true);
        match (e.s("github"), releases && auto) {
            (Some(repo), true) => {
                let r = resolve(&gh, repo, e.s("id").unwrap_or(""), e.s("fixed_release_tag"));
                println!("{:<32} {}", e.folder, if r.check == "ok" { format!("v{}", r.latest.as_ref().unwrap()["version"].as_str().unwrap_or("?")) } else { r.check.clone() });
                v.insert("latest".into(), r.latest.unwrap_or(Value::Null));
                v.insert("update_check".into(), json!(r.check));
                let dl = if r.per_tag.is_empty() && !history.contains_key(&e.folder) { Value::Null } else { track_downloads(&mut history, &e.folder, &r.per_tag) };
                v.insert("downloads".into(), dl);
                v.insert("first_release".into(), r.first.map(Value::from).unwrap_or(Value::Null));
                v.insert("last_release".into(), r.last.map(Value::from).unwrap_or(Value::Null));
            }
            (Some(_), false) if auto => {
                v.insert("update_check".into(), json!("pending"));
            }
            _ => {
                v.insert("update_check".into(), json!("off"));
                v.insert("downloads".into(), Value::Null);
            }
        }
        mods.push(Value::Object(v));
    }
    mods.sort_by_key(|m| m["title"].as_str().unwrap_or("").to_lowercase());
    let generated = now_iso();
    let feed = json!({
        "schema_version": SCHEMA_VERSION,
        "generated_at": generated,
        "count": mods.len(),
        "categories": CATEGORIES,
        "games": ["dw1", "dw2", "dw3"],
        "mods": mods,
    });
    std::fs::write(data.join("index.json"), serde_json::to_string_pretty(&feed)?)?;
    history.retain(|k, _| entries.iter().any(|e| &e.folder == k));
    std::fs::write(data.join("history.json"), serde_json::to_string(&json!({ "version": 1, "entries": history }))?)?;
    std::fs::write(out.join("index.html"), render_html(feed["mods"].as_array().unwrap(), &generated, repo))?;
    std::fs::write(out.join(".nojekyll"), "")?;
    if root.join("schema/mod.schema.json").exists() {
        std::fs::create_dir_all(out.join("schema"))?;
        std::fs::copy(root.join("schema/mod.schema.json"), out.join("schema/mod.schema.json"))?;
    }
    println!("wrote {} ({} mods)", data.join("index.json").display(), entries.len());
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let flag = |f: &str| args.iter().any(|a| a == f);
    let opt = |f: &str| args.iter().position(|a| a == f).and_then(|i| args.get(i + 1)).cloned();
    let root = PathBuf::from(opt("--root").unwrap_or_else(|| ".".into()));
    let repo = this_repo(&root, opt("--repo"));
    match args.first().map(String::as_str) {
        Some("validate") => {
            let values = [opt("--root"), opt("--repo")];
            let named: Vec<&String> = args[1..].iter().filter(|a| !a.starts_with("--")).filter(|a| !values.iter().any(|v| v.as_ref() == Some(*a))).collect();
            let mut entries = Vec::new();
            if named.is_empty() {
                entries.extend(load_dir(&root.join("mods"), repo.as_deref())?);
                if flag("--examples") {
                    entries.extend(load_dir(&root.join("examples"), repo.as_deref())?);
                }
            } else {
                for n in named {
                    entries.push(load_entry(Path::new(n), repo.as_deref())?);
                }
            }
            let n = validate(&entries, &mut std::io::stdout());
            if n > 0 {
                bail!("{n} error(s)");
            }
            println!("{} entr{} valid", entries.len(), if entries.len() == 1 { "y" } else { "ies" });
            Ok(())
        }
        Some("build") => {
            let out = PathBuf::from(opt("--out").unwrap_or_else(|| "site".into()));
            build(&root, repo.as_deref(), &out, flag("--releases"), opt("--previous").as_deref().map(Path::new))
        }
        // The mods hosted here, one per line: folder, id, version, name
        // (tab-separated), for the release step. Checks go to stderr.
        Some("hosted") => {
            let entries = load_dir(&root.join("mods"), repo.as_deref())?;
            let n = validate(&entries, &mut std::io::stderr());
            if n > 0 {
                bail!("{n} error(s)");
            }
            for e in &entries {
                if let Some(h) = &e.hosted {
                    println!("{}\t{}\t{}\t{}", e.folder, h.id, h.version, h.name.replace(['\t', '\n'], " "));
                }
            }
            Ok(())
        }
        _ => {
            eprintln!("usage:\n  build-index validate [--examples] [--repo owner/repo] [mods/<Author>@<id> ...]\n  build-index build [--releases] [--previous <history.json>] [--out site]\n  build-index hosted [--repo owner/repo]");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        for d in [0, 1, 59, 365, 10957, 20376] {
            let (y, m, dd) = civil_from_days(d);
            assert_eq!(days_from_civil(y, m, dd), d);
        }
        assert_eq!(civil_from_days(20376), (2025, 10, 15));
        assert_eq!(day_number("2026-10-15").unwrap() - day_number("2026-09-15").unwrap(), 30);
    }

    #[test]
    fn versions_and_assets() {
        assert_eq!(tag_version("cool-v1.2", "cool").as_deref(), Some("1.2.0"));
        assert!(tag_version("latest", "cool").is_none());
        let assets = vec![json!({"name":"x.zip","browser_download_url":"u1"}), json!({"name":"cool-1.0.0.zip","browser_download_url":"u2"})];
        assert_eq!(pick_zip(&assets, "cool", "1.0.0").unwrap()["browser_download_url"], "u2");
        assert!(valid_repo("a-b/c.d") && !valid_repo("a/b/c") && !valid_repo("../x"));
    }

    #[test]
    fn hosted_entries() {
        let root = std::env::temp_dir().join(format!("build-index-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let d = root.join("mods").join("Me@cool");
        std::fs::create_dir_all(d.join("mod")).unwrap();
        std::fs::write(d.join("description.md"), "# Cool\n").unwrap();
        let toml = |github: &str| {
            format!(
                "[mod]\nid = \"cool\"\nname = \"Cool Mod\"\nversion = \"1.2\"\nauthor = \"Me\"\ndescription = \"Does cool things.\"\ngame = \"dw1\"\ncategories = [\"QOL\"]\nscript = \"main.lua\"\n{github}"
            )
        };
        std::fs::write(d.join("mod/main.lua"), "").unwrap();
        std::fs::write(d.join("mod/mod.toml"), toml("github = \"Me/index\"\n")).unwrap();
        // Everything comes from mod.toml: no meta.json needed.
        let e = load_entry(&d, Some("Me/index")).unwrap();
        let (err, _) = check(&e);
        assert!(err.is_empty(), "{err:?}");
        assert_eq!(e.s("version"), Some("1.2.0"));
        assert_eq!(e.s("title"), Some("Cool Mod"));
        assert_eq!(e.s("github"), Some("Me/index"));
        assert_eq!(e.s("repo"), Some("https://github.com/Me/index/tree/HEAD/mods/Me@cool"));
        assert_eq!(e.meta["games"], json!(["dw1"]));
        assert_eq!(e.hosted.as_ref().map(|h| h.version.as_str()), Some("1.2.0"));
        // meta.json may add to it, but not contradict it.
        std::fs::write(d.join("meta.json"), r#"{"summary":"Short.","version":"1.1.0"}"#).unwrap();
        let e = load_entry(&d, Some("Me/index")).unwrap();
        assert_eq!(e.s("summary"), Some("Short."));
        assert!(check(&e).0.iter().any(|x| x.contains("leave version out")));
        std::fs::remove_file(d.join("meta.json")).unwrap();
        // mod.toml must point update checks here.
        std::fs::write(d.join("mod/mod.toml"), toml("")).unwrap();
        assert!(check(&load_entry(&d, Some("Me/index")).unwrap()).0.iter().any(|x| x.contains("add github = \"Me/index\"")));
        std::fs::write(d.join("mod/mod.toml"), toml("github = \"Me/index\"\n")).unwrap();
        // Stray files are refused.
        std::fs::write(d.join("notes.txt"), "").unwrap();
        assert!(check(&load_entry(&d, Some("Me/index")).unwrap()).0.iter().any(|x| x.contains("notes.txt")));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn shared_tags() {
        assert!(tags_collide("pack-2", "pack") && tags_collide("pack-v3", "pack") && tags_collide("pack_2", "pack"));
        assert!(!tags_collide("pack-extra", "pack") && !tags_collide("packer", "pack") && !tags_collide("pack", "pack-2"));
        assert_eq!(summarize("one two three", 9), "one two…");
        assert_eq!(summarize("short", 200), "short");
    }

    #[test]
    fn download_tracking() {
        let mut h = Map::new();
        let tags: BTreeMap<String, u64> = [("v1".to_string(), 10), ("v2".to_string(), 5)].into();
        let d = track_downloads(&mut h, "A@a", &tags);
        assert_eq!(d["total"], 15);
        assert!(d["recent"].is_null());
        // A re-uploaded asset (count reset) never lowers the total.
        let tags: BTreeMap<String, u64> = [("v1".to_string(), 2), ("v2".to_string(), 7)].into();
        assert_eq!(track_downloads(&mut h, "A@a", &tags)["total"], 17);
        // Forty days ago the total was 3.
        let (t, _) = today();
        let (y, m, dd) = civil_from_days(t - 40);
        h["A@a"]["samples"].as_array_mut().unwrap().insert(0, json!({"date": format!("{y:04}-{m:02}-{dd:02}"), "total": 3}));
        let d = track_downloads(&mut h, "A@a", &BTreeMap::new());
        assert_eq!((d["recent"].as_u64(), d["window_days"].as_i64()), (Some(14), Some(40)));
    }
}
