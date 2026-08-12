--- @since 25.2.7

local M = {}

-- Run an already-configured `cmd`, returning its Output on success or
-- `nil, Err(...)` if the process couldn't even be spawned (missing binary,
-- etc.). Doesn't look at `output.status.success` — callers still need to
-- branch on that themselves, since a non-zero exit isn't always a hard
-- failure (e.g. LibreOffice's own quirks around PageRange, handled by the
-- caller in doc2pdf).
local function run(name, cmd)
	local output, err = cmd:output()
	if not output then
		return nil, Err("Failed to start `%s`, error: %s", name, err)
	end
	return output
end

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
	-- be served, and scoping each source file to its own subdirectory means
	-- two different files that happen to share a basename can never collide
	-- in the cache.
	local cha = job.file.cha
	local key = ya.hash(tostring(job.file.url) .. "|" .. tostring(cha and cha.mtime) .. "|" .. tostring(cha and cha.len))
	local base = "/tmp/yazi-" .. ya.uid() .. "/" .. ya.hash("office.yazi") .. "/" .. key .. "/"
	local pdf = base .. "cached.pdf"

	if fs.cha(Url(pdf)) then
		return pdf
	end

	-- soffice writes to `--outdir <scratch>/<basename>.pdf` before we rename
	-- it into the stable `pdf` cache path. Give every conversion attempt its
	-- own scratch directory (an in-process counter is enough: two concurrent
	-- doc2pdf calls only ever interleave at an `await` point inside `run`,
	-- never between reading and incrementing this) so that two overlapping
	-- attempts for the same file — plausible if a page is turned again before
	-- the first conversion finishes — never have two `soffice` processes
	-- writing the same file at once. Only the final rename below is still
	-- shared, and that race is already handled: the loser just adopts the
	-- winner's result.
	M.scratch_seq = (M.scratch_seq or 0) + 1
	local scratch = base .. "scratch-" .. M.scratch_seq .. "/"

	--[[	For Future Reference: Regarding `libreoffice` as preconverter
	  1. It prints errors to stdout (always, doesn't matter if it succeeded or it failed)
	  2. Always writes the converted files to the filesystem, so no "Mario|Bros|Piping|Magic" for the data stream (https://ask.libreoffice.org/t/using-convert-to-output-to-stdout/38753)
	  3. The `pdf:draw_pdf_Export` filter needs literal double quotes when defining its options (https://help.libreoffice.org/latest/en-US/text/shared/guide/pdf_params.html?&DbPAR=SHARED&System=UNIX#generaltext/shared/guide/pdf_params.xhp)
	  3.1 Regarding double quotes and Lua strings, see https://www.lua.org/manual/5.1/manual.html#2.1 --]]
	local libreoffice, err = run(
		"soffice",
		Command("soffice")
			:arg({
				"--headless",
				"--convert-to",
				"pdf:draw_pdf_Export",
				"--outdir",
				scratch,
				tostring(job.file.url),
			})
			:stdin(Command.NULL)
			:stdout(Command.PIPED)
			:stderr(Command.PIPED)
	)

	if not libreoffice then
		return nil, err
	elseif not libreoffice.status.success then
		local output = libreoffice.stdout .. libreoffice.stderr
		local version = (output:match("LibreOffice .+") or ""):gsub("%\n.*", "")
		local error = (output:match("Error:? .+") or ""):gsub("%\n.*", "")
		if version ~= "" or error ~= "" then
			ya.err((version or "LibreOffice") .. " " .. (error or "Unknown error"))
		end
		fs.remove("dir_all", Url(scratch))
		return nil, Err("Failed to convert `%s` to a temporary PDF", job.file.name)
	end

	local out = scratch .. job.file.name:gsub("%.[^%.]+$", ".pdf")

	local renamed, rn_err = fs.rename(Url(out), Url(pdf))
	fs.remove("dir_all", Url(scratch))
	if not renamed then
		if fs.cha(Url(pdf)) then
			-- A concurrent doc2pdf call for the same file already won this race
			-- and moved its own output into place first; that's success, not a
			-- failure.
			return pdf
		end
		return nil, Err("Failed to cache `%s` as `%s`: %s", out, pdf, rn_err)
	end

	return pdf
end

-- Total page count of `pdf`, or nil if it can't be determined. `pdf`'s cache
-- path is keyed on the source file's mtime/size (see doc2pdf), so its page
-- count can never change for a given cache entry — memoize it (including
-- failures, via a `false` sentinel so a nil result is still distinguishable
-- from "not computed yet") instead of re-spawning `pdfinfo` on every single
-- page turn.
function M:page_count(pdf)
	M.page_counts = M.page_counts or {}
	local cached = M.page_counts[pdf]
	if cached ~= nil then
		return cached or nil
	end

	local output = run("pdfinfo", Command("pdfinfo"):arg({ tostring(pdf) }):stdout(Command.PIPED):stderr(Command.PIPED))
	if not output or not output.status.success then
		M.page_counts[pdf] = false
		return nil
	end

	local total = tonumber(output.stdout:match("Pages:%s*(%d+)"))
	M.page_counts[pdf] = total or false
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
		-- `pdfinfo` failing (e.g. missing from PATH) disables the exact
		-- out-of-range guard below, but pdftoppm's own "past the last page"
		-- error further down is still parsed as a fallback — this should
		-- never happen silently, though, so surface it once per session
		-- rather than on every single page turn.
		if not M.warned_no_pdfinfo then
			M.warned_no_pdfinfo = true
			ya.err("`pdfinfo` failed or is not installed; falling back to a less precise page-range check")
		end
	elseif total == 0 then
		-- A "successfully" converted but empty PDF (corrupt/protected source,
		-- ...) has no valid page at all. Must not fall into the branch below:
		-- there is no last page to clamp `job.skip` to.
		return true, Err("`%s` converted to an empty PDF (0 pages)", job.file.name)
	elseif job.skip >= total then
		-- Past the end of the document: we know the exact last page from
		-- `pdfinfo`, so render *that* instead of stepping back one page (and
		-- one failed conversion) at a time.
		--
		-- Deliberately not corrected via a follow-up `ya.emit("peek", ...)`:
		-- that used to ask core to peek again at total - 1, but core's
		-- same_url/same_file checks (which decide whether the *previous*
		-- in-flight peek gets left alone or aborted) compare against a
		-- preview lock that only `ya.preview_widget`/`_code` ever populate —
		-- `ya.image_show`, the only thing this plugin calls, never does. So
		-- every single peek — including the corrective one — aborts whatever
		-- is currently in flight, which can be *this very call* racing its
		-- own follow-up and losing, leaving nothing shown at all. Clamping
		-- `job.skip` locally and rendering the last page under the
		-- originally-requested (out-of-range) cache slot avoids ever
		-- round-tripping through core for the correction.
		job.skip = total - 1
	end

	local function render(skip)
		return run(
			"pdftoppm",
			Command("pdftoppm")
				:arg({
					"-singlefile",
					"-jpeg",
					"-jpegopt",
					"quality=" .. rt.preview.image_quality,
					"-f",
					skip + 1,
					tostring(pdf),
				})
				:stdout(Command.PIPED)
				:stderr(Command.PIPED)
		)
	end

	local output, err = render(job.skip)

	if not output then
		return true, err
	elseif not output.status.success then
		-- Only relevant when `total` above is nil (no `pdfinfo`): pdftoppm's
		-- own validation of the page we asked for reports the document's real
		-- last page, so retry against that directly — same reasoning as the
		-- `job.skip >= total` branch above for why this doesn't round-trip
		-- through a follow-up `peek` instead.
		local last = not total and tonumber(output.stderr:match("the last page %((%d+)%)"))
		if last and job.skip > last - 1 then
			job.skip = math.max(0, last - 1)
			output, err = render(job.skip)
		end
		if not output then
			return true, err
		elseif not output.status.success then
			return true, Err("Failed to convert %s to image, stderr: %s", pdf, output.stderr)
		end
	end

	return fs.write(cache, output.stdout)
end

return M
