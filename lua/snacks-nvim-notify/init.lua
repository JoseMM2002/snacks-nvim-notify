local M = {}

M.opts = {
	width = 0.6,
	height = 0.5,
	border = "rounded",
	truncate_width = 80,
}

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

local function fmt_item(item)
	local msg = item.message or ""
	if #msg > 120 then
		msg = msg:sub(1, M.opts.truncate_width) .. "..."
	end
	local lvl = (item.level or "INFO"):upper()
	local notify_icon_hl = "Notify" .. lvl .. "Icon"
	local notify_title_hl = "Notify" .. lvl .. "Title"
	local nottify_message_hl = "Notify" .. lvl .. "Body"

	return {
		{ item.clock or "", "Comment" },
		{ "  " },
		{ item.icon or "", notify_icon_hl },
		{ " ", notify_icon_hl },
		{ item.level, notify_title_hl },
		{ "  " },
		{ msg, nottify_message_hl },
	}
end

local function open_float()
	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * (M.opts.width or 0.6))
	local height = math.floor(vim.o.lines * (M.opts.height or 0.5))
	local row = math.floor((vim.o.lines - height) / 2 - 1)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = M.opts.border or "rounded",
		width = width,
		height = height,
		row = row,
		col = col,
		noautocmd = true,
	})

	return buf, win
end

function M.build_lines(item)
	local title_chunks = fmt_item(item)
	title_chunks[#title_chunks] = nil -- remove message part
	title_chunks[#title_chunks] = nil -- remove trailing space

	local title, spans = "", {}
	local col = 0
	for _, chunk in ipairs(title_chunks) do
		local text = chunk[1] or ""
		local hl = chunk[2]
		local len = string.len(text)
		if hl ~= nil then
			spans[#spans + 1] = { hl = hl, from = col, to = col + len }
		end
		col = col + len
		title = title .. text
	end

	local src = (item and item.raw and item.raw.message) or {}
	local lines = { title }
	for i = 1, #src do
		lines[#lines + 1] = tostring(src[i])
	end
	local level = (item and (item.level or (item.raw and item.raw.level)) or "INFO"):upper()
	return spans, lines, level
end

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

function M.set_notification_window(buf, win, item)
	local spans, lines, level = M.build_lines(item)

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = false

	M.apply_window_opts(win, level)

	local ns = vim.api.nvim_create_namespace("snacks_notify_title_hl")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, s in ipairs(spans) do
		vim.hl.range(buf, ns, s.hl, { 0, s.from }, { 0, s.to }, { inclusive = false })
	end
end

function M.preview_notify(ctx)
	local ok, err = pcall(function()
		M.set_notification_window(ctx.buf, ctx.win, ctx.item)
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
			local buf, win = open_float()
			M.set_notification_window(buf, win, item)
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
