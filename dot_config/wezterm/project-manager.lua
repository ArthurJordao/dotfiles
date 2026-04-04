local wezterm = require("wezterm")
local mux = wezterm.mux
local act = wezterm.action

local M = {}

-- Project layouts are read from .wezterm.json files in each project directory
-- No centralized configuration needed

-- Helper function to calculate pane split direction and size
function M.calculate_pane_split(layout, pane_index, total_panes)
	if layout == "tiled" then
		-- Tiled layout: limit to 4 panes maximum to avoid sizing issues
		if total_panes > 4 then
			wezterm.log_warn(
				"Tiled layout limited to 4 panes, you have " .. total_panes .. ". Consider using multiple tabs."
			)
			total_panes = 4
		end

		-- Create a 2x2 grid for tiled layout
		if pane_index == 2 then
			-- Split right to create 2 columns
			return "Right", 0.5
		elseif pane_index == 3 then
			-- Split the left pane down to create top-left and bottom-left
			return "Bottom", 0.5
		elseif pane_index == 4 then
			-- Split the right pane down to create top-right and bottom-right
			return "Bottom", 0.5
		end
	elseif layout == "main-horizontal" then
		-- Horizontal splits (all panes stacked vertically)
		local remaining_panes = total_panes - pane_index + 1
		local size = math.max(0.15, 1.0 / remaining_panes) -- Minimum 15% size
		return "Bottom", size
	else
		-- Default: main-vertical (all panes side by side)
		local remaining_panes = total_panes - pane_index + 1
		local size = math.max(0.15, 1.0 / remaining_panes) -- Minimum 15% size
		return "Right", size
	end
end

-- Default template (equivalent to your tmuxinator/project.yml)
M.default_layout = {
	windows = {
		{
			name = "editor",
			command = "nvim .",
		},
		{
			name = "server",
			layout = "main-vertical",
			panes = {
				{ command = "" },
				{ command = "" },
			},
		},
	},
}

-- Function to read project JSON configuration
function M.read_project_config(project_path)
	local config_file = project_path .. "/.wezterm.json"
	local file = io.open(config_file, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()

	-- Simple JSON parsing (you can use a more robust library)
	local success, config = pcall(function()
		return wezterm.json_parse(content)
	end)

	if success then
		return config
	else
		wezterm.log_error("Failed to parse project config: " .. config_file)
		return nil
	end
end

-- Function to create workspace based on layout
function M.setup_project_workspace(project_name, project_path)
	local layout = M.read_project_config(project_path) or M.default_layout

	-- Use project name as workspace if not specified
	local workspace = layout.workspace or project_name
	local root = layout.root and layout.root:gsub("~", os.getenv("HOME")) or project_path

	-- Create first window
	local first_tab, first_pane, first_window = mux.spawn_window({
		workspace = workspace,
		cwd = root,
	})

	-- Setup first window
	local first_window_config = layout.windows[1]
	if first_window_config then
		-- Set tab title
		if first_window_config.name then
			first_tab:set_title(first_window_config.name)
		end

		-- Execute initial command if specified
		if first_window_config.command then
			if first_window_config.send_keys then
				first_pane:send_text(first_window_config.command)
			else
				first_pane:send_text(first_window_config.command .. "\n")
			end
		end

		-- The first window (editor) should NOT have panes normally
		-- If it does, handle it anyway
		if first_window_config.panes then
			wezterm.log_info(
				"Creating panes for first window ("
					.. (first_window_config.name or "unnamed")
					.. "): "
					.. #first_window_config.panes
					.. " panes"
			)

			-- Calculate dynamic size and direction based on layout
			local total_panes = #first_window_config.panes
			local panes = { first_pane } -- Track all panes

			for j, pane_config in ipairs(first_window_config.panes) do
				if j == 1 then
					-- First pane already exists, just execute command
					if pane_config.command and pane_config.command ~= "" then
						if pane_config.send_keys then
							panes[1]:send_text(pane_config.command)
						else
							panes[1]:send_text(pane_config.command .. "\n")
						end
					end
				else
					-- Create new panes with dynamic sizing and layout
					local direction, size = M.calculate_pane_split(first_window_config.layout, j, total_panes)

					-- Choose which pane to split from for tiled layout
					local split_from_pane = panes[1] -- Default to first pane
					if first_window_config.layout == "tiled" then
						if j == 2 then
							split_from_pane = panes[1] -- Split from pane 1 to create pane 2
						elseif j == 3 then
							split_from_pane = panes[1] -- Split from pane 1 to create pane 3
						elseif j == 4 then
							split_from_pane = panes[2] -- Split from pane 2 to create pane 4
						end
					end

					wezterm.log_info("Creating pane " .. j .. " with direction: " .. direction .. " and size: " .. size)
					local new_pane = split_from_pane:split({
						direction = direction,
						size = size,
						cwd = root,
					})

					if pane_config.command and pane_config.command ~= "" then
						if pane_config.send_keys then
							new_pane:send_text(pane_config.command)
						else
							new_pane:send_text(pane_config.command .. "\n")
						end
					end

					-- Track the new pane
					table.insert(panes, new_pane)
				end
			end
		end
	end

	-- Create additional tabs
	wezterm.log_info("Creating " .. (#layout.windows - 1) .. " additional tabs")
	for i = 2, #layout.windows do
		local window_config = layout.windows[i]

		wezterm.log_info("Creating tab " .. i .. " (" .. (window_config.name or "unnamed") .. ")")
		local tab, pane, window = first_window:spawn_tab({
			cwd = root,
		})

		-- Set tab title
		if window_config.name then
			tab:set_title(window_config.name)
		end

		-- Execute initial command if specified
		if window_config.command then
			if window_config.send_keys then
				pane:send_text(window_config.command)
			else
				pane:send_text(window_config.command .. "\n")
			end
		end

		-- Create additional panes if specified
		if window_config.panes then
			wezterm.log_info(
				"Tab "
					.. i
					.. " ("
					.. (window_config.name or "unnamed")
					.. ") has "
					.. #window_config.panes
					.. " panes defined"
			)

			-- Calculate dynamic size and direction based on layout
			local total_panes = #window_config.panes
			local panes = { pane } -- Track all panes

			for j, pane_config in ipairs(window_config.panes) do
				wezterm.log_info("Processing pane " .. j .. " of " .. #window_config.panes)
				if j == 1 then
					-- First pane already exists, just execute command
					wezterm.log_info("First pane, executing command: '" .. (pane_config.command or "empty") .. "'")
					if pane_config.command and pane_config.command ~= "" then
						if pane_config.send_keys then
							panes[1]:send_text(pane_config.command)
						else
							panes[1]:send_text(pane_config.command .. "\n")
						end
					end
				else
					-- Create new panes with dynamic sizing and layout
					local direction, size = M.calculate_pane_split(window_config.layout, j, total_panes)

					-- Choose which pane to split from for tiled layout
					local split_from_pane = panes[1] -- Default to first pane
					if window_config.layout == "tiled" then
						if j == 2 then
							split_from_pane = panes[1] -- Split from pane 1 to create pane 2
						elseif j == 3 then
							split_from_pane = panes[1] -- Split from pane 1 to create pane 3
						elseif j == 4 then
							split_from_pane = panes[2] -- Split from pane 2 to create pane 4
						end
					end

					wezterm.log_info(
						"Creating pane "
							.. j
							.. " in tab "
							.. i
							.. " with direction: "
							.. direction
							.. " and size: "
							.. size
					)
					local new_pane = split_from_pane:split({
						direction = direction,
						size = size,
						cwd = root,
					})

					if pane_config.command and pane_config.command ~= "" then
						if pane_config.send_keys then
							new_pane:send_text(pane_config.command)
						else
							new_pane:send_text(pane_config.command .. "\n")
						end
					end

					-- Track the new pane
					table.insert(panes, new_pane)
				end
			end
		else
			wezterm.log_info("Tab " .. i .. " (" .. (window_config.name or "unnamed") .. ") has no panes defined")
		end
	end

	-- Focus on created workspace
	mux.set_active_workspace(workspace)

	-- Return workspace name for confirmation
	return workspace
end

-- Function to list projects (equivalent to tmux-sessionizer's find)
function M.get_projects()
	local projects = {}
	local search_paths = {
		os.getenv("HOME") .. "/dev/noredink",
		os.getenv("HOME") .. "/dev/personal",
	}

	for _, search_path in ipairs(search_paths) do
		local handle = io.popen("find " .. search_path .. " -mindepth 1 -maxdepth 1 -type d 2>/dev/null")
		if handle then
			for line in handle:lines() do
				local project_name = line:match("([^/]+)$")
				if project_name then
					table.insert(projects, {
						name = project_name,
						path = line,
					})
				end
			end
			handle:close()
		end
	end

	return projects
end

-- Action for workspace switcher (equivalent to tmux-sessionizer)
function M.workspace_switcher()
	return wezterm.action_callback(function(window, pane)
		local projects = M.get_projects()
		local choices = {}

		if #projects == 0 then
			wezterm.log_error("No projects found in search paths")
			return
		end

		for _, project in ipairs(projects) do
			table.insert(choices, {
				id = project.path,
				label = project.name,
			})
		end

		window:perform_action(
			act.InputSelector({
				action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
					if not id and not label then
						return
					end

					local project_name = label
					local project_path = id

					-- Check if workspace already exists
					local workspaces = mux.get_workspace_names()
					for _, ws in ipairs(workspaces) do
						if ws == project_name then
							mux.set_active_workspace(project_name)
							return
						end
					end

					-- Create new workspace
					wezterm.log_info("Creating workspace: " .. project_name .. " at " .. project_path)
					M.setup_project_workspace(project_name, project_path)
				end),
				title = "Select Project",
				choices = choices,
				fuzzy = true,
				description = "Select a project to open (tmux-sessionizer style)",
			}),
			pane
		)
	end)
end

return M
