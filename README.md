<div align="center">

# office.yazi
### A plugin to preview office documents in <a href="https://github.com/sxyazi/yazi">Yazi <img src="https://github.com/sxyazi/yazi/blob/main/assets/logo.png?raw=true" alt="a duck" width="24px" height="24px"></a>

<img src="https://github.com/macydnah/office.yazi/blob/assets/preview_test.gif" alt="preview test" width="88%">

##

</div>

> [!NOTE]
> This is a personal fork of [macydnah/office.yazi](https://github.com/macydnah/office.yazi), maintained for my own dotfiles setup
> because the upstream repository was unmaintained. Changes made in this fork:
> - `main.lua`: run `soffice` instead of `libreoffice` — on macOS (Homebrew cask `libreoffice`) only `soffice` is
>   put on `PATH`, so the upstream `libreoffice` call always failed. (On Linux, `soffice` is generally available too,
>   e.g. as a symlink shipped alongside the `libreoffice` wrapper — if your distro truly lacks it, adjust the
>   command back to `libreoffice`.)
> - `main.lua`: removed the call to `ya.preview_widgets(job, {})`, which was deprecated/removed from Yazi's plugin
>   API and made every preview fail with `attempt to call a nil value (field 'preview_widgets')` on recent Yazi
>   versions (confirmed on Yazi 26.5.6). The call only ever passed an empty widget list, so dropping it is a no-op
>   for behavior.
> - `README.md`: updated the example config below from the old `name = "*.docx"` rule key to `url = "*.docx"`,
>   matching current Yazi config schema.
> - `main.lua`: replaced `ya.manager_emit(...)` (seek) and `ya.mgr_emit(...)` (preload error recovery) with
>   `ya.emit(...)`. Both were older, deprecated aliases; `manager_emit` in particular no longer works on recent
>   Yazi, so paging with `J`/`K` while previewing a document silently did nothing and stayed stuck on page 1.
> - `main.lua`: reworked paging past the last page. The plugin used to ask LibreOffice to export one page at a
>   time via `PageRange`, and had to *guess* whether a missing output file meant "no such page" or a genuine
>   conversion failure — LibreOffice exits `0` either way, and the only distinguishing signal was an internal,
>   version/locale-dependent log string. `doc2pdf` now converts the *whole* document to PDF once (cached per
>   file), and `preload` reads the exact page count from that PDF via `pdfinfo` before extracting a page with
>   `pdftoppm`. Paging past the end now jumps straight to the real last page instead of guessing and stepping
>   back one page at a time, a genuine conversion failure always surfaces as an error, and paging through an
>   already-open document is much faster since only the first page triggers a `soffice` conversion.
> - `main.lua`: follow-up fixes to the above, found by another review pass: the per-document PDF cache is now
>   keyed on the file's mtime/size as well as its url, so editing a file and re-previewing it no longer serves a
>   stale conversion, and each file gets its own cache subdirectory so two files that happen to share a basename
>   can no longer race on the same intermediate output path. The "past the end of the document" case now returns
>   an error alongside the corrective `peek`, matching every other failure path — returning bare `true` there
>   skipped `M:peek`'s guard and could flash `ya.image_show` against a cache slot that was never written. A
>   `soffice`/`pdfinfo` process that fails to spawn at all is now handled explicitly instead of crashing on a nil
>   dereference, and a missing/failing `pdfinfo` now logs a warning instead of silently disabling the
>   out-of-range-page guard.
> - `main.lua`: a fifth review pass found that a source document LibreOffice "successfully" converts to a
>   0-page PDF (corrupt/protected/etc.) made the "past the end" branch compute a corrective target identical to
>   `job.skip = 0`, causing an infinite `peek`/`preload`/`emit` loop for that file — a 0-page conversion is now
>   treated as its own error instead. `pdfinfo`'s page count is now memoized per cached PDF instead of
>   re-spawned on every page turn (the count can't change once a version is cached), the "pdfinfo missing"
>   warning above now actually only logs once per session as its comment claims, a losing `fs.rename` in a
>   same-file race is now treated as success instead of a spurious error (the winner already cached the file),
>   and a redundant `io.open` existence check before `fs.rename` — which already reports a missing file on its
>   own — was removed. Deliberately **not** addressed for now: cache entries for old versions of an edited file
>   are not evicted (each new version gets its own subdirectory, so `/tmp` usage grows with edits; acceptable
>   for a personal, session-scoped tmpdir), and the cache key doesn't fall back to anything if a filesystem
>   doesn't report `mtime` (rare enough in practice not to be worth the complexity).

## Installation
> [!TIP]
> Installing this plugin with `ya` will conveniently clone the plugin from GitHub,
> copy it to your plugins directory, and update the `package.toml` to lock its version [^1].
> 
> To install it with `ya` run:
> ```sh
> ya pkg add masaki39/office
> ```

> Or if you prefer a manual approach:
> ```sh
> ## For linux and MacOS
> git clone https://github.com/masaki39/office.yazi.git ~/.config/yazi/plugins/office.yazi
> 
> ## For Windows
> git clone https://github.com/masaki39/office.yazi.git %AppData%\yazi\config\plugins\office.yazi
> ```

## Usage
In your `yazi.toml` add rules to preloaders[^2] and previewers[^3] to run `office` plugin with office documents.

> [!NOTE]
> Your config may be different depending if you're *appending*, *prepending* or *overriding* default rules.
> If unsure, take a look at [Configuration](https://yazi-rs.github.io/docs/configuration/overview)[^4]
> and [Configuration mixing](https://yazi-rs.github.io/docs/configuration/overview#mixing)[^5]

For a general usecase, you may use the following rules
```toml
[plugin]

prepend_preloaders = [
    # Office Documents
    { mime = "application/openxmlformats-officedocument.*", run = "office" },
    { mime = "application/oasis.opendocument.*", run = "office" },
    { mime = "application/ms-*", run = "office" },
    { mime = "application/msword", run = "office" },
    { url = "*.docx", run = "office" },
]

prepend_previewers = [
    # Office Documents
    { mime = "application/openxmlformats-officedocument.*", run = "office" },
    { mime = "application/oasis.opendocument.*", run = "office" },
    { mime = "application/ms-*", run = "office" },
    { mime = "application/msword", run = "office" },
    { url = "*.docx", run = "office" },
]
```

## Dependencies
> [!IMPORTANT]
> Make sure that these commands are installed in your system and can be found in `PATH`:
>
> - `soffice` (installed with LibreOffice; on some Linux distros the wrapper script is named `libreoffice`
>   instead — if so, edit `main.lua` to use that name)
> - `pdftoppm`
> - `pdfinfo` (both are part of `poppler`/`poppler-utils`, usually installed alongside `pdftoppm`)

## License
office.yazi is licensed under the terms of the [MIT License](LICENSE)

[^1]: [The official package manager for Yazi](https://yazi-rs.github.io/docs/cli)
[^2]: [Preloaders rules](https://yazi-rs.github.io/docs/configuration/yazi#plugin.preloaders)
[^3]: [Previewers rules](https://yazi-rs.github.io/docs/configuration/yazi#plugin.previewers)
[^4]: [Configuration](https://yazi-rs.github.io/docs/configuration/overview)
[^5]: [Configuration mixing](https://yazi-rs.github.io/docs/configuration/overview#mixing)
