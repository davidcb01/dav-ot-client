if not MiscAnalyser then
  MiscAnalyser = {
    launchTime = 0,
    session = 0,
    charms = {},
    imbuements = {},
    upgrades = {},
    window = nil,
  }
  MiscAnalyser.__index = MiscAnalyser
end

local CHARM_PATTERNS = {
  { id = 0,  name = 'Wound',            pattern = 'wound charm' },
  { id = 1,  name = 'Enflame',          pattern = 'enflame charm' },
  { id = 2,  name = 'Poison',           pattern = 'poison charm' },
  { id = 3,  name = 'Freeze',           pattern = 'freeze charm' },
  { id = 4,  name = 'Zap',              pattern = 'zap charm' },
  { id = 5,  name = 'Curse',            pattern = 'curse charm' },
  { id = 6,  name = 'Cripple',          pattern = 'cripple charm' },
  { id = 7,  name = 'Parry',            pattern = 'parry charm' },
  { id = 8,  name = 'Dodge',            pattern = 'dodge charm' },
  { id = 9,  name = 'Adrenaline Burst', pattern = 'adrenaline' },
  { id = 10, name = 'Numb',             pattern = 'numb charm' },
  { id = 11, name = 'Cleanse',          pattern = 'cleanse charm' },
  { id = 12, name = 'Bless',            pattern = 'bless charm' },
  { id = 13, name = 'Scavenge',         pattern = 'scavenge charm' },
  { id = 14, name = 'Gut',              pattern = 'gut charm' },
  { id = 15, name = 'Low Blow',         pattern = 'low blow charm' },
  { id = 16, name = 'Divine Wrath',     pattern = 'divine wrath charm' },
  { id = 17, name = 'Vampiric Embrace', pattern = 'vampiric embrace charm' },
  { id = 18, name = "Void's Call",      pattern = "void's call charm" },
  { id = 19, name = 'Savage Blow',      pattern = 'savage blow charm' },
  { id = 20, name = 'Fatal Hold',       pattern = 'fatal hold charm' },
  { id = 21, name = 'Void Inversion',   pattern = 'void inversion charm' },
  { id = 22, name = 'Carnage',          pattern = 'carnage charm' },
  { id = 23, name = 'Overpower',        pattern = 'overpower charm' },
  { id = 24, name = 'Overflux',         pattern = 'overflux charm' },
}

local IMBUEMENT_META = {
  critical   = { name = 'Critical Hit', icon = '/images/game/analyzer/misc/critical' },
  lifeLeech  = { name = 'Life Leech',   icon = '/images/game/analyzer/misc/life-leech' },
  manaLeech  = { name = 'Mana Leech',   icon = '/images/game/analyzer/misc/mana-leech' },
}

local UPGRADE_META = {
  onslaught     = { name = 'Onslaught',     icon = '/images/game/analyzer/misc/onslaught' },
  ruse          = { name = 'Ruse',          icon = '/images/game/analyzer/misc/ruse' },
  momentum      = { name = 'Momentum',      icon = '/images/game/analyzer/misc/momentum' },
  transcendence = { name = 'Transcendence', icon = '/images/game/analyzer/misc/transcendence' },
}

function MiscAnalyser:create()
  MiscAnalyser.launchTime = 0
  MiscAnalyser.session = 0
  MiscAnalyser.charms = {}
  MiscAnalyser.imbuements = {}
  MiscAnalyser.upgrades = {}
  MiscAnalyser.window = openedWindows['miscButton']
  if not MiscAnalyser.window then
    return
  end

  local toggleFilterButton = MiscAnalyser.window:recursiveGetChildById('toggleFilterButton')
  if toggleFilterButton then
    toggleFilterButton:setVisible(false)
  end

  local newWindowButton = MiscAnalyser.window:recursiveGetChildById('newWindowButton')
  if newWindowButton then
    newWindowButton:setVisible(false)
  end

  local contextMenuButton = MiscAnalyser.window:recursiveGetChildById('contextMenuButton')
  local minimizeButton = MiscAnalyser.window:recursiveGetChildById('minimizeButton')
  if contextMenuButton and minimizeButton then
    contextMenuButton:setVisible(true)
    contextMenuButton:breakAnchors()
    contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
    contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
    contextMenuButton:setMarginRight(7)
    contextMenuButton:setMarginTop(0)
    contextMenuButton.onClick = function(_, mousePos)
      return modules.game_analyser.onMiscExtra(mousePos or g_window.getMousePosition())
    end
  end

  local lockButton = MiscAnalyser.window:recursiveGetChildById('lockButton')
  if lockButton and contextMenuButton then
    lockButton:breakAnchors()
    lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
    lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
    lockButton:setMarginRight(2)
    lockButton:setMarginTop(0)
  end

  MiscAnalyser.window:setContentMinimumHeight(80)
end

function MiscAnalyser:reset()
  MiscAnalyser.launchTime = g_clock.millis()
  MiscAnalyser.session = os.time()
  MiscAnalyser.charms = {}
  MiscAnalyser.imbuements = {}
  MiscAnalyser.upgrades = {}
  MiscAnalyser:rebuildLists()
  MiscAnalyser:updateWindow(true)
end

local function populateSection(listWidget, entries, iconResolver)
  if not listWidget then
    return
  end
  listWidget:destroyChildren()

  local ordered = {}
  for key, data in pairs(entries) do
    table.insert(ordered, { key = key, data = data })
  end
  table.sort(ordered, function(a, b)
    if a.data.count ~= b.data.count then
      return a.data.count > b.data.count
    end
    return tostring(a.data.name) < tostring(b.data.name)
  end)

  if #ordered == 0 then
    g_ui.createWidget('MiscNoDataRow', listWidget)
    return
  end

  for _, item in ipairs(ordered) do
    local row = g_ui.createWidget('MiscEntryRow', listWidget)
    local iconPath = iconResolver(item.key, item.data)
    if iconPath and g_resources.fileExists(iconPath .. '.png') then
      row.icon:setImageSource(iconPath)
    end
    row.name:setText(item.data.name)
    row.count:setText(string.format('%dx', item.data.count))
    local tip = item.data.name .. ': ' .. item.data.count .. 'x'
    if (item.data.amount or 0) > 0 then
      tip = tip .. '\nTotal value: ' .. comma_value(item.data.amount)
    end
    row:setTooltip(tip)
  end
end

function MiscAnalyser:rebuildLists()
  if not MiscAnalyser.window or not MiscAnalyser.window.contentsPanel then
    return
  end
  local cp = MiscAnalyser.window.contentsPanel
  populateSection(cp.charmList, MiscAnalyser.charms, function(key)
    return '/images/game/analyzer/charm_runes/charm_' .. tostring(key)
  end)
  populateSection(cp.imbuementList, MiscAnalyser.imbuements, function(key)
    local meta = IMBUEMENT_META[key]
    return meta and meta.icon or nil
  end)
  populateSection(cp.upgradeList, MiscAnalyser.upgrades, function(key)
    local meta = UPGRADE_META[key]
    return meta and meta.icon or nil
  end)
end

function MiscAnalyser:updateWindow(ignoreVisible)
  if not MiscAnalyser.window or not MiscAnalyser.window.contentsPanel then
    return
  end
  if not ignoreVisible and not MiscAnalyser.window:isVisible() then
    return
  end

  local contentsPanel = MiscAnalyser.window.contentsPanel
  local session = MiscAnalyser.session
  if not session or session == 0 then
    contentsPanel.session:setText('00:00h')
  else
    local duration = math.max(0, os.time() - session)
    local hours = math.floor(duration / 3600)
    local minutes = math.floor((duration % 3600) / 60)
    contentsPanel.session:setText(string.format('%02d:%02dh', hours, minutes))
  end

  if contentsPanel.charmList and contentsPanel.charmList:getChildCount() == 0 then
    MiscAnalyser:rebuildLists()
  end
end

local function recordEntry(bucket, key, name, amount)
  if not bucket[key] then
    bucket[key] = { name = name, count = 0, amount = 0 }
  end
  bucket[key].count = bucket[key].count + 1
  if amount and amount > 0 then
    bucket[key].amount = bucket[key].amount + amount
  end
end

function MiscAnalyser:onTextMessage(mode, text)
  if not text or text == '' or not g_game.isOnline() then
    return
  end

  local lower = text:lower()
  local changed = false
  local dmg = tonumber(text:match('loses (%d+) hitpoints')) or tonumber(text:match('loses (%d+) health')) or 0

  -- Charm procs
  for _, charm in ipairs(CHARM_PATTERNS) do
    if lower:find(charm.pattern, 1, true) then
      recordEntry(MiscAnalyser.charms, charm.id, charm.name, dmg)
      changed = true
      break
    end
  end

  -- Item Upgrade (Forge Exaltation) procs
  if lower:find('(onslaught)', 1, true) or lower:find('(amplified onslaught)', 1, true) then
    recordEntry(MiscAnalyser.upgrades, 'onslaught', UPGRADE_META.onslaught.name, dmg)
    changed = true
  end
  if lower:find('you dodged an attack', 1, true) then
    recordEntry(MiscAnalyser.upgrades, 'ruse', UPGRADE_META.ruse.name, 0)
    changed = true
  end
  if lower:find('(momentum)', 1, true) or lower:find('momentum triggered', 1, true) then
    recordEntry(MiscAnalyser.upgrades, 'momentum', UPGRADE_META.momentum.name, 0)
    changed = true
  end
  if lower:find('(transcendence)', 1, true) or lower:find('transcendence triggered', 1, true) then
    recordEntry(MiscAnalyser.upgrades, 'transcendence', UPGRADE_META.transcendence.name, 0)
    changed = true
  end

  -- Critical Hit (when attacking)
  if lower:find('due to your critical attack', 1, true) then
    recordEntry(MiscAnalyser.imbuements, 'critical', IMBUEMENT_META.critical.name, dmg)
    changed = true
  end
  if lower:find('life leech', 1, true) then
    local val = tonumber(text:match('(%d+) hitpoints')) or 0
    recordEntry(MiscAnalyser.imbuements, 'lifeLeech', IMBUEMENT_META.lifeLeech.name, val)
    changed = true
  end
  if lower:find('mana leech', 1, true) then
    local val = tonumber(text:match('(%d+) mana')) or 0
    recordEntry(MiscAnalyser.imbuements, 'manaLeech', IMBUEMENT_META.manaLeech.name, val)
    changed = true
  end

  if changed then
    MiscAnalyser:rebuildLists()
  end
end

function MiscAnalyser:getSummaryText()
  local lines = {}
  local session = MiscAnalyser.session or 0
  local duration = session > 0 and math.max(0, os.time() - session) or 0
  table.insert(lines, string.format('Session: %02d:%02dh', math.floor(duration / 3600), math.floor((duration % 3600) / 60)))

  local function dumpSection(title, bucket)
    table.insert(lines, title)
    local has = false
    for _, entry in pairs(bucket) do
      has = true
      table.insert(lines, string.format('  %s: %dx', entry.name, entry.count))
    end
    if not has then
      table.insert(lines, '  No data yet')
    end
  end

  dumpSection('Charm:', MiscAnalyser.charms)
  dumpSection('Imbuement:', MiscAnalyser.imbuements)
  dumpSection('Item Upgrade:', MiscAnalyser.upgrades)
  return table.concat(lines, '\n')
end

function onMiscExtra(mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Reset Data'), function()
    MiscAnalyser:reset()
  end)
  menu:addOption(tr('Copy to Clipboard'), function()
    g_window.setClipboardText(MiscAnalyser:getSummaryText())
  end)
  menu:display(mousePos)
  return true
end
