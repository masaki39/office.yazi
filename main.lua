--- @since 25.2.7

local M = {}

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err = self:preload(job)
	if not ok or err then
		return
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	ya.image_show(cache, job.area)
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		ya.emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

-- Convert the *whole* document to PDF once and cache it, instead of asking
-- LibreOffice to export a single page at a time. This is deliberately
-- different from a straightforward per-page `--convert-to ... PageRange`
-- call: LibreOffice exits 0 and prints nothing conclusive when a requested
-- page is past the end of the document (it just skips writing the file), so
-- there is no reliable way to tell "no such page" apart from a genuine
-- conversion failure by probing one page at a time. Converting once gives us
-- an authoritative page count via `pdfinfo`, and every page after the first
-- is a cheap `pdftoppm` extraction from the cached PDF instead of a fresh
-- `soffice` invocation.
function M:doc2pdf(job)
	-- Key the cache dir on the file's url *and* its mtime/size, not just the
	-- url: a stale PDF from before the source file was last edited must never
	-- be served, and scoping each source file to its own subdirectory also
	-- means two different files that happen to share a basename (or repeated
	-- concurrent preloads of the same file) can never race on the same
	-- intermediate output path below.
	local cha = job.file.cha
	local key = ya.hash(tostring(job.file.url) .. "|" .. tostring(cha and cha.mtime) .. "|" .. tostring(cha and cha.len))
	local dir = "/tmp/yazi-" .. ya.uid() .. "/" .. ya.hash("office.yazi") .. "/" .. key .. "/"
	local pdf = dir .. "cached.pdf"

	if fs.cha(Url(pdf)) then
		return pdf
	end

	--[[	For Future Reference: Regarding `libreoffice` as preconverter
	  1. It prints errors to stdout (always, doesn't matter if it succeeded or it failed)
	  2. Always writes the converted files to the filesystem, so no "Mario|Bros|Piping|Magic" for the data stream (https://ask.libreoffice.org/t/using-convert-to-output-to-stdout/38753)
	  3. The `pdf:draw_pdf_Export` filter needs literal double quotes when defining its options (https://help.libreoffice.org/latest/en-US/text/shared/guide/pdf_params.html?&DbPAR=SHARED&System=UNIX#generaltext/shared/guide/pdf_params.xhp)
	  3.1 Regarding double quotes and Lua strings, see https://www.lua.org/manual/5.1/manual.html#2.1 --]]
	local libreoffice, spawn_err = Command("soffice")
		:arg({
			"--headless",
			"--convert-to",
			"pdf:draw_pdf_Export",
			"--outdir",
			dir,
			tostring(job.file.url),
		})
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not libreoffice then
		return nil, Err("Failed to start `soffice`, error: %s", spawn_err)
	elseif not libreoffice.status.success then
		local output = libreoffice.stdout .. libreoffice.stderr
		local version = (output:match("LibreOffice .+") or ""):gsub("%\n.*", "")
		local error = (output:match("Error:? .+") or ""):gsub("%\n.*", "")
		if version ~= "" or error ~= "" then
			ya.err((version or "LibreOffice") .. " " .. (error or "Unknown error"))
		end
		return nil, Err("Failed to convert `%s` to a temporary PDF", job.file.name)
	end

	local out = dir .. job.file.name:gsub("%.[^%.]+$", ".pdf")

	local renamed, rn_err = fs.rename(Url(out), Url(pdf))
	if not renamed then
		if fs.cha(Url(pdf)) then
			-- A concurrent doc2pdf call for the same file already won this race
			-- and moved `out` into place first; that's success, not a failure.
			return pdf
		end
		return nil, Err("Failed to cache `%s` as `%s`: %s", out, pdf, rn_err)
	end

	return pdf
end

-- Total page count of `pdf`, or nil if it can't be determined. `pdf`'s cache
-- path is keyed on the source file's mtime/size (see doc2pdf), so its page
-- count can never change for a given cache entry — memoize it instead of
-- re-spawning `pdfinfo` on every single page turn.
function M:page_count(pdf)
	M.page_counts = M.page_counts or {}
	local cached = M.page_counts[pdf]
	if cached ~= nil then
		return cached
	end

	local output = Command("pdfinfo"):arg({ tostring(pdf) }):stdout(Command.PIPED):stderr(Command.PIPED):output()
	if not output or not output.status.success then
		return nil
	end

	local total = tonumber(output.stdout:match("Pages:%s*(%d+)"))
	M.page_counts[pdf] = total
	return total
end

function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	local pdf, err = self:doc2pdf(job)
	if not pdf then
		return true, Err("    " .. "%s", err)
	end

	local total = self:page_count(pdf)
	if not total then
		-- `pdfinfo` failing (e.g. missing from PATH) only disables the
		-- out-of-range guard below, it doesn't stop rendering — but that
		-- should never happen silently, so surface it once per session rather
		-- than on every single page turn.
		if not M.warned_no_pdfinfo then
			M.warned_no_pdfinfo = true
			ya.err("`pdfinfo` failed or is not installed; paging past the last page will not be caught")
		end
	elseif total == 0 then
		-- A "successfully" converted but empty PDF (corrupt/protected source,
		-- ...) has no valid page at all. Must not fall into the branch below:
		-- its target page would be math.max(0, 0-1) = 0, identical to the
		-- job.skip = 0 that got us here, which would emit a `peek` back to the
		-- same skip forever.
		return true, Err("`%s` converted to an empty PDF (0 pages)", job.file.name)
	elseif job.skip >= total then
		-- Past the end of the document: we know the exact last page from
		-- `pdfinfo`, so jump straight there instead of stepping back one page
		-- (and one failed conversion) at a time. This must return an error too,
		-- not just `true`: an empty `ok`/`err` pair would fall through to
		-- `M:peek`'s `ya.image_show`, which would show whatever (nothing) was
		-- cached for this out-of-range `job.skip` before the corrective peek
		-- above lands.
		ya.emit("peek", { total - 1, only_if = job.file.url, upper_bound = true })
		return true, Err("Page %d is past the end of `%s` (%d pages)", job.skip + 1, job.file.name, total)
	end

	local output, err = Command("pdftoppm")
		:arg({
			"-singlefile",
			"-jpeg",
			"-jpegopt",
			"quality=" .. rt.preview.image_quality,
			"-f",
			job.skip + 1,
			tostring(pdf),
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output then
		return true, Err("Failed to start `pdftoppm`, error: %s", err)
	elseif not output.status.success then
		return true, Err("Failed to convert %s to image, stderr: %s", pdf, output.stderr)
	end

	return fs.write(cache, output.stdout)
end

return M
