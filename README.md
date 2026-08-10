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

## License
office.yazi is licensed under the terms of the [MIT License](LICENSE)

[^1]: [The official package manager for Yazi](https://yazi-rs.github.io/docs/cli)
[^2]: [Preloaders rules](https://yazi-rs.github.io/docs/configuration/yazi#plugin.preloaders)
[^3]: [Previewers rules](https://yazi-rs.github.io/docs/configuration/yazi#plugin.previewers)
[^4]: [Configuration](https://yazi-rs.github.io/docs/configuration/overview)
[^5]: [Configuration mixing](https://yazi-rs.github.io/docs/configuration/overview#mixing)
