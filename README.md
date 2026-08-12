<div align="center">

# office.yazi
### A plugin to preview office documents in <a href="https://github.com/sxyazi/yazi">Yazi <img src="https://github.com/sxyazi/yazi/blob/main/assets/logo.png?raw=true" alt="a duck" width="24px" height="24px"></a>

<img src="https://github.com/macydnah/office.yazi/blob/assets/preview_test.gif" alt="preview test" width="88%">

##

</div>

> [!NOTE]
> This is a personal fork of [macydnah/office.yazi](https://github.com/macydnah/office.yazi), maintained for my own
> dotfiles setup because the upstream repository was unmaintained. Changes made in this fork:
> - Use `soffice` instead of `libreoffice` (only `soffice` is on `PATH` with the macOS Homebrew cask), and replace
>   the deprecated `ya.manager_emit`/`ya.mgr_emit`/`ya.preview_widgets` calls with their current Yazi APIs — all
>   of these had silently stopped working (broken previews, and `J`/`K` paging stuck on page 1) on recent Yazi.
> - Convert the whole document to PDF once per file (cached, keyed on url + mtime/size) instead of asking
>   LibreOffice to export one page at a time, and read the real page count via `pdfinfo` instead of guessing
>   from LibreOffice's inconclusive exit status. Paging is faster (only the first page triggers a conversion)
>   and paging past the last page reliably renders the real last page instead of a blank/black preview.
> - Update the example config in this README from the old `name = "*.docx"` rule key to `url = "*.docx"`.

<details>
<summary>Fork changelog (older/incremental fixes)</summary>

> - Fixed a bug where a source document that "successfully" converts to a 0-page PDF (corrupt/protected/etc.)
>   caused an infinite peek loop.
> - Fixed a race where two overlapping conversions of the same not-yet-cached file could collide on the same
>   intermediate output path, and memoized `pdfinfo`'s page count instead of re-spawning it on every page turn.
> - Fixed `M:seek` (paging past the last page) requesting an ever-growing, unclamped page index from Yazi core:
>   the document would stay stuck on the last page until "previous" was pressed as many times as "next" had
>   overshot by. The requested page is now clamped to the last known page count before being requested.

</details>

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
