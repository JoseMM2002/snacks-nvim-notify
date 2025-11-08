local M = {}

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", {}, opts or {})
	vim.api.nvim_create_user_command("SnacksNotifications", function()
		M.notifications_history()
	end, {
		desc = "Show notifications history using snacks-nvim picker",
	})
end

local function history_to_items(history)
	local items = {}
	for _, h in ipairs(history or {}) do
		local cat = (h.title and h.title[1]) or ""
		local clock = (h.title and h.title[2]) or ""
		local msg = table.concat(h.message or {}, " ")
		local lvl = (h.level or "INFO"):upper()
		local icon = h.icon or ""
		local text = string.format("[%s] %s %s — %s", lvl, clock, cat, msg)
		table.insert(items, {
			text = text,
			id = h.id,
			level = lvl,
			icon = icon,
			category = cat,
			clock = clock,
			message = msg,
			raw = h,
		})
	end
	table.sort(items, function(a, b)
		local ta = (a.raw and a.raw.time) or 0
		local tb = (b.raw and b.raw.time) or 0
		return ta > tb
	end)
	return items
end

local function level_hl(level)
	local lvl = (level or "INFO"):upper()
	return "Notify" .. lvl .. "Title"
end

local function fmt_item(item)
	local msg = item.message or ""
	if #msg > 120 then
		msg = msg:sub(1, 117) .. "..."
	end
	local lvl = (item.level or "INFO"):upper()
	local notify_icon_hl = "Notify" .. lvl .. "Icon"
	local notify_title_hl = "Notify" .. lvl .. "Title"

	return {
		{ item.icon or "", notify_icon_hl },
		{ " | ", notify_icon_hl },
		{ item.level, level_hl(item.level) },
		{ "  " },
		{ item.category or "", "Directory" },
		{ "  " },
		{ item.clock or "", "Comment" },
		{ "  " },
		{ msg, notify_title_hl },
	}
end

local function open_float(opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * (opts.w or 0.6))
	local height = math.floor(vim.o.lines * (opts.h or 0.5))
	local row = math.floor((vim.o.lines - height) / 2 - 1)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = opts.border or "rounded",
		width = width,
		height = height,
		row = row,
		col = col,
		noautocmd = true,
	})

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.wo[win].wrap = false
	vim.wo[win].conceallevel = 2

	return buf, win
end

-- Build title + body lines consistently for preview and confirm
function M.build_lines(item)
	local it = item or {}
	local notif = it.raw or {}
	local icon = it.icon or notif.icon or ""
	local category = it.category or (notif.title and notif.title[1]) or "Notify"
	local clock = it.clock or (notif.title and notif.title[2]) or ""

	local lines = {}
	local title_prefix = (icon ~= "" and (icon .. " | ") or "")
	local title_text = string.format("%s%s%s", title_prefix, category or "", (clock ~= "" and ("  " .. clock) or ""))
	table.insert(lines, title_text)

	if type(notif.message) == "table" then
		for _, m in ipairs(notif.message) do
			table.insert(lines, tostring(m))
		end
	elseif notif.message ~= nil then
		table.insert(lines, tostring(notif.message))
	elseif it.message then
		table.insert(lines, tostring(it.message))
	end

	return lines, icon
end

-- Apply window options and level-based border highlight
function M.apply_window_opts(win, level)
	if not (win and vim.api.nvim_win_is_valid(win)) then
		return
	end
	vim.wo[win].wrap = true
	vim.wo[win].conceallevel = 2
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	local border_hl = "Notify" .. (level or "INFO") .. "Border"
	pcall(vim.api.nvim_set_option_value, "winhighlight", "FloatBorder:" .. border_hl, { win = win })
end

-- Highlight the icon and title part on the first line
function M.highlight_title(buf, level, icon, first_line)
	local ns = vim.api.nvim_create_namespace("snacks_notify_title_hl")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local icon_hl = "Notify" .. (level or "INFO") .. "Icon"
	local title_hl = "Notify" .. (level or "INFO") .. "Title"
	local first = first_line or ""
	-- icon prefix includes " | " in build_lines, but we only color the icon chars
	local only_icon = (icon ~= "" and (icon .. " ") or "")
	local icon_len = icon ~= "" and vim.fn.strdisplaywidth(only_icon) or 0
	if icon_len > 0 then
		vim.hl.range(buf, ns, icon_hl, { 0, 0 }, { 0, icon_len }, { inclusive = false })
	end
	vim.hl.range(buf, ns, title_hl, { 0, icon_len }, { 0, #first }, { inclusive = false })
end

function M.preview_notify(ctx)
	local ok, err = pcall(function()
		local it = ctx.item or {}
		local notif = it.raw or {}
		local level = (it.level or notif.level or "INFO"):upper()

		local buf = ctx.bufnr or ctx.buf
		local win = ctx.win or ctx.winid

		local lines, icon = M.build_lines(it)

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].modifiable = false

		M.apply_window_opts(win, level)
		M.highlight_title(buf, level, icon, lines[1] or "")
	end)
	if not ok then
		vim.notify("preview_notify error: " .. tostring(err), vim.log.levels.ERROR)
	end
	if ctx.done then
		ctx.done()
	end
end

function M.notifications_history()
	local Snacks = require("snacks")
	local notify = require("notify")
	local history = notify.history()
	local items = history_to_items(history)

	Snacks.picker({
		title = "Notifications History",
		items = items,
		format = fmt_item,

		-- inline preview using our module function
		preview = function(ctx)
			M.preview_notify(ctx)
		end,

		confirm = function(picker, item)
			picker:close()

			local notif = item.raw or {}
			local level = (item.level or notif.level or "INFO"):upper()
			local buf, win = open_float({ w = 0.65, h = 0.5, border = "rounded" })

			local lines, icon = M.build_lines(item)

			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].modifiable = false
			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].bufhidden = "wipe"
			vim.bo[buf].swapfile = false

			M.apply_window_opts(win, level)
			M.highlight_title(buf, level, icon, lines[1] or "")

			local function close_win()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
			end
			vim.keymap.set("n", "q", close_win, { buffer = buf, nowait = true, silent = true })
			vim.keymap.set("n", "<Esc>", close_win, { buffer = buf, nowait = true, silent = true })
		end,
	})
end

return M
