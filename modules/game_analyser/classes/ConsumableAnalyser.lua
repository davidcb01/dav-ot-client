if not ConsumableAnalyser then
  ConsumableAnalyser = {
    timers = {},
    widgets = {},
    window = nil,
  }
  ConsumableAnalyser.__index = ConsumableAnalyser
end

local BUFF_POTIONS = {
  [7439] = {
    key = 'berserk_potion',
    itemId = 7439,
    name = 'Berserk Potion',
    effect = '+5 melee, -10 shielding',
    duration = 600,
    sayText = 'you feel stronger.',
    borderColor = '#d9534f',
  },
  [7440] = {
    key = 'mastermind_potion',
    itemId = 7440,
    name = 'Mastermind Potion',
    effect = '+3 magic level',
    duration = 600,
    sayText = 'you feel smarter.',
    borderColor = '#4fa3f7',
  },
  [7443] = {
    key = 'bullseye_potion',
    itemId = 7443,
    name = 'Bullseye Potion',
    effect = '+5 distance, -10 shielding',
    duration = 600,
    sayText = 'you feel more accurate.',
    borderColor = '#b46be6',
  },
  [49271] = {
    key = 'transcendence_potion',
    itemId = 49271,
    name = 'Transcendence Potion',
    effect = '+4 fist fighting',
    duration = 600,
    sayText = 'you feel more balanced.',
    borderColor = '#5cb85c',
  },
}

local CONCOCTION_EFFECTS = {
  ['strike enhancement']      = '+5% critical hit chance',
  ['charm upgrade']           = '+5% charm trigger chance',
  ['wealth duplex']           = '2x loot rate',
  ['bestiary betterment']     = '2x bestiary kill progress',
  ['fire resilience']         = '+8% fire protection',
  ['ice resilience']          = '+8% ice protection',
  ['earth resilience']        = '+8% earth protection',
  ['energy resilience']       = '+8% energy protection',
  ['holy resilience']         = '+8% holy protection',
  ['death resilience']        = '+8% death protection',
  ['physical resilience']     = '+8% physical protection',
  ['fire amplification']      = '+8% fire damage',
  ['ice amplification']       = '+8% ice damage',
  ['earth amplification']     = '+8% earth damage',
  ['energy amplification']    = '+8% energy damage',
  ['holy amplification']      = '+8% holy damage',
  ['death amplification']     = '+8% death damage',
  ['physical amplification']  = '+8% physical damage',
}

local function formatCountdown(seconds)
  seconds = math.max(0, math.floor(seconds))
  local hours = math.floor(seconds / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60
  if hours > 0 then
    return string.format('%dh%02d', hours, mins)
  end
  return string.format('%d:%02d', mins, secs)
end

local function parseDurationWords(words)
  if not words then
    return 0
  end
  local total = 0
  for num, unit in words:lower():gmatch('(%d+)%s*(%a+)') do
    local n = tonumber(num) or 0
    if unit:find('hour') then
      total = total + n * 3600
    elseif unit:find('minute') then
      total = total + n * 60
    elseif unit:find('second') then
      total = total + n
    end
  end
  return total
end

function ConsumableAnalyser:create()
  ConsumableAnalyser.timers = {}
  ConsumableAnalyser.widgets = {}
  ConsumableAnalyser.window = openedWindows['consumableButton']
  if not ConsumableAnalyser.window then
    return
  end

  local toggleFilterButton = ConsumableAnalyser.window:recursiveGetChildById('toggleFilterButton')
  if toggleFilterButton then
    toggleFilterButton:setVisible(false)
  end

  local newWindowButton = ConsumableAnalyser.window:recursiveGetChildById('newWindowButton')
  if newWindowButton then
    newWindowButton:setVisible(false)
  end

  local contextMenuButton = ConsumableAnalyser.window:recursiveGetChildById('contextMenuButton')
  local minimizeButton = ConsumableAnalyser.window:recursiveGetChildById('minimizeButton')
  if contextMenuButton and minimizeButton then
    contextMenuButton:setVisible(true)
    contextMenuButton:breakAnchors()
    contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
    contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
    contextMenuButton:setMarginRight(7)
    contextMenuButton:setMarginTop(0)
    contextMenuButton.onClick = function(_, mousePos)
      return modules.game_analyser.onConsumableExtra(mousePos or g_window.getMousePosition())
    end
  end

  local lockButton = ConsumableAnalyser.window:recursiveGetChildById('lockButton')
  if lockButton and contextMenuButton then
    lockButton:breakAnchors()
    lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
    lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
    lockButton:setMarginRight(2)
    lockButton:setMarginTop(0)
  end

  ConsumableAnalyser.window:setContentMinimumHeight(55)
end

function ConsumableAnalyser:reset()
  ConsumableAnalyser.timers = {}
  ConsumableAnalyser.widgets = {}
  ConsumableAnalyser:rebuild()
end

function ConsumableAnalyser:startTimer(key, opts)
  if not key or not opts or not opts.duration or opts.duration <= 0 then
    return
  end
  local now = os.time()
  ConsumableAnalyser.timers[key] = {
    key = key,
    name = opts.name or key,
    effect = opts.effect or '',
    itemId = opts.itemId,
    iconSource = opts.iconSource,
    borderColor = opts.borderColor or '#b46be6',
    expiresAt = now + math.floor(opts.duration),
    duration = math.floor(opts.duration),
    isDynamic = opts.isDynamic == true,
  }
  ConsumableAnalyser:rebuild()
end

function ConsumableAnalyser:removeTimer(key)
  if ConsumableAnalyser.timers[key] then
    ConsumableAnalyser.timers[key] = nil
    ConsumableAnalyser:rebuild()
  end
end

function ConsumableAnalyser:onSupplyUsed(itemId)
  if not g_game.isOnline() or not itemId then
    return
  end
  local info = BUFF_POTIONS[itemId]
  if info then
    ConsumableAnalyser:startTimer(info.key, info)
  end
end

function ConsumableAnalyser:onTalk(name, level, mode, text)
  if not g_game.isOnline() or not text then
    return
  end
  local player = g_game.getLocalPlayer()
  if not player or name ~= player:getName() then
    return
  end
  local lower = text:lower()
  for _, info in pairs(BUFF_POTIONS) do
    if lower == info.sayText then
      ConsumableAnalyser:startTimer(info.key, info)
      return
    end
  end
end

function ConsumableAnalyser:onTextMessage(mode, text)
  if not g_game.isOnline() or not text or text == '' then
    return
  end
  local activatedName, durStr = text:match('^You have activated (.+)%. It will last for ([^%.]+)')
  if activatedName and durStr then
    local secs = parseDurationWords(durStr)
    if secs > 0 then
      local key = 'concoction_' .. activatedName:lower():gsub('%s+', '_')
      local effect = CONCOCTION_EFFECTS[activatedName:lower()] or 'Active concoction buff'
      ConsumableAnalyser:startTimer(key, {
        name = activatedName,
        effect = effect,
        duration = secs,
        iconSource = '/images/icons/icon_misc',
        borderColor = '#f0c040',
      })
    end
    return
  end

  local activeName, remStr = text:match('^Your concoction (.+) is still active for another ([^%.]+)%.')
  if activeName and remStr then
    local secs = parseDurationWords(remStr)
    if secs > 0 then
      local key = 'concoction_' .. activeName:lower():gsub('%s+', '_')
      local effect = CONCOCTION_EFFECTS[activeName:lower()] or 'Active concoction buff'
      ConsumableAnalyser:startTimer(key, {
        name = activeName,
        effect = effect,
        duration = secs,
        iconSource = '/images/icons/icon_misc',
        borderColor = '#f0c040',
      })
    end
    return
  end

  local wornOffName = text:match('^Your concoction (.+) has worn off%.')
  if wornOffName then
    local key = 'concoction_' .. wornOffName:lower():gsub('%s+', '_')
    ConsumableAnalyser:removeTimer(key)
  end
end

function ConsumableAnalyser:syncXpBoost()
  local player = g_game.getLocalPlayer()
  if not player or not player.getStoreExpBoostTime then
    return
  end
  local boostTime = player:getStoreExpBoostTime() or 0
  if boostTime > 0 then
    local existing = ConsumableAnalyser.timers['xp_boost']
    ConsumableAnalyser.timers['xp_boost'] = {
      key = 'xp_boost',
      name = 'XP Boost',
      effect = '+50% XP Gain',
      iconSource = '/images/ui/button-storexp',
      borderColor = '#4fa3f7',
      expiresAt = os.time() + boostTime,
      remaining = boostTime,
      isDynamic = true,
    }
    if not existing then
      ConsumableAnalyser:rebuild()
    end
  elseif ConsumableAnalyser.timers['xp_boost'] then
    ConsumableAnalyser:removeTimer('xp_boost')
  end
end

function ConsumableAnalyser:rebuild()
  if not ConsumableAnalyser.window or not ConsumableAnalyser.window.contentsPanel then
    return
  end
  local cp = ConsumableAnalyser.window.contentsPanel
  local grid = cp.itemsGrid
  if not grid then
    return
  end

  grid:destroyChildren()
  ConsumableAnalyser.widgets = {}

  local now = os.time()
  local list = {}
  for key, entry in pairs(ConsumableAnalyser.timers) do
    local rem = entry.isDynamic and (entry.remaining or 0) or (entry.expiresAt - now)
    if rem > 0 then
      table.insert(list, entry)
    else
      ConsumableAnalyser.timers[key] = nil
    end
  end

  table.sort(list, function(a, b)
    if a.key == 'xp_boost' and b.key ~= 'xp_boost' then
      return false
    elseif b.key == 'xp_boost' and a.key ~= 'xp_boost' then
      return true
    end
    return (a.expiresAt or 0) < (b.expiresAt or 0)
  end)

  if cp.emptyLabel then
    cp.emptyLabel:setVisible(#list == 0)
  end

  for _, entry in ipairs(list) do
    local tile = g_ui.createWidget('ConsumableTile', grid)
    tile:setBorderColor(entry.borderColor or '#b46be6')
    if entry.itemId then
      tile.item:setItemId(entry.itemId)
      tile.item:setVisible(true)
      tile.iconFallback:setVisible(false)
    elseif entry.iconSource then
      tile.item:setVisible(false)
      tile.iconFallback:setImageSource(entry.iconSource)
      tile.iconFallback:setVisible(true)
    end
    local rem = entry.isDynamic and (entry.remaining or 0) or math.max(0, entry.expiresAt - now)
    tile.timer:setText(formatCountdown(rem))
    local tip = entry.name
    if entry.effect and entry.effect ~= '' then
      tip = tip .. '\n' .. entry.effect
    end
    tile:setTooltip(tip)
    tile.onMouseRelease = function(_, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('Remove Timer'), function()
          ConsumableAnalyser:removeTimer(entry.key)
        end)
        menu:display(mousePos)
        return true
      end
      return false
    end
    ConsumableAnalyser.widgets[entry.key] = tile
  end
end

function ConsumableAnalyser:updateWindow(ignoreVisible)
  if not g_game.isOnline() then
    return
  end
  ConsumableAnalyser:syncXpBoost()

  local now = os.time()
  local expired = false
  for key, entry in pairs(ConsumableAnalyser.timers) do
    local rem = entry.isDynamic and (entry.remaining or 0) or (entry.expiresAt - now)
    if rem <= 0 then
      ConsumableAnalyser.timers[key] = nil
      expired = true
    end
  end

  if not ConsumableAnalyser.window or not ConsumableAnalyser.window.contentsPanel then
    return
  end
  if not ignoreVisible and not ConsumableAnalyser.window:isVisible() then
    return
  end

  if expired or table.size(ConsumableAnalyser.timers) ~= table.size(ConsumableAnalyser.widgets) then
    ConsumableAnalyser:rebuild()
    return
  end

  for key, tile in pairs(ConsumableAnalyser.widgets) do
    local entry = ConsumableAnalyser.timers[key]
    if entry and tile and not tile:isDestroyed() then
      local rem = entry.isDynamic and (entry.remaining or 0) or math.max(0, entry.expiresAt - now)
      tile.timer:setText(formatCountdown(rem))
    end
  end
end

function ConsumableAnalyser:saveConfigJson()
  if not g_game.isOnline() then
    return
  end
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end
  local now = os.time()
  local data = {}
  for key, entry in pairs(ConsumableAnalyser.timers) do
    if not entry.isDynamic and entry.expiresAt and entry.expiresAt > now then
      table.insert(data, {
        key = entry.key,
        name = entry.name,
        effect = entry.effect,
        itemId = entry.itemId,
        iconSource = entry.iconSource,
        borderColor = entry.borderColor,
        remaining = entry.expiresAt - now,
      })
    end
  end
  local characterDir = '/characterdata/' .. player:getId()
  pcall(function() g_resources.makeDir('/characterdata') end)
  pcall(function() g_resources.makeDir(characterDir) end)
  local file = characterDir .. '/consumables.json'
  local ok, encoded = pcall(function() return json.encode(data, 2) end)
  if ok and encoded then
    g_resources.writeFileContents(file, encoded)
  end
end

function ConsumableAnalyser:loadConfigJson()
  if not g_game.isOnline() then
    return
  end
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end
  local file = '/characterdata/' .. player:getId() .. '/consumables.json'
  if not g_resources.fileExists(file) then
    return
  end
  local ok, decoded = pcall(function()
    return json.decode(g_resources.readFileContents(file))
  end)
  if not ok or type(decoded) ~= 'table' then
    return
  end
  for _, entry in ipairs(decoded) do
    if entry.key and entry.remaining and entry.remaining > 0 then
      ConsumableAnalyser:startTimer(entry.key, {
        name = entry.name,
        effect = entry.effect,
        itemId = entry.itemId,
        iconSource = entry.iconSource,
        borderColor = entry.borderColor,
        duration = entry.remaining,
      })
    end
  end
end

function onConsumableExtra(mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Clear All Timers'), function()
    ConsumableAnalyser:reset()
  end)
  menu:display(mousePos)
  return true
end
