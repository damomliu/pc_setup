local markdown_path = ya.sync(function()
	local tab = cx.active
	local file = tab.current.hovered
	for _, selected in pairs(tab.selected) do
		file = selected
		break
	end
	if not file or file.cha.is_dir then return end

	local extension = (file.url.ext or ""):lower()
	if extension == "md" or extension == "markdown" then
		return tostring(file.url.path)
	end
end)

local function entry()
	local path = markdown_path()
	if not path then
		return ya.notify { title = "Glow", content = "Select a Markdown file (.md or .markdown)", timeout = 3, level = "warn" }
	end

	local command = Command("glow")
	-- Match the Glow openers in yazi.toml.
	if ya.target_family() == "windows" then
		local program_files = os.getenv("ProgramFiles") or os.getenv("ProgramW6432")
		if not program_files then
			return ya.notify { title = "Glow", content = "Cannot locate Git for Windows: ProgramFiles is unset", timeout = 5, level = "error" }
		end
		program_files = program_files:gsub("\\", "/")
		command:env("PAGER", "'" .. program_files .. "/Git/usr/bin/less.exe' -R"):arg("--pager")
	else
		command:arg("--tui")
	end
	command:arg({ "--", path }):stdin(Command.INHERIT):stdout(Command.INHERIT):stderr(Command.INHERIT)

	local permit = ui.hide()
	local status, err = command:status()
	permit:drop()
	if not status or not status.success then
		local message = status and ("Glow exited with code " .. tostring(status.code)) or tostring(err)
		ya.notify { title = "Glow", content = message, timeout = 5, level = "error" }
	end
end

return { entry = entry }
