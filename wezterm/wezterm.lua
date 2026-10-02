local wezterm = require 'wezterm'
local act = wezterm.action
local mux = wezterm.mux

local config = wezterm.config_builder()

-- Shell 與啟動選單。
config.default_prog = { 'C:\\Program Files\\PowerShell\\7\\pwsh.exe', '-NoLogo' }
local ubuntu_wsl = { 'wsl.exe', '--distribution', 'Ubuntu-24.04', '--cd', '~' }
config.launch_menu = {
  {
    label = 'PowerShell 7',
    args = { 'C:\\Program Files\\PowerShell\\7\\pwsh.exe', '-NoLogo' },
  },
  {
    label = 'Ubuntu 24.04',
    args = ubuntu_wsl,
  },
  {
    label = 'Git Bash',
    args = { 'C:\\Program Files\\Git\\bin\\bash.exe', '-l', '-i' },
  },
  {
    label = 'Command Prompt',
    args = { 'cmd.exe' },
  },
  {
    label = 'SSH: nb',
    args = { 'ssh.exe', 'nb' },
  },
}

-- 外觀。
config.color_scheme = 'Catppuccin Mocha'
config.font = wezterm.font 'Sarasa Term TC Nerd Font'
config.font_size = 11
config.default_cursor_style = 'SteadyBar'
config.window_background_opacity = 1
config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'
config.inactive_pane_hsb = {
  saturation = 0.5,
  brightness = 0.4,
}
config.window_padding = {
  left = 4,
  right = 4,
  top = 4,
  bottom = 4,
}

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 32

-- 終端行為。
config.scrollback_lines = 10000
config.use_ime = true
config.audible_bell = 'SystemBeep'
config.window_close_confirmation = 'AlwaysPrompt'

-- Ctrl+B 作為 WezTerm prefix。
local PREFIX_TIMEOUT_MS = 2000
config.leader = {
  key = 'b',
  mods = 'CTRL',
  timeout_milliseconds = PREFIX_TIMEOUT_MS,
}

-- 啟動時最大化 GUI 視窗。
wezterm.on('gui-startup', function(cmd)
  local _, _, window = mux.spawn_window(cmd or {})
  window:gui_window():maximize()
end)

-- Prefix 啟動時才顯示狀態。
wezterm.on('update-right-status', function(window)
  if window:leader_is_active() then
    window:set_right_status ' LEADER '
  else
    window:set_right_status ''
  end
end)

local function basename(path)
  return path:gsub('(.*[/\\])', '')
end

local claude_name_cache = {}

local function decode_json(text)
  if wezterm.serde and wezterm.serde.json_decode then
    local ok, data = pcall(wezterm.serde.json_decode, text)
    if ok and type(data) == 'table' then
      return data
    end
  end

  return {
    name = text:match('"name"%s*:%s*"([^"]*)"'),
  }
end

local function read_claude_session(pid)
  if not pid then
    return
  end

  pid = tostring(math.floor(pid))
  local paths = {
    wezterm.home_dir .. '/.claude/sessions/' .. pid .. '.json',
    wezterm.home_dir .. '\\.claude\\sessions\\' .. pid .. '.json',
  }

  for _, path in ipairs(paths) do
    local file = io.open(path, 'r')
    if file then
      local data = decode_json(file:read('*a') or '')
      file:close()
      if data and data.name and data.name ~= '' then
        return data
      end
    end
  end
end

-- Claude 把狀態符號 + 名稱寫進 pane OSC：✳ 忙碌、◐/○/● 閒置或切回主 agent。
local function claude_name_from_pane_title(title)
  if not title or title == '' then
    return
  end

  -- 一個 ASCII 或 UTF-8 符號，後面空白再接名稱。
  local rest = title:match('^[\1-\127]%s+(.+)$')
    or title:match('^[\194-\244][\128-\191]+%s+(.+)$')
  if not rest then
    return
  end

  rest = rest:match('^%s*(.-)%s*$') or ''
  if rest ~= '' then
    return rest
  end
end

local function active_mux_pane(tab, mux_tab)
  if mux_tab then
    local ok, panes = pcall(function()
      return mux_tab:panes_with_info()
    end)
    if ok then
      for _, info in ipairs(panes) do
        if info.is_active and info.pane then
          return info.pane
        end
      end
    end
  end
  if mux.get_pane then
    local ok, pane = pcall(mux.get_pane, tab.active_pane.pane_id)
    if ok then
      return pane
    end
  end
end

-- 停在 sub-agent 時 OSC 仍是主場名稱；名稱在畫面底的 ─── 標題列。
local claude_view_cache = {}

local function claude_focused_subagent(pane)
  if not pane then
    return
  end

  local pane_id = pane:pane_id()
  local now = os.time()
  local ok, text = pcall(function()
    return pane:get_lines_as_text(16)
  end)
  if not ok or not text or text == '' then
    return
  end

  local cached = claude_view_cache[pane_id]
  if cached and now - cached.at < 1 and cached.text == text then
    return cached.name
  end

  local name
  if text:find('Message @', 1, true) or text:find('Enter to view', 1, true) then
    local bar = '\226\148\128'
    for line in text:gmatch('[^\r\n]+') do
      if line:sub(1, #bar) == bar then
        local trimmed = line
        while trimmed:sub(1, #bar) == bar do
          trimmed = trimmed:sub(#bar + 1)
        end
        trimmed = trimmed:match('^%s*(.-)%s*$') or ''
        while #trimmed >= #bar and trimmed:sub(-#bar) == bar do
          trimmed = trimmed:sub(1, -(#bar + 1))
        end
        trimmed = trimmed:match('^%s*(.-)%s*$') or ''
        if trimmed ~= '' then
          name = trimmed
        end
      end
    end
  end

  claude_view_cache[pane_id] = { at = now, text = text, name = name }
  return name
end

-- /rename 後舊的 interactive session 檔可能仍叫 archi，bg job 才是新名。
local function pick_claude_session_name(pids, pane_title)
  local from_pane = claude_name_from_pane_title(pane_title)
  if from_pane then
    return from_pane
  end

  local best
  local best_score = -1
  local best_since = -1
  for pid in pairs(pids) do
    local data = read_claude_session(pid)
    if data then
      local score = 0
      if data.nameSource == 'user' then
        score = score + 10
      end
      if data.kind == 'bg' then
        score = score + 5
      end
      if data.parkedJobId then
        score = score - 50
      end
      local since = tonumber(data.nameSince) or 0
      if score > best_score or (score == best_score and since > best_since) then
        best = data.name
        best_score = score
        best_since = since
      end
    end
  end
  return best
end

local function collect_child_pids(info, pids)
  if not info or not info.pid or pids[info.pid] then
    return
  end

  pids[info.pid] = true
  if type(info.children) == 'table' then
    for _, child in pairs(info.children) do
      collect_child_pids(child, pids)
    end
  end
end

local function process_info_from_tab(tab, mux_tab)
  if mux_tab then
    local panes_ok, panes = pcall(function()
      return mux_tab:panes_with_info()
    end)
    if panes_ok then
      for _, info in ipairs(panes) do
        if info.is_active and info.pane then
          local proc_ok, proc = pcall(function()
            return info.pane:get_foreground_process_info()
          end)
          if proc_ok and proc then
            return proc
          end
        end
      end
    end
  end

  if mux.get_pane then
    local pane_ok, pane = pcall(mux.get_pane, tab.active_pane.pane_id)
    if pane_ok and pane then
      local proc_ok, proc = pcall(function()
        return pane:get_foreground_process_info()
      end)
      if proc_ok then
        return proc
      end
    end
  end
end

local function claude_session_name(tab, mux_tab)
  local pane_id = tab.active_pane.pane_id
  local pane_title = tab.active_pane.title or ''
  local now = os.time()
  local cached = claude_name_cache[pane_id]
  if cached and now - cached.at < 2 and cached.pane_title == pane_title then
    return cached.name
  end

  local pids = {}
  local info = process_info_from_tab(tab, mux_tab)
  if info then
    collect_child_pids(info, pids)

    local pid = info.pid
    local ppid = info.ppid
    for _ = 1, 8 do
      if not pid then
        break
      end
      pids[pid] = true
      if not ppid or ppid == 0 or pids[ppid] then
        break
      end
      pid = ppid
      local parent = wezterm.procinfo.get_info_for_pid(ppid)
      ppid = parent and parent.ppid or nil
    end
  end

  local name = pick_claude_session_name(pids, pane_title)
  claude_name_cache[pane_id] = { at = now, name = name, pane_title = pane_title }
  return name
end

local function auto_tab_title(tab, mux_tab)
  local title = tab.tab_title
  if title and title ~= '' then
    return title
  end

  local pane = active_mux_pane(tab, mux_tab)
  local sub = claude_focused_subagent(pane)
  if sub then
    return sub
  end

  title = claude_session_name(tab, mux_tab)
  if title then
    return title
  end

  local process = basename(tab.active_pane.foreground_process_name or 'shell')
  local cwd = tab.active_pane.current_working_dir
  local directory = ''
  if cwd then
    directory = basename(cwd.file_path or tostring(cwd))
  end

  title = process
  if directory ~= '' then
    title = title .. ' · ' .. directory
  end
  return title
end

-- 手動 tab 名稱優先，否則顯示 Claude session、程序與工作目錄。
wezterm.on('format-tab-title', function(tab, _, _, _, _, max_width)
  local number = tostring(tab.tab_index + 1)
  local mux_tab = mux.get_tab(tab.tab_id)
  local title = auto_tab_title(tab, mux_tab)

  local all_panes = mux_tab and mux_tab:panes_with_info() or tab.panes
  local current = 1

  for index, info in ipairs(all_panes) do
    local pane_id = info.pane and info.pane:pane_id() or info.pane_id
    if info.is_active or pane_id == tab.active_pane.pane_id then
      current = index
      break
    end
  end

  local pane_status = string.format(
    ' (%d/%d%s)',
    current,
    #all_panes,
    tab.active_pane.is_zoomed and 'Z' or ''
  )
  local prefix = ' ' .. number .. ': '
  local suffix = pane_status .. ' '
  local title_width = math.max(1, max_width - #prefix - #suffix)

  return prefix .. wezterm.truncate_right(title, title_width) .. suffix
end)

wezterm.on('format-window-title', function(tab, _, tabs)
  local mux_tab = mux.get_tab(tab.tab_id)
  local title = auto_tab_title(tab, mux_tab)
  local zoomed = tab.active_pane.is_zoomed and '[Z] ' or ''
  local index = ''
  if #tabs > 1 then
    index = string.format('[%d/%d] ', tab.tab_index + 1, #tabs)
  end
  return zoomed .. index .. title
end)

local function pane_state(pane)
  local tab = pane:tab()
  if not tab then
    return
  end
  local panes = tab:panes_with_info()
  local current = 1
  local was_zoomed = false

  for index, info in ipairs(panes) do
    if info.pane:pane_id() == pane:pane_id() then
      current = index
      was_zoomed = info.is_zoomed
      break
    end
  end

  return tab, panes, current, was_zoomed
end

-- 切換 pane 後維持原本的 zoom 狀態。
local function activate_pane(target_number)
  return wezterm.action_callback(function(_, pane)
    local tab, panes, current, was_zoomed = pane_state(pane)
    if not tab then
      return
    end
    local count = #panes

    if count < 2 then
      return
    end

    local target
    if target_number == 'next' then
      target = current % count + 1
    elseif target_number == 'previous' then
      target = (current - 2) % count + 1
    else
      target = target_number
    end

    if target < 1 or target > count or target == current then
      return
    end

    tab:set_zoomed(false)
    panes[target].pane:activate()
    tab:set_zoomed(was_zoomed)
  end)
end

local function ranges_overlap(start_a, size_a, start_b, size_b)
  return math.min(start_a + size_a, start_b + size_b) - math.max(start_a, start_b)
end

-- 含「移 tab 後 mux 未縮、pane 互相重疊」：只要起點更左／更右就算該方向。
local function pane_in_direction(direction, current, candidate)
  local slack = 1
  if direction == 'Left' then
    if candidate.left >= current.left - slack then
      return
    end
    local gap = current.left - candidate.left - candidate.width
    local distance = gap >= 0 and gap or (current.left - candidate.left)
    return distance, ranges_overlap(candidate.top, candidate.height, current.top, current.height)
  end
  if direction == 'Right' then
    if candidate.left <= current.left + slack then
      return
    end
    local gap = candidate.left - current.left - current.width
    local distance = gap >= 0 and gap or (candidate.left - current.left)
    return distance, ranges_overlap(candidate.top, candidate.height, current.top, current.height)
  end
  if direction == 'Up' then
    if candidate.top >= current.top - slack then
      return
    end
    local gap = current.top - candidate.top - candidate.height
    local distance = gap >= 0 and gap or (current.top - candidate.top)
    return distance, ranges_overlap(candidate.left, candidate.width, current.left, current.width)
  end
  if direction == 'Down' then
    if candidate.top <= current.top + slack then
      return
    end
    local gap = candidate.top - current.top - current.height
    local distance = gap >= 0 and gap or (candidate.top - current.top)
    return distance, ranges_overlap(candidate.left, candidate.width, current.left, current.width)
  end
end

-- 依 pane 的實際位置尋找指定方向，並在切換後恢復 zoom。
local function activate_pane_direction(direction)
  return wezterm.action_callback(function(_, pane)
    local tab, _, _, was_zoomed = pane_state(pane)
    if not tab then
      return
    end
    tab:set_zoomed(false)

    local panes = tab:panes_with_info()
    local current

    for _, info in ipairs(panes) do
      if info.pane:pane_id() == pane:pane_id() then
        current = info
        break
      end
    end

    if not current then
      tab:set_zoomed(was_zoomed)
      return
    end

    local best
    local best_distance
    local best_overlap

    for _, candidate in ipairs(panes) do
      if candidate.pane:pane_id() ~= current.pane:pane_id() then
        local distance, overlap = pane_in_direction(direction, current, candidate)
        if distance and overlap > 0 then
          if not best or distance < best_distance or
              (distance == best_distance and overlap > best_overlap) then
            best = candidate
            best_distance = distance
            best_overlap = overlap
          end
        end
      end
    end

    if best then
      best.pane:activate()
    end
    tab:set_zoomed(was_zoomed)
  end)
end

local rename_tab = act.PromptInputLine {
  description = '輸入 tab 名稱；留空可恢復自動標題',
  action = wezterm.action_callback(function(window, _, line)
    if line then
      window:active_tab():set_title(line)
    end
  end),
}

local function strip_prompt(text)
  text = (text or ''):gsub('\r', ''):gsub('\n', ' ')
  text = text:match('^%s*(.-)%s*$') or ''
  if text == '' then
    return ''
  end

  local cmd = text:match('^PS .-%>%s*(.*)$')
    or text:match('^[❯➜]%s*(.*)$')
    or text:match('^[^%s]+@[^%s]+:.-[$#]%s+(.*)$')
    or text:match('^[$#>]%s+(.*)$')
  if cmd then
    return cmd:match('^%s*(.-)%s*$') or ''
  end
  return text
end

local function current_command_line(pane)
  local cursor = pane:get_cursor_position()
  if cursor and cursor.x and cursor.x > 0 then
    local ok, text = pcall(
      pane.get_text_from_region,
      pane,
      0,
      cursor.y,
      cursor.x,
      cursor.y
    )
    if ok then
      local cmd = strip_prompt(text)
      if cmd ~= '' then
        return cmd, 'pending'
      end
    end
  end

  local ok_zones, zones = pcall(pane.get_semantic_zones, pane, 'Input')
  if ok_zones and type(zones) == 'table' and #zones > 0 then
    local ok_text, text = pcall(
      pane.get_text_from_semantic_zone,
      pane,
      zones[#zones]
    )
    if ok_text then
      local cmd = strip_prompt(text)
      if cmd ~= '' then
        return cmd, 'done'
      end
    end
  end
end

local function sync_current_command_to_other_panes(window, pane)
  local tab = pane:tab()
  if not tab then
    return
  end

  local cmd, state = current_command_line(pane)
  if not cmd then
    window:toast_notification(
      'WezTerm',
      '請先在目前 pane 輸入指令，再執行 Sync',
      nil,
      3000
    )
    return
  end

  local current_id = pane:pane_id()
  local text = cmd .. '\r'
  for _, info in ipairs(tab:panes_with_info()) do
    if info.pane:pane_id() ~= current_id then
      info.pane:send_text(text)
    end
  end

  if state == 'pending' then
    pane:send_text '\r'
  end
end

local function pane_info_by_id(tab)
  local by_id = {}
  for _, info in ipairs(tab:panes_with_info()) do
    by_id[info.pane:pane_id()] = info
  end
  return by_id
end

local function refresh_infos(tab, infos)
  local by_id = pane_info_by_id(tab)
  local next_infos = {}
  for _, info in ipairs(infos) do
    local fresh = by_id[info.pane:pane_id()]
    if fresh then
      next_infos[#next_infos + 1] = fresh
    end
  end
  return next_infos
end

local CELL_SLACK = 1

local function ranges_overlap_exclusive(start_a, size_a, start_b, size_b)
  return math.min(start_a + size_a, start_b + size_b) - math.max(start_a, start_b) > 0
end

-- 寬或高被擠成 0 的 pane 仍在 tab 裡，只是沒被畫出來（Prefix+Q 會只看到 1）。
local function revive_collapsed_panes(window, tab)
  for _, info in ipairs(tab:panes_with_info()) do
    if info.width == 0 then
      info.pane:activate()
      window:perform_action(act.AdjustPaneSize { 'Left', 8 }, info.pane)
    end
    if info.height == 0 then
      info.pane:activate()
      window:perform_action(act.AdjustPaneSize { 'Up', 4 }, info.pane)
    end
  end
end

local function unique_positions(infos, key)
  local seen = {}
  local values = {}
  for _, info in ipairs(infos) do
    local value = info[key]
    if not seen[value] then
      seen[value] = true
      values[#values + 1] = value
    end
  end
  table.sort(values)
  return values
end

local function partition_infos(infos, cut, pos_key, size_key)
  local before = {}
  local after = {}
  for _, info in ipairs(infos) do
    local pos = info[pos_key]
    local finish = pos + info[size_key]
    local is_before = finish <= cut + CELL_SLACK
    local is_after = pos >= cut - CELL_SLACK
    if is_before and is_after then
      if pos >= cut then
        after[#after + 1] = info
      else
        before[#before + 1] = info
      end
    elseif is_before then
      before[#before + 1] = info
    elseif is_after then
      after[#after + 1] = info
    else
      return
    end
  end
  if #before > 0 and #after > 0 then
    return before, after
  end
end

local function fanout_leaves(infos, kind)
  local children = {}
  for _, info in ipairs(infos) do
    children[#children + 1] = { kind = 'leaf', info = info }
  end
  return { kind = kind, children = children }
end

local function build_split_tree(infos)
  if #infos == 0 then
    return { kind = 'leaf' }
  end
  if #infos == 1 then
    return { kind = 'leaf', info = infos[1] }
  end

  local lefts = unique_positions(infos, 'left')
  for index = 2, #lefts do
    local before, after = partition_infos(infos, lefts[index], 'left', 'width')
    if before then
      return {
        kind = 'vsplit',
        children = { build_split_tree(before), build_split_tree(after) },
      }
    end
  end

  local tops = unique_positions(infos, 'top')
  for index = 2, #tops do
    local before, after = partition_infos(infos, tops[index], 'top', 'height')
    if before then
      return {
        kind = 'hsplit',
        children = { build_split_tree(before), build_split_tree(after) },
      }
    end
  end

  local first = infos[1]
  local same_row = true
  local same_col = true
  for _, info in ipairs(infos) do
    if math.abs(info.top - first.top) > CELL_SLACK then
      same_row = false
    end
    if math.abs(info.left - first.left) > CELL_SLACK then
      same_col = false
    end
  end

  table.sort(infos, function(a, b)
    if a.left == b.left then
      return a.top < b.top
    end
    return a.left < b.left
  end)

  if same_row then
    return fanout_leaves(infos, 'vsplit')
  end
  if same_col then
    return fanout_leaves(infos, 'hsplit')
  end
  return fanout_leaves(infos, 'vsplit')
end

local function tree_leaves(node)
  if node.kind == 'leaf' then
    if not node.info then
      return {}
    end
    return { node.info }
  end
  local leaves = {}
  for _, child in ipairs(node.children or {}) do
    for _, leaf in ipairs(tree_leaves(child)) do
      leaves[#leaves + 1] = leaf
    end
  end
  return leaves
end

local function tree_span(node, pos_key, size_key)
  local min_pos
  local max_end
  for _, info in ipairs(tree_leaves(node)) do
    local pos = info[pos_key]
    local finish = pos + info[size_key]
    min_pos = min_pos and math.min(min_pos, pos) or pos
    max_end = max_end and math.max(max_end, finish) or finish
  end
  if not min_pos then
    return 0
  end
  return max_end - min_pos
end

local function touching_pairs(left_node, right_node, axis)
  local pos_key = axis == 'width' and 'left' or 'top'
  local size_key = axis
  local cross_pos = axis == 'width' and 'top' or 'left'
  local cross_size = axis == 'width' and 'height' or 'width'
  local pairs = {}

  for _, left in ipairs(tree_leaves(left_node)) do
    local edge = left[pos_key] + left[size_key]
    for _, right in ipairs(tree_leaves(right_node)) do
      if math.abs(right[pos_key] - edge) <= CELL_SLACK and
          ranges_overlap_exclusive(
            left[cross_pos],
            left[cross_size],
            right[cross_pos],
            right[cross_size]
          ) then
        pairs[#pairs + 1] = { left = left, right = right }
      end
    end
  end

  if #pairs == 0 then
    local lefts = tree_leaves(left_node)
    local rights = tree_leaves(right_node)
    if #lefts > 0 and #rights > 0 then
      pairs[1] = { left = lefts[1], right = rights[1] }
    end
  end

  return pairs
end

-- 移動 left 與 right 相接的那條邊。delta > 0 代表 left 變寬／變高。
-- 右深的分割樹裡，這條邊屬於 left；左深時才屬於 right。
-- 先試 1 格，確認這兩個 pane 的交界真的動了，再補上剩下的距離。
local function adjust_pair(window, tab, pair, axis, delta)
  if not pair or delta == 0 then
    return
  end

  local size_key = axis
  local pos_key = axis == 'width' and 'left' or 'top'
  local grow_dir = axis == 'width' and 'Right' or 'Down'
  local shrink_dir = axis == 'width' and 'Left' or 'Up'
  local direction = delta > 0 and grow_dir or shrink_dir
  local undo_dir = delta > 0 and shrink_dir or grow_dir
  local id_l = pair.left.pane:pane_id()
  local id_r = pair.right.pane:pane_id()

  local function edge()
    local by_id = pane_info_by_id(tab)
    local left = by_id[id_l]
    local right = by_id[id_r]
    if not left or not right then
      return
    end
    return left[size_key], right[pos_key]
  end

  local function layout_signature()
    local parts = {}
    for _, info in ipairs(tab:panes_with_info()) do
      parts[#parts + 1] = table.concat({
        info.pane:pane_id(),
        info.left,
        info.top,
        info.width,
        info.height,
      }, ':')
    end
    return table.concat(parts, '|')
  end

  local function nudge(info, dir, amount)
    info.pane:activate()
    window:perform_action(act.AdjustPaneSize { dir, amount }, info.pane)
  end

  local function try_pane(info)
    local before_size, before_pos = edge()
    local before_layout = layout_signature()
    if not before_size then
      return false
    end

    nudge(info, direction, 1)
    local after_size, after_pos = edge()
    local moved = after_size and after_pos and (after_size ~= before_size) and (after_pos ~= before_pos)
    if not moved then
      if layout_signature() ~= before_layout then
        nudge(info, undo_dir, 1)
      end
      return false
    end

    local rest = math.abs(delta) - 1
    if rest > 0 then
      nudge(info, direction, rest)
    end
    return true
  end

  if try_pane(pair.left) then
    return
  end
  try_pane(pair.right)
end

local function axis_extent(infos, pos_key, size_key)
  local max_end = 0
  for _, info in ipairs(infos) do
    max_end = math.max(max_end, info[pos_key] + info[size_key])
  end
  return max_end
end

-- tab:get_size() 跟視窗一致。其他 tab 的 pane 可能還停在縮放前的寬度，不能拿來當目標。
local function usable_axis_extent(tab, axis, mux_total)
  local ok, size = pcall(function()
    return tab:get_size()
  end)
  if ok and size then
    local extent = axis == 'width' and size.cols or size.rows
    if extent and extent > 0 then
      return extent
    end
  end
  return mux_total
end

local function equalize_nodes(window, tab, nodes, axis, usable, split_guard)
  if #nodes < 2 then
    return
  end

  local pos_key = axis == 'width' and 'left' or 'top'
  local size_key = axis
  local ids = {}
  for index, node in ipairs(nodes) do
    ids[index] = {}
    for _, info in ipairs(tree_leaves(node)) do
      ids[index][#ids[index] + 1] = info.pane:pane_id()
    end
  end

  local function current_nodes()
    local by_id = pane_info_by_id(tab)
    local fresh = {}
    for index, pane_ids in ipairs(ids) do
      local infos = {}
      for _, pane_id in ipairs(pane_ids) do
        if by_id[pane_id] then
          infos[#infos + 1] = by_id[pane_id]
        end
      end
      fresh[index] = build_split_tree(infos)
    end
    return fresh
  end

  local function spans_beyond_band(info)
    if not split_guard then
      return false
    end
    local pos = info[split_guard.cross_pos]
    local size = info[split_guard.cross_size]
    return pos < split_guard.band_pos - CELL_SLACK
      or pos + size > split_guard.band_pos + split_guard.band_span + CELL_SLACK
  end

  nodes = current_nodes()
  local mux_total = 0
  for _, node in ipairs(nodes) do
    mux_total = mux_total + tree_span(node, pos_key, size_key)
  end
  if mux_total <= 0 then
    return
  end

  -- 這一帶的 mux 總長和 tab 實際欄列對不上時，改依 tab 尺寸均分。
  local total = mux_total
  if usable and usable > 0 then
    local mux_extent = mux_total + (#nodes - 1)
    if math.abs(mux_extent - usable) > CELL_SLACK then
      total = math.max(1, usable - (#nodes - 1))
    end
  end

  local base = math.floor(total / #nodes)
  local extra = total % #nodes

  for index = 1, #nodes - 1 do
    local fresh = current_nodes()
    local desired = base + (index <= extra and 1 or 0)
    local by_id = pane_info_by_id(tab)
    -- 同一條分割線只調一次，避免田字共用邊被左右／上下各砍一刀。
    for _, pair in ipairs(touching_pairs(fresh[index], fresh[index + 1], axis)) do
      local left = by_id[pair.left.pane:pane_id()]
      local right = by_id[pair.right.pane:pane_id()]
      if left and right then
        local shared = spans_beyond_band(left) or spans_beyond_band(right)
        if shared and split_guard and split_guard.shared_done then
          local cut = right[pos_key]
          if split_guard.shared_done[cut] then
            break
          end
          split_guard.shared_done[cut] = true
        end
        adjust_pair(window, tab, { left = left, right = right }, axis, desired - left[size_key])
        break
      end
    end
  end
end

local function cluster_groups(infos, pos_key)
  local sorted = {}
  for _, info in ipairs(infos) do
    sorted[#sorted + 1] = info
  end
  table.sort(sorted, function(a, b)
    if a[pos_key] == b[pos_key] then
      return a.left < b.left
    end
    return a[pos_key] < b[pos_key]
  end)

  local groups = {}
  for _, info in ipairs(sorted) do
    local last = groups[#groups]
    if last and math.abs(info[pos_key] - last.pos) <= CELL_SLACK then
      last.panes[#last.panes + 1] = info
    else
      groups[#groups + 1] = { pos = info[pos_key], panes = { info } }
    end
  end
  return groups
end

local function group_as_node(group)
  if #group.panes == 1 then
    return { kind = 'leaf', info = group.panes[1] }
  end
  return fanout_leaves(group.panes, 'hsplit')
end

local function infos_to_axis_nodes(infos, axis)
  local pos_key = axis == 'width' and 'left' or 'top'
  local nodes = {}
  for _, group in ipairs(cluster_groups(infos, pos_key)) do
    nodes[#nodes + 1] = group_as_node(group)
  end
  return nodes
end

-- 通高／通寬 pane 只出現在 cluster 的第一帶；其他列／欄均分時要補回來。
local function expand_band(infos, band, cross_pos, cross_size)
  local span = math.huge
  for _, pane in ipairs(band.panes) do
    span = math.min(span, pane[cross_size])
  end
  if span == math.huge then
    return band.panes
  end

  local seen = {}
  local panes = {}
  for _, pane in ipairs(band.panes) do
    seen[pane.pane:pane_id()] = true
    panes[#panes + 1] = pane
  end
  for _, info in ipairs(infos) do
    local id = info.pane:pane_id()
    if not seen[id] and ranges_overlap_exclusive(
      band.pos,
      span,
      info[cross_pos],
      info[cross_size]
    ) then
      seen[id] = true
      panes[#panes + 1] = info
    end
  end
  return panes, span
end

-- 寬：每一列自己均分（田字上下分割線可以不對齊）；通高左欄要算進每一列。
-- 高：每一欄自己均分。
local function equalize_tree_axis(window, tab, infos, axis)
  local pos_key = axis == 'width' and 'left' or 'top'
  local mux_extent = axis_extent(infos, pos_key, axis)
  local usable = usable_axis_extent(tab, axis, mux_extent)
  local band_key = axis == 'width' and 'top' or 'left'
  local cross_size = axis == 'width' and 'height' or 'width'
  local shared_done = {}

  for _, band in ipairs(cluster_groups(infos, band_key)) do
    local panes, band_span = expand_band(infos, band, band_key, cross_size)
    local nodes = infos_to_axis_nodes(panes, axis)
    if #nodes >= 2 then
      equalize_nodes(window, tab, nodes, axis, usable, {
        band_pos = band.pos,
        band_span = band_span,
        cross_pos = band_key,
        cross_size = cross_size,
        shared_done = shared_done,
      })
    end
  end
end

local function overlapping_infos(infos, active, axis)
  local pos_key = axis == 'width' and 'top' or 'left'
  local size_key = axis == 'width' and 'height' or 'width'
  local subset = {}
  for _, info in ipairs(infos) do
    if ranges_overlap_exclusive(
      active[pos_key],
      active[size_key],
      info[pos_key],
      info[size_key]
    ) then
      subset[#subset + 1] = info
    end
  end
  return subset
end

local function equalize_panes(window, pane, scope, axis)
  local tab = pane:tab()
  if not tab then
    return
  end

  tab:set_zoomed(false)
  revive_collapsed_panes(window, tab)
  local infos = tab:panes_with_info()
  if #infos < 2 then
    pane:activate()
    return
  end

  local active
  for _, info in ipairs(infos) do
    if info.pane:pane_id() == pane:pane_id() then
      active = info
      break
    end
  end
  if not active then
    pane:activate()
    return
  end

  local function run(target_axis)
    local target = infos
    if scope == 'band' then
      target = overlapping_infos(infos, active, target_axis)
    end
    if #target >= 2 then
      equalize_tree_axis(window, tab, target, target_axis)
      infos = refresh_infos(tab, infos)
      active = pane_info_by_id(tab)[pane:pane_id()] or active
    end
  end

  if axis == 'both' then
    run 'height'
    run 'width'
  else
    run(axis)
  end

  pane:activate()
end

local function equalize_action(scope, axis)
  return wezterm.action_callback(function(window, pane)
    equalize_panes(window, pane, scope, axis)
  end)
end

local SIMULATOR_ROOT = 'C:\\Users\\user\\Documents\\RyokoTower'
local SIMULATOR_PYTHON = SIMULATOR_ROOT .. '\\.venv\\Scripts\\python.exe'

local function simulator_args(script, ...)
  local args = { SIMULATOR_PYTHON, SIMULATOR_ROOT .. '\\' .. script }
  for _, arg in ipairs({ ... }) do
    table.insert(args, arg)
  end
  return args
end

-- CCaption | LanePLC   | Tower1 | CardR
-- CCaption | LprAccess | Tower2 | RemoteC
local function ccaption_spawn()
  return {
    cwd = SIMULATOR_ROOT,
    args = simulator_args(
      'scripts\\serial-tools\\cc_display_simulator.py',
      '--port', 'COM9',
      '--stations', 'A4,A6,A9,B1,B2'
    ),
  }
end

local function layout_simulators(tab, cc)
  local root = SIMULATOR_ROOT
  tab:set_title('Simulators')

  local lane = cc:split {
    direction = 'Right',
    size = 0.75,
    cwd = root,
    args = simulator_args(
      'scripts\\plc-simulator\\lane_plc_simulator.py',
      '--port', 'COM15',
      '--slaves', '10,11',
      '--cli'
    ),
  }
  local tower = lane:split {
    direction = 'Right',
    size = 2 / 3,
    cwd = root,
    args = simulator_args(
      'scripts\\plc-simulator\\tower_plc_v2_simulator.py',
      '--port', 'COM13',
      '--cli',
      '--slave', '1'
    ),
  }
  local card = tower:split {
    direction = 'Right',
    size = 0.5,
    cwd = root,
    args = simulator_args(
      'scripts\\serial-tools\\card_reader_simulator.py',
      '--port', 'COM7'
    ),
  }
  lane:split {
    direction = 'Bottom',
    size = 0.5,
    cwd = root,
    args = simulator_args(
      'scripts\\serial-tools\\payment_system_simulator.py',
      '--port', 'COM17'
    ),
  }
  tower:split {
    direction = 'Bottom',
    size = 0.5,
    cwd = root,
    args = simulator_args(
      'scripts\\plc-simulator\\tower_plc_v2_simulator.py',
      '--port', 'COM21',
      '--cli',
      '--slave', '3'
    ),
  }
  card:split {
    direction = 'Bottom',
    size = 0.5,
    cwd = root,
    args = simulator_args(
      'scripts\\serial-tools\\remote_control_simulator.py',
      '--port', 'COM5'
    ),
  }
  tab:activate()
end

local function notify_spawn_error(gui_win, err)
  if gui_win then
    gui_win:toast_notification('WezTerm', tostring(err), nil, 4000)
  end
end

local function spawn_simulators_tab(gui_win, pane)
  local mux_win = pane:window()
  if not mux_win then
    return
  end

  local ok, err = pcall(function()
    local tab, cc = mux_win:spawn_tab(ccaption_spawn())
    layout_simulators(tab, cc)
  end)

  if not ok then
    notify_spawn_error(gui_win, err)
  end
end

local function layout_simulators_when_maximized(gui_win, src_pane, tab, cc, gui)
  local src_tab = src_pane:tab()
  local src_size = src_tab and src_tab:get_size() or {}
  local src_ok, src_dims = pcall(function()
    return gui_win:get_dimensions()
  end)

  local function layout_now()
    local laid_ok, laid_err = pcall(function()
      layout_simulators(tab, cc)
      if gui then
        equalize_panes(gui, cc, 'tab', 'both')
      end
    end)
    if not laid_ok then
      notify_spawn_error(gui_win, laid_err)
    end
  end

  if not gui then
    layout_now()
    return
  end

  local tries = 0
  local last_signature
  local function tick()
    tries = tries + 1
    local dims_ok, dims = pcall(function()
      return gui:get_dimensions()
    end)
    local size_ok, size = pcall(function()
      return tab:get_size()
    end)
    local signature
    local matched = false
    if dims_ok and size_ok and dims and size and src_ok and src_dims and src_size.cols then
      signature = table.concat({
        dims.pixel_width or 0,
        dims.pixel_height or 0,
        size.cols or 0,
        size.rows or 0,
      }, 'x')
      matched = (dims.pixel_width or 0) >= (src_dims.pixel_width or 0) - 48
        and (dims.pixel_height or 0) >= (src_dims.pixel_height or 0) - 48
        and (size.cols or 0) >= src_size.cols - 2
        and (size.rows or 0) >= (src_size.rows or 0) - 2
    end
    local stable = signature and signature == last_signature
    last_signature = signature
    if (matched and stable) or tries >= 40 then
      layout_now()
      return
    end
    wezterm.time.call_after(0.05, tick)
  end

  wezterm.time.call_after(0.05, tick)
end

local function spawn_simulators_window(gui_win, pane)
  local ok, err = pcall(function()
    local tab, cc, window = mux.spawn_window(ccaption_spawn())
    local gui = window:gui_window()
    if gui then
      gui:maximize()
    end
    layout_simulators_when_maximized(gui_win, pane, tab, cc, gui)
  end)

  if not ok then
    notify_spawn_error(gui_win, err)
  end
end

wezterm.on('augment-command-palette', function()
  return {
    {
      brief = 'RyokoTower Simulators (新分頁)',
      doc = '在目前視窗開 Simulators tab，跑 RyokoTower 的七個模擬器',
      icon = 'md_tab_plus',
      action = wezterm.action_callback(spawn_simulators_tab),
    },
    {
      brief = 'RyokoTower Simulators (新視窗)',
      doc = '開一個新視窗，跑 RyokoTower 的七個模擬器',
      icon = 'md_window_restore',
      action = wezterm.action_callback(spawn_simulators_window),
    },
    {
      brief = 'Sync: 送到其他 pane',
      doc = '把目前 pane 的輸入列送到同 tab 其他 pane，並在目前 pane 送出 Enter',
      icon = 'md_sync',
      action = wezterm.action_callback(sync_current_command_to_other_panes),
    },
    {
      brief = 'Close tab',
      doc = '關閉目前的 tab',
      icon = 'md_tab_remove',
      action = act.CloseCurrentTab { confirm = true },
    },
    {
      brief = 'Equalize: 平均分配欄寬 (僅同列)',
      doc = '就地均分與目前 pane 同一列的欄寬',
      icon = 'md_arrow_expand_horizontal',
      action = equalize_action('band', 'width'),
    },
    {
      brief = 'Equalize: 平均分配欄寬 (Tab)',
      doc = '就地均分目前 tab 的所有欄寬',
      icon = 'md_view_column',
      action = equalize_action('tab', 'width'),
    },
    {
      brief = 'Equalize: 平均分配欄高 (僅同欄)',
      doc = '就地均分與目前 pane 同一欄的列高',
      icon = 'md_arrow_expand_vertical',
      action = equalize_action('band', 'height'),
    },
    {
      brief = 'Equalize: 平均分配欄高 (Tab)',
      doc = '就地均分目前 tab 的所有列高',
      icon = 'md_view_agenda',
      action = equalize_action('tab', 'height'),
    },
    {
      brief = 'Equalize: 平均分配欄寬高 (Tab)',
      doc = '就地均分目前 tab 的欄寬與列高',
      icon = 'md_view_dashboard',
      action = equalize_action('tab', 'both'),
    },
  }
end)

local shifted_number_keys = { '!', '@', '#', '$', '%', '^', '&', '*', '(' }

local function wezterm_exe()
  local dir = wezterm.executable_dir
  if dir and dir ~= '' then
    return dir .. '\\wezterm.exe'
  end
  return 'wezterm.exe'
end

local function tab_active_pane(tab)
  for _, info in ipairs(tab:panes_with_info()) do
    if info.is_active then
      return info.pane
    end
  end
  local panes = tab:panes()
  return panes and panes[1]
end

local function layout_overflows(infos, size)
  for _, info in ipairs(infos) do
    if info.left + info.width > size.cols + CELL_SLACK
      or info.top + info.height > size.rows + CELL_SLACK then
      return true
    end
  end
  return false
end

local function same_position(infos, key)
  local origin = infos[1][key]
  for _, info in ipairs(infos) do
    if math.abs(info[key] - origin) > CELL_SLACK then
      return false
    end
  end
  return true
end

local function shrink_cells(cells_list, room)
  local fitted = {}
  local sum = 0
  for _, cells in ipairs(cells_list) do
    local size = math.max(1, cells)
    fitted[#fitted + 1] = size
    sum = sum + size
  end
  if sum <= room or sum == 0 then
    return fitted
  end

  local used = 0
  for index, cells in ipairs(fitted) do
    if index == #fitted then
      fitted[index] = math.max(1, room - used)
    else
      local share = math.max(1, math.floor(cells * room / sum))
      local remain_slots = #fitted - index
      if used + share > room - remain_slots then
        share = math.max(1, room - used - remain_slots)
      end
      fitted[index] = share
      used = used + share
    end
  end
  return fitted
end

-- 視窗變窄時，直向或橫向一疊 pane 的分割節點可能仍是舊尺寸。
-- 那個尺寸比 tab 大，Split 會直接 No space for split。
-- 先把其他 pane 移出，剩下的根 pane 會回到 tab 尺寸，再依原高度／寬度移回來。
local function refit_overflow_layout(window, pane)
  local tab = pane:tab()
  if not tab then
    return true
  end
  tab:set_zoomed(false)

  local size = tab:get_size()
  local infos = tab:panes_with_info()
  if not size or #infos < 2 or not layout_overflows(infos, size) then
    return true
  end

  local vertical = same_position(infos, 'left')
  local horizontal = same_position(infos, 'top')
  if not vertical and not horizontal then
    window:toast_notification('WezTerm', 'pane 超出視窗，無法分割', nil, 4000)
    return false
  end

  local pos_key = vertical and 'top' or 'left'
  local size_key = vertical and 'height' or 'width'
  local direction = vertical and '--bottom' or '--right'
  local limit = vertical and size.rows or size.cols
  table.sort(infos, function(a, b)
    if a[pos_key] == b[pos_key] then
      return a.pane:pane_id() < b.pane:pane_id()
    end
    return a[pos_key] < b[pos_key]
  end)

  local room = limit - (#infos - 1) - 1
  if room < #infos - 1 then
    window:toast_notification('WezTerm', 'pane 超出視窗，無法分割', nil, 4000)
    return false
  end

  local anchor_id = infos[1].pane:pane_id()
  local moved = {}
  for index = 2, #infos do
    moved[#moved + 1] = {
      id = infos[index].pane:pane_id(),
      cells = infos[index][size_key],
    }
  end
  local cells_list = {}
  for _, item in ipairs(moved) do
    cells_list[#cells_list + 1] = item.cells
  end
  cells_list = shrink_cells(cells_list, room)
  for index, cells in ipairs(cells_list) do
    moved[index].cells = cells
  end

  for index = #moved, 1, -1 do
    local moved_pane = wezterm.mux.get_pane(moved[index].id)
    if not moved_pane then
      window:toast_notification('WezTerm', '找不到要收回的 pane', nil, 4000)
      return false
    end
    moved_pane:move_to_new_tab()
  end

  for index = #moved, 1, -1 do
    local item = moved[index]
    local ok, _, err = wezterm.run_child_process {
      wezterm_exe(),
      'cli',
      'split-pane',
      direction,
      '--cells',
      tostring(item.cells),
      '--move-pane-id',
      tostring(item.id),
      '--pane-id',
      tostring(anchor_id),
    }
    if not ok then
      window:toast_notification(
        'WezTerm',
        tostring(err or '無法把超出視窗的 pane 收回'),
        nil,
        4000
      )
      return false
    end
  end

  local active = wezterm.mux.get_pane(pane:pane_id())
  if active then
    active:activate()
  end
  return true
end

local function split_action(direction, args)
  return wezterm.action_callback(function(window, pane)
    if not refit_overflow_layout(window, pane) then
      return
    end
    local spec = { domain = 'CurrentPaneDomain' }
    if args then
      spec.args = args
    end
    local action = direction == 'Right' and act.SplitHorizontal(spec) or act.SplitVertical(spec)
    window:perform_action(action, pane)
  end)
end

-- 把目前 pane 移到指定 tab（1 起算）；該 tab 不存在則開新 tab。
local function move_pane_to_tab(index)
  return wezterm.action_callback(function(gui_win, pane)
    local mux_win = pane:window()
    if not mux_win then
      return
    end

    local tabs = mux_win:tabs()
    local target = tabs[index]
    if not target then
      pane:move_to_new_tab()
      return
    end

    local current = pane:tab()
    if current and current:tab_id() == target:tab_id() then
      return
    end

    local dest = tab_active_pane(target)
    if not dest then
      return
    end

    local ok, _, err = wezterm.run_child_process {
      wezterm_exe(),
      'cli',
      'split-pane',
      '--right',
      '--top-level',
      '--move-pane-id',
      tostring(pane:pane_id()),
      '--pane-id',
      tostring(dest:pane_id()),
    }
    if not ok then
      gui_win:toast_notification(
        'WezTerm',
        tostring(err or '無法把 pane 移到指定 tab'),
        nil,
        4000
      )
      return
    end

    -- --top-level 之後原 pane 常仍佔滿整寬，移入的 pane 重疊而點不到、方向鍵也找不到。
    equalize_panes(gui_win, pane, 'tab', 'width')
    pane:activate()
  end)
end

config.keys = {
  -- Pane 分割、zoom、切換。
  { key = 'z', mods = 'ALT', action = act.TogglePaneZoomState },
  { key = ']', mods = 'ALT', action = activate_pane 'next' },
  { key = '[', mods = 'ALT', action = activate_pane 'previous' },
  { key = 'LeftArrow', mods = 'ALT', action = activate_pane_direction 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = activate_pane_direction 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = activate_pane_direction 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = activate_pane_direction 'Down' },

  -- Pane 大小。
  { key = 'LeftArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'RightArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Right', 5 } },
  { key = 'UpArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Up', 2 } },
  { key = 'DownArrow', mods = 'ALT|SHIFT', action = act.AdjustPaneSize { 'Down', 2 } },

  -- Prefix 操作。
  { key = '\\', mods = 'LEADER', action = split_action 'Right' },
  { key = '-', mods = 'LEADER', action = split_action 'Bottom' },
  { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = false } },
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'LEADER', action = act.CloseCurrentTab { confirm = true } },
  { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },
  { key = 'p', mods = 'LEADER', action = act.ActivateTabRelative(-1) },
  { key = ',', mods = 'LEADER', action = rename_tab },
  { key = 'l', mods = 'LEADER', action = act.ShowLauncher },
  {
    key = 'q',
    mods = 'LEADER',
    action = wezterm.action_callback(function(window, pane)
      local tab = pane:tab()
      if tab then
        tab:set_zoomed(false)
        revive_collapsed_panes(window, tab)
      end
      window:perform_action(act.PaneSelect { alphabet = '123456789' }, pane)
    end),
  },
  { key = 's', mods = 'LEADER', action = act.PaneSelect { mode = 'SwapWithActiveKeepFocus' } },
  { key = 'PageUp', mods = 'CTRL', action = act.ActivateTabRelative(-1) },
  { key = 'PageDown', mods = 'CTRL', action = act.ActivateTabRelative(1) },
  {
    key = 'u',
    mods = 'CTRL',
    action = act.ActivateKeyTable {
      name = 'ubuntu',
      one_shot = true,
      timeout_milliseconds = PREFIX_TIMEOUT_MS,
    },
  },

  -- 捲動與搜尋。
  { key = 'u', mods = 'CTRL|SHIFT', action = act.ScrollByPage(-1) },
  { key = 'd', mods = 'CTRL|SHIFT', action = act.ScrollByPage(1) },
  { key = 'f', mods = 'CTRL|SHIFT', action = act.Search 'CurrentSelectionOrEmptyString' },
}

config.key_tables = {
  ubuntu = {
    {
      key = 'c',
      action = act.SpawnCommandInNewTab {
        args = ubuntu_wsl,
      },
    },
    {
      key = '\\',
      action = split_action('Right', ubuntu_wsl),
    },
    {
      key = '-',
      action = split_action('Bottom', ubuntu_wsl),
    },
  },
}

for number = 1, 9 do
  table.insert(config.keys, {
    key = tostring(number),
    mods = 'ALT',
    action = activate_pane(number),
  })
  table.insert(config.keys, {
    key = tostring(number),
    mods = 'LEADER',
    action = act.ActivateTab(number - 1),
  })
  table.insert(config.keys, {
    key = tostring(number),
    mods = 'LEADER|SHIFT',
    action = move_pane_to_tab(number),
  })
  table.insert(config.keys, {
    key = shifted_number_keys[number],
    mods = 'LEADER',
    action = move_pane_to_tab(number),
  })
  table.insert(config.keys, {
    key = shifted_number_keys[number],
    mods = 'LEADER|SHIFT',
    action = move_pane_to_tab(number),
  })
end

config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection 'Clipboard',
  },
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.PasteFrom 'Clipboard',
  },
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.Nop,
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.OpenLinkAtMouseCursor,
  },
}

return config
