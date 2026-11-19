-- Cavebot UI, floor markers, auto-recorder, settings, and walking engine

-- CAVEBOT: MINIMAP WAYPOINTS, GAME OVERLAY, START NEAREST, LURE
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Marcadores de waypoint NO CHAO (quadrado preto translucido + texto abaixo do char)
-- ---------------------------------------------------------------------------
FLOOR_WP_EFFECT_ID = 9991
lastFloorMarkAt = 0
local floorWpEffectObj = nil
local floorWpEffectTried = false
local floorLabelPool = {}
local activeFloorMarkerGroups = {}

function ensureFloorWpEffect()
  if floorWpEffectObj then return floorWpEffectObj end
  if not g_attachedEffects then return nil end

  -- Use direct image registration (game_attachedeffects is sandboxed; avoid noisy getById errors before register)
  if g_attachedEffects.registerByImage then
    local ok, reg = pcall(function()
      return g_attachedEffects.registerByImage(FLOOR_WP_EFFECT_ID, 'CavebotFloorWpBg', '/mods/game_helper/images/wp_tile_bg')
    end)
    if ok and reg then
      pcall(function()
        if reg.setSize then reg:setSize({ width = 32, height = 32 }) end
        if reg.setOpacity then reg:setOpacity(0.75) end
        if reg.setOnTop then reg:setOnTop(false) end
        if reg.setDrawOrder then reg:setDrawOrder(1) end
        if reg.setPermanent then reg:setPermanent(true) end
        if reg.setCanDrawOnUI then reg:setCanDrawOnUI(false) end
      end)
      floorWpEffectObj = reg
      return floorWpEffectObj
    end
  end

  if floorWpEffectTried then return nil end
  floorWpEffectTried = true

  local effMgr = AttachedEffectManager or (modules and modules.game_attachedeffects and modules.game_attachedeffects.AttachedEffectManager)
  if type(effMgr) == 'table' and effMgr.register then
    pcall(function()
      effMgr.register(FLOOR_WP_EFFECT_ID, 'CavebotFloorWpBg', '/mods/game_helper/images/wp_tile_bg', ThingExternalTexture, {
        size = { 32, 32 },
        opacity = 0.75,
        onTop = false,
        drawOrder = 1,
        permanent = true,
        drawOnUI = false
      })
    end)
    if g_attachedEffects.getById then
      local ok, eff = pcall(g_attachedEffects.getById, FLOOR_WP_EFFECT_ID)
      if ok and eff then
        floorWpEffectObj = eff
      end
    end
  end
  return floorWpEffectObj
end

local function hideFloorLabels()
  for i = #floorLabelPool, 1, -1 do
    local lbl = floorLabelPool[i]
    if not lbl or (lbl.isDestroyed and lbl:isDestroyed()) then
      table.remove(floorLabelPool, i)
    else
      lbl:hide()
    end
  end
end

function clearFloorMarkers()
  for _, pos in ipairs(markedWorldTiles) do
    pcall(function()
      local tile = g_map.getTile(pos)
      if tile then
        if tile.setText then tile:setText('') end
        local ground = tile.getGround and tile:getGround() or nil
        if ground and ground.detachEffectById then
          ground:detachEffectById(FLOOR_WP_EFFECT_ID)
        end
        if tile.detachEffectById then
          tile:detachEffectById(FLOOR_WP_EFFECT_ID)
        end
      end
    end)
  end
  markedWorldTiles = {}
  activeFloorMarkerGroups = {}
  hideFloorLabels()
end

function floorMarkerColor(typeLower)
  if typeLower:find('^stand') then return '#ffcc33' end
  if typeLower:find('^start lure') then return '#5ce65c' end
  if typeLower:find('^end lure') then return '#ff9944' end
  if typeLower:find('^rope') or typeLower:find('^shovel') or typeLower:find('^hole')
     or typeLower:find('^ladder') or typeLower:find('^use') then return '#66ccff' end
  return '#ffffff'
end

local function getOrCreateFloorLabel(mapPanel, index)
  local lbl = floorLabelPool[index]
  if lbl and (lbl.isDestroyed and lbl:isDestroyed()) then
    lbl = nil
  end
  if lbl and lbl.getParent and lbl:getParent() ~= mapPanel then
    pcall(function() lbl:destroy() end)
    lbl = nil
  end
  if not lbl then
    lbl = g_ui.createWidget('UILabel', mapPanel)
    lbl:setId('cbFloorWpLbl_' .. index)
    lbl:setFont('verdana-11px-rounded')
    lbl:setTextAutoResize(true)
    lbl:setPhantom(true)
    lbl:setFocusable(false)
    if AlignCenter and lbl.setTextAlign then
      lbl:setTextAlign(AlignCenter)
    end
    floorLabelPool[index] = lbl
  end
  return lbl
end

local function updateFloorMarkerLabels()
  local cbc = charConfig and charConfig.cavebot
  if not cbc or cbc.showWaypointsFloor == false or #activeFloorMarkerGroups == 0 then
    hideFloorLabels()
    return
  end
  local mapPanel = modules and modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not mapPanel or (mapPanel.isDestroyed and mapPanel:isDestroyed()) or not mapPanel:isVisible() then
    hideFloorLabels()
    return
  end

  local used = 0
  for _, g in ipairs(activeFloorMarkerGroups) do
    if mapPanel.isInRange and mapPanel:isInRange(g.pos) and mapPanel.getTileRect then
      local rect = mapPanel:getTileRect(g.pos)
      if rect and rect.width and rect.width > 4 and rect.height and rect.height > 4 then
        used = used + 1
        local lbl = getOrCreateFloorLabel(mapPanel, used)
        lbl:setColor(g.color)
        if lbl:getText() ~= g.text then
          lbl:setText(g.text)
        end
        local w = lbl:getWidth()
        local x = rect.x + math.floor(rect.width / 2) - math.floor(w / 2)
        local y = rect.y + rect.height + 1
        lbl:setPosition({ x = x, y = y })
        lbl:show()
      end
    end
  end

  for i = used + 1, #floorLabelPool do
    local lbl = floorLabelPool[i]
    if lbl and (not lbl.isDestroyed or not lbl:isDestroyed()) then
      lbl:hide()
    end
  end
end

function refreshFloorMarkers()
  clearFloorMarkers()
  local cbc = charConfig and charConfig.cavebot
  if not cbc or cbc.showWaypointsFloor == false then return end
  local player = g_game.getLocalPlayer()
  local pPos = player and player:getPosition()
  if not pPos then return end
  local effTemplate = ensureFloorWpEffect()
  local groups, order = {}, {}
  for idx, wpStr in ipairs(cbc.waypoints or {}) do
    local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and z == pPos.z and math.abs(x - pPos.x) <= 9 and math.abs(y - pPos.y) <= 7 then
      local key = x .. ',' .. y
      local wpType = wpStr:match('^([^:]+):') or 'WP'
      local g = groups[key]
      if not g then
        g = { pos = { x = x, y = y, z = z }, labels = {}, color = floorMarkerColor(wpType:lower()) }
        groups[key] = g
        order[#order + 1] = key
      end
      g.labels[#g.labels + 1] = idx .. ' ' .. wpType
    end
  end
  for _, key in ipairs(order) do
    local g = groups[key]
    local tile = g_map.getTile(g.pos)
    if tile then
      if effTemplate then
        if tile.attachEffect then
          pcall(function() tile:attachEffect(effTemplate:clone()) end)
        else
          local ground = tile.getGround and tile:getGround() or nil
          if ground and ground.attachEffect then
            pcall(function() ground:attachEffect(effTemplate:clone()) end)
          end
        end
      end
      if tile.setText then
        pcall(function() tile:setText('') end)
      end
      g.text = table.concat(g.labels, '\n')
      activeFloorMarkerGroups[#activeFloorMarkerGroups + 1] = g
      markedWorldTiles[#markedWorldTiles + 1] = g.pos
    end
  end
  updateFloorMarkerLabels()
end

function tickFloorMarkers(now)
  local cbc = charConfig and charConfig.cavebot
  if not cbc or cbc.showWaypointsFloor == false or #(cbc.waypoints or {}) == 0 then
    if #markedWorldTiles > 0 or #floorLabelPool > 0 then
      clearFloorMarkers()
    end
    return
  end
  if (now - lastFloorMarkAt) >= 600 then
    lastFloorMarkAt = now
    refreshFloorMarkers()
  elseif #activeFloorMarkerGroups > 0 then
    updateFloorMarkerLabels()
  end
end

function clearTemporaryWaypointMarkers()
  for _, entry in ipairs(minimapTempFlags) do
    if entry.map and entry.pos then
      pcall(function() entry.map:removeFlag(entry.pos, entry.icon, entry.desc) end)
    end
  end
  minimapTempFlags = {}
  clearFloorMarkers()
end

function renderCavebotWaypointsOnMaps()
  clearTemporaryWaypointMarkers()
  refreshFloorMarkers()
  local show = charConfig and charConfig.cavebot and (charConfig.cavebot.showWaypoints ~= false)
  if not show then return end

  local player = g_game.getLocalPlayer()
  local pPos = player and player:getPosition()
  local curZ = pPos and pPos.z or nil

  local cbMap = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  local wps = charConfig.cavebot.waypoints or {}

  for idx, wpStr in ipairs(wps) do
    local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
    if x and y and z then
      local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
      if not curZ or pos.z == curZ then
        local wpLower = wpStr:lower()
        local iconIdx = wpLower:find('lure') and 11 or (wpLower:find('rope') or wpLower:find('hole') or wpLower:find('ladder')) and 12 or 1
        local desc = string.format('#%d %s', idx, wpStr)
        if cbMap then
          pcall(function()
            cbMap:addFlag(pos, iconIdx, desc, true)
            table.insert(minimapTempFlags, { map = cbMap, pos = pos, icon = iconIdx, desc = desc })
          end)
        end
      end
    end
  end
end

function onToggleShowWaypointsFloor(checked)
  if not charConfig or not charConfig.cavebot then return end
  charConfig.cavebot.showWaypointsFloor = checked and true or false
  refreshFloorMarkers()
  saveCurrentProfile()
end

syncingWpMode = false
function syncCavebotWpModeUI()
  local box = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  if not box then return end
  local mode = (charConfig and charConfig.cavebot and charConfig.cavebot.wpMode) or 'Add'
  syncingWpMode = true
  for _, name in ipairs({ 'Add', 'Insert', 'Replace' }) do
    local w = box:getChildById('wpMode' .. name)
    if w then w:setChecked(name == mode) end
  end
  syncingWpMode = false
end

function setCavebotWpMode(mode, checked)
  if syncingWpMode then return end
  if not charConfig or not charConfig.cavebot then return end
  if not checked then
    -- funciona como radio: nao deixa desmarcar o modo atual
    if (charConfig.cavebot.wpMode or 'Add') == mode then syncCavebotWpModeUI() end
    return
  end
  charConfig.cavebot.wpMode = mode
  syncCavebotWpModeUI()
  saveCurrentProfile()
end

function onToggleShowWaypoints(checked)
  charConfig.cavebot.showWaypoints = checked
  renderCavebotWaypointsOnMaps()
  saveCurrentProfile()
end

function centerCavebotMinimap()
  local player = g_game.getLocalPlayer()
  local cbMap = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  if cbMap and player and player:getPosition() then
    cbMap:setCameraPosition(player:getPosition())
    cbMap:setCrossPosition(player:getPosition())
  end
end

function zoomCavebotMinimap(delta)
  local cbMap = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  if cbMap then
    if delta > 0 then cbMap:zoomIn() else cbMap:zoomOut() end
  end
end

function isCavebotAutoRecActive()
  return cavebotAutoRec
end

function setCavebotDirOffset(dir)
  cavebotDirOffset = dir or 'C'
  local dirs = { 'NW', 'N', 'NE', 'W', 'C', 'E', 'SW', 'S', 'SE' }
  local cbBox = panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cbActionToolsBox'):getChildById('dirGridPanel')
  local hudGrid = cbControlMiniHud and cbControlMiniHud:getChildById('hudGridRow')
  for _, d in ipairs(dirs) do
    local isSel = (d == cavebotDirOffset)
    local b1 = cbBox and cbBox:getChildById('dir' .. d)
    if b1 then
      b1:setOn(isSel)
      b1:setColor(isSel and '#ffffff' or '#dfdfdf')
    end
    local b2 = hudGrid and hudGrid:getChildById('h' .. d)
    if b2 then b2:setColor(isSel and '#5ce65c' or '#dfdfdf') end
  end
end

function getWaypointPos(wpStr)
  if not wpStr then return nil end
  local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
  if x and y and z then
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
  end
  return nil
end

function onToggleCavebotAutoRec(checked)
  cavebotAutoRec = checked and true or false
  if cavebotAutoRec then
    if charConfig and charConfig.cavebot and charConfig.cavebot.enabled then
      charConfig.cavebot.enabled = false
      local player = g_game.getLocalPlayer()
      if player and player.stopAutoWalk and player:isAutoWalking() then
        player:stopAutoWalk()
      end
      local topBox0 = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox')
      local cbEnChk = topBox0 and topBox0:getChildById('enableCavebotCheck')
      if cbEnChk and cbEnChk:isChecked() then
        cbEnChk:setChecked(false)
      end
      updateStatsUI()
      refreshCavebotUI()
      saveCurrentProfile()
    end
    local wps = charConfig and charConfig.cavebot and charConfig.cavebot.waypoints or {}
    local lastPos = (#wps > 0) and getWaypointPos(wps[#wps]) or nil
    local pPos = g_game.getLocalPlayer() and g_game.getLocalPlayer():getPosition() or nil
    if lastPos and pPos and lastPos.z == pPos.z then
      lastAutoRecPos = lastPos
    else
      lastAutoRecPos = nil
    end
  else
    lastAutoRecPos = nil
  end
  local topBox = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox')
  local chk = topBox and topBox:getChildById('autoRecCheck')
  if chk and chk:isChecked() ~= cavebotAutoRec then
    chk:setChecked(cavebotAutoRec)
  end
  if cbControlMiniHud then
    local hBtn = cbControlMiniHud:getChildById('hudAutoRecBtn')
    if hBtn then
      hBtn:setText(ht('Auto Rec: ') .. (cavebotAutoRec and 'ON' or 'OFF'))
      hBtn:setColor(cavebotAutoRec and '#22ee22' or '#ff6666')
    end
  end
end

function toggleCbControlHud(forceState)
  if not cbControlMiniHud then return end
  local target = (forceState ~= nil) and forceState or (not cbControlMiniHud:isVisible())
  if target then
    cbControlMiniHud:show()
    cbControlMiniHud:raise()
  else
    cbControlMiniHud:hide()
  end
end

DIR_OFFSETS = {
  NW = { -1, -1 }, N = { 0, -1 }, NE = { 1, -1 },
  W  = { -1,  0 }, C = { 0,  0 }, E  = { 1,  0 },
  SW = { -1,  1 }, S = { 0,  1 }, SE = { 1,  1 }
}

function refreshCavebotUI(scrollToBottom)
  syncCavebotWpModeUI()
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local cbRow = cBody:getChildById('cbListRow')
  local list = cbRow:getChildById('cavebotWpList')
  local wpScroll = cbRow:getChildById('wpScrollBar')
  local wasAtBottom = true
  if wpScroll and wpScroll.getValue and wpScroll.getMaximum then
    local maxV = wpScroll:getMaximum()
    if maxV > 0 and wpScroll:getValue() < (maxV - 25) then
      wasAtBottom = false
    end
  end
  local actionBox = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  local statusLbl = actionBox:getChildById('cavebotStatusLabel')
  list:destroyChildren()

  local wps = charConfig.cavebot.waypoints or {}
  local curIdx = charConfig.cavebot.currentWpIndex or 1
  if #wps == 0 then
    selectedCavebotWpIdx = nil
  elseif not selectedCavebotWpIdx or selectedCavebotWpIdx > #wps then
    selectedCavebotWpIdx = math.min(curIdx, #wps)
  end

  for idx, wpStr in ipairs(wps) do
    local row = g_ui.createWidget('CavebotWpRow', list)
    local wpType, wpBody = wpStr:match('^([^:]+):%s*(.+)$')
    if not wpType then
      wpType = 'Action'
      wpBody = wpStr
    end
    row:getChildById('wpIndexLabel'):setText(tostring(idx))
    row:getChildById('wpTypeLabel'):setText(wpType)
    row:getChildById('wpPosLabel'):setText(wpBody)
    if idx == curIdx and charConfig.cavebot.enabled then
      row:setBackgroundColor('#2e4a2e')
    end
    row.wpIdx = idx
    row.onClick = function(w)
      selectedCavebotWpIdx = w.wpIdx
      list:focusChild(w, MouseFocusReason)
      if charConfig.cavebot.enabled then
        local dest = getWaypointPos(wps[w.wpIdx])
        local player = g_game.getLocalPlayer()
        local pPos = player and player:getPosition() or nil
        if dest and pPos and dest.z == pPos.z and getDistanceBetween(pPos, dest) <= 25 then
          charConfig.cavebot.currentWpIndex = w.wpIdx
          if player.stopAutoWalk and player:isAutoWalking() then
            player:stopAutoWalk()
          end
          player:autoWalk(dest)
          refreshCavebotUI()
        end
      end
    end
    row.onDoubleClick = function(w)
      selectedCavebotWpIdx = w.wpIdx
      charConfig.cavebot.currentWpIndex = w.wpIdx
      refreshCavebotUI()
    end
    if idx == selectedCavebotWpIdx then
      list:focusChild(row, KeyboardFocusReason)
    end
  end

  local stText = charConfig.cavebot.enabled and htf('Running WP #%d/%d', curIdx, #wps) or htf('Idle (%d WPs)', #wps)
  if cbPauseState then stText = stText .. ht(' [Luring/Paused]') end
  statusLbl:setText(ht('Status: ') .. stText)
  if (scrollToBottom or wasAtBottom) and wpScroll and wpScroll.setValue and wpScroll.getMaximum then
    addEvent(function()
      if wpScroll and wpScroll.getMaximum then
        wpScroll:setValue(wpScroll:getMaximum())
      end
    end)
  end
  renderCavebotWaypointsOnMaps()
  installClickOutsideUnfocus(list)
end

function cavebotAdvanceUI()
  local cb = charConfig.cavebot
  local player = g_game.getLocalPlayer()
  local pPos = player and player:getPosition()
  if pPos and helperLastRenderZ ~= pPos.z then
    helperLastRenderZ = pPos.z
    renderCavebotWaypointsOnMaps()  -- minimapa só redesenha quando muda de andar
  end
  if not (helperWindow and helperWindow:isVisible() and panels.cavebot and panels.cavebot:isVisible()) then return end
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local list = cBody:getChildById('cbListRow'):getChildById('cavebotWpList')
  local curIdx = cb.currentWpIndex or 1
  for _, row in ipairs(list:getChildren()) do
    row:setBackgroundColor((row.wpIdx == curIdx and cb.enabled) and '#2e4a2e' or '#363636')
  end
  local statusLbl = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox'):getChildById('cavebotStatusLabel')
  local wps = cb.waypoints or {}
  local stText = cb.enabled and htf('Running WP #%d/%d', curIdx, #wps) or htf('Idle (%d WPs)', #wps)
  if cbPauseState then stText = stText .. ht(' [Luring/Paused]') end
  statusLbl:setText(ht('Status: ') .. stText)
end

function selectNearestCavebotWaypoint()
  local player = g_game.getLocalPlayer()
  local wps = charConfig.cavebot.waypoints or {}
  if not player or #wps == 0 then return end
  local pPos = player:getPosition()
  local bestIdx = 1
  local bestDist = 99999
  for idx, wpStr in ipairs(wps) do
    local pos = getWaypointPos(wpStr)
    local lowWp = wpStr:lower()
    if pos and pos.z == pPos.z and not lowWp:find('^start lure') and not lowWp:find('^end lure') then
      local d = math.max(math.abs(pPos.x - pos.x), math.abs(pPos.y - pos.y))
      if d < bestDist then
        bestDist = d
        bestIdx = idx
      end
    end
  end
  charConfig.cavebot.currentWpIndex = bestIdx
  selectedCavebotWpIdx = bestIdx
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] Start nearest -> WP #' .. bestIdx)
  end
  refreshCavebotUI()
end

function addCavebotWaypoint(wpType)
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pPos = player:getPosition()
  local off = DIR_OFFSETS[cavebotDirOffset] or { 0, 0 }
  local x, y, z = pPos.x + off[1], pPos.y + off[2], pPos.z
  local entries
  if wpType == 'Box' then
    entries = {
      string.format('End Lure: %d, %d, %d', x, y, z),
      string.format('Stand: %d, %d, %d', x, y, z),
      string.format('Start Lure: %d, %d, %d', x, y, z)
    }
  else
    entries = { string.format('%s: %d, %d, %d', wpType, x, y, z) }
  end
  local wps = charConfig.cavebot.waypoints
  local mode = charConfig.cavebot.wpMode or 'Add'
  local sel = selectedCavebotWpIdx
  local scroll = true
  if mode == 'Insert' and sel and wps[sel] then
    -- entra ANTES do selecionado; a selecao continua no waypoint original (inserts seguidos ficam em ordem)
    for i, entry in ipairs(entries) do
      table.insert(wps, sel + i - 1, entry)
    end
    local cur = charConfig.cavebot.currentWpIndex or 1
    if cur >= sel then charConfig.cavebot.currentWpIndex = cur + #entries end
    selectedCavebotWpIdx = sel + #entries
    scroll = false
  elseif mode == 'Replace' and sel and wps[sel] then
    wps[sel] = entries[1]
    for i = 2, #entries do
      table.insert(wps, sel + i - 1, entries[i])
    end
    local cur = charConfig.cavebot.currentWpIndex or 1
    if #entries > 1 and cur > sel then
      charConfig.cavebot.currentWpIndex = cur + (#entries - 1)
    end
    scroll = false
  else
    for _, entry in ipairs(entries) do
      table.insert(wps, entry)
    end
    selectedCavebotWpIdx = #wps
  end
  setCavebotDirOffset('C')
  refreshCavebotUI(scroll)
  saveCurrentProfile()
end

function undoCavebotWaypoint()
  local wps = charConfig.cavebot.waypoints
  if #wps > 0 then
    table.remove(wps)
    selectedCavebotWpIdx = (#wps > 0) and #wps or nil
    if (charConfig.cavebot.currentWpIndex or 1) > #wps then
      charConfig.cavebot.currentWpIndex = math.max(1, #wps)
    end
    lastAutoRecPos = (#wps > 0) and getWaypointPos(wps[#wps]) or nil
    refreshCavebotUI()
    saveCurrentProfile()
  end
end

function moveCavebotWaypoint(delta)
  local wps = charConfig.cavebot.waypoints
  local idx = selectedCavebotWpIdx
  if not idx or not wps[idx] then return end
  local tgt = idx + delta
  if tgt >= 1 and tgt <= #wps then
    wps[idx], wps[tgt] = wps[tgt], wps[idx]
    selectedCavebotWpIdx = tgt
    refreshCavebotUI()
    saveCurrentProfile()
  end
end

function deleteSelectedCavebotWaypoint()
  local wps = charConfig.cavebot.waypoints
  local idx = selectedCavebotWpIdx
  if (not idx or not wps[idx]) and #wps > 0 then
    idx = #wps
  end
  if not idx or not wps[idx] then return end
  table.remove(wps, idx)
  if #wps == 0 then
    selectedCavebotWpIdx = nil
    charConfig.cavebot.currentWpIndex = 1
    lastAutoRecPos = nil
  else
    selectedCavebotWpIdx = math.min(idx, #wps)
    charConfig.cavebot.currentWpIndex = math.min(charConfig.cavebot.currentWpIndex or 1, #wps)
    lastAutoRecPos = getWaypointPos(wps[#wps])
  end
  refreshCavebotUI()
  saveCurrentProfile()
end

function clearCavebotWaypoints()
  charConfig.cavebot.waypoints = {}
  charConfig.cavebot.currentWpIndex = 1
  selectedCavebotWpIdx = nil
  refreshCavebotUI()
  saveCurrentProfile()
end

function getCavebotDiskDir()
  local base = g_resources.getWorkDir and g_resources.getWorkDir() or ''
  if base ~= '' then
    return base .. 'mods/game_helper/cavebots'
  end
  return 'mods/game_helper/cavebots'
end

function saveCavebotWaypoints()
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local huntEdit = cBody:getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit')
  local rawName = huntEdit and huntEdit:getText() or ''
  local cleanName = rawName:gsub('[^%w%-%_%s]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', '_')
  if cleanName == '' then
    cleanName = 'hunt_' .. os.date('%H%M%S')
  end
  charConfig.cavebot.huntName = cleanName
  if huntEdit then huntEdit:setText(cleanName) end
  saveCurrentProfile()

  local savedFile = false
  local diskDir = getCavebotDiskDir()
  if io and io.open then
    local f = io.open(diskDir .. '/' .. cleanName .. '.txt', 'w')
    if f then
      for _, wp in ipairs(charConfig.cavebot.waypoints or {}) do
        f:write(wp .. '\n')
      end
      f:close()
      savedFile = true
    end
  end
  if modules.game_textmessage then
    if savedFile then
      modules.game_textmessage.displayStatusMessage(string.format('[DAVCaster] Saved hunt "%s.txt" (%d WPs).', cleanName, #charConfig.cavebot.waypoints))
    else
      modules.game_textmessage.displayStatusMessage(string.format('[DAVCaster] Saved %d WPs to profile "%s".', #charConfig.cavebot.waypoints, cleanName))
    end
  end
end

selectedHuntFile = nil

function openHuntList()
  if not huntListModal then return end
  local list = huntListModal:getChildById('huntsList')
  list:destroyChildren()
  selectedHuntFile = nil
  local dir = '/mods/game_helper/cavebots'
  if g_resources.directoryExists(dir) then
    local files = g_resources.listDirectoryFiles(dir) or {}
    table.sort(files)
    for _, fname in ipairs(files) do
      if fname:match('%.txt$') or fname:match('%.json$') or fname:match('%.cb$') then
        local row = g_ui.createWidget('HuntListRow', list)
        row:getChildById('huntNameLabel'):setText(fname)
        row.fname = fname
        row.onClick = function(w)
          selectedHuntFile = w.fname
          list:focusChild(w, MouseFocusReason)
        end
        row.onDoubleClick = function(w)
          selectedHuntFile = w.fname
          confirmLoadHunt()
        end
      end
    end
  end
  huntListModal:show()
  huntListModal:raise()
  huntListModal:focus()
end

function confirmLoadHunt()
  if not selectedHuntFile then return end
  local dir = '/mods/game_helper/cavebots'
  local raw = g_resources.readFileContents(dir .. '/' .. selectedHuntFile)
  if raw and #raw > 0 then
    local loaded = {}
    for line in raw:gmatch('[^\r\n]+') do
      line = line:gsub('^%s+', ''):gsub('%s+$', '')
      if line ~= '' and line:match('%d+,%s*%d+,%s*%d+') then
        table.insert(loaded, line)
      end
    end
    if #loaded > 0 then
      charConfig.cavebot.waypoints = loaded
      charConfig.cavebot.currentWpIndex = 1
      charConfig.cavebot.huntName = selectedHuntFile:gsub('%.[^%.]+$', '')
      local huntEdit = panels.cavebot:getChildById('bodyPanel'):getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit')
      if huntEdit then huntEdit:setText(charConfig.cavebot.huntName) end
      refreshCavebotUI()
      saveCurrentProfile()
      if modules.game_textmessage then
        modules.game_textmessage.displayStatusMessage('[DAVCaster] Loaded ' .. #loaded .. ' WPs from ' .. selectedHuntFile)
      end
      huntListModal:hide()
      return
    end
  end
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] Could not find coordinates in ' .. selectedHuntFile)
  end
end

function loadCavebotWaypoints()
  openHuntList()
end

function syncCavebotSpeedEditState()
  if not panels.cavebot or not charConfig or not charConfig.cavebot then return end
  local cbS = charConfig.cavebot.settings or {}
  local isDyn = (cbS.dynamicLure ~= false)
  local ed = panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox'):getChildById('cbWalkSpeedEdit')
  if not ed then return end
  if ed.setEditable then ed:setEditable(not isDyn) end
  if ed.setFocusable then ed:setFocusable(not isDyn) end
  if ed.setEnabled then ed:setEnabled(not isDyn) end
  ed:setColor(isDyn and '#888888' or '#efefef')
  if isDyn and ed:isFocused() then
    unfocusActiveHelperTextEdit(nil)
  elseif not isDyn then
    helperSpeedUiLock = true
    ed:setText(tostring(cbS.walkSpeedPct or 100), true)
    helperSpeedUiLock = false
  end
end

function openCavebotSettingsModal()
  local s = charConfig.cavebot.settings
  local ls = s.lureSpeeds or {}
  local isGlobal = (s.lureMode == 'global')
  local boxChk = cavebotSettingsModal:getChildById('cbLureBoxModeCheck')
  local glbChk = cavebotSettingsModal:getChildById('cbLureGlobalModeCheck')
  if boxChk and glbChk then
    boxChk.onCheckChange = nil
    glbChk.onCheckChange = nil
    boxChk:setChecked(not isGlobal)
    glbChk:setChecked(isGlobal)
    boxChk.onCheckChange = function(w, ch)
      if ch and glbChk:isChecked() then glbChk:setChecked(false)
      elseif not ch and not glbChk:isChecked() then boxChk:setChecked(true) end
      s.lureMode = glbChk:isChecked() and 'global' or 'box'
      saveCurrentProfile()
    end
    glbChk.onCheckChange = function(w, ch)
      if ch and boxChk:isChecked() then boxChk:setChecked(false)
      elseif not ch and not boxChk:isChecked() then glbChk:setChecked(true) end
      s.lureMode = glbChk:isChecked() and 'global' or 'box'
      saveCurrentProfile()
    end
  end
  local stopEd = cavebotSettingsModal:getChildById('cbStopMonstersEdit')
  local walkEd = cavebotSettingsModal:getChildById('cbWalkMonstersEdit')
  local dynChk = cavebotSettingsModal:getChildById('cbDynamicLureCheck')
  stopEd.onTextChange = nil
  walkEd.onTextChange = nil
  dynChk.onCheckChange = nil
  stopEd:setText(tostring(s.stopMonsters or 3))
  walkEd:setText(tostring(s.walkMonsters or 1))
  dynChk:setChecked(s.dynamicLure ~= false)
  dynChk.onCheckChange = function(w, ch)
    s.dynamicLure = ch and true or false
    syncCavebotSpeedEditState()
    saveCurrentProfile()
  end
  local grid = cavebotSettingsModal:getChildById('cbLureGrid')
  if grid then
    for i = 0, 5 do
      local e = grid:getChildById('cbLure' .. i)
      if e then
        e.onTextChange = nil
        e:setText(tostring(ls[i] ~= nil and ls[i] or 100))
        e.onTextChange = function(w, txt)
          if helperSpeedUiLock then return end
          local n = tonumber(txt)
          if n then
            local clamped = math.max(0, math.min(100, math.floor(n)))
            if clamped ~= n then
              helperSpeedUiLock = true
              w:setText(tostring(clamped), true)
              helperSpeedUiLock = false
            end
            s.lureSpeeds = s.lureSpeeds or {}
            s.lureSpeeds[i] = clamped
            saveCurrentProfile()
          end
        end
      end
    end
  end
  stopEd.onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then s.stopMonsters = math.max(1, math.min(20, math.floor(n))) saveCurrentProfile() end
  end
  walkEd.onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then s.walkMonsters = math.max(0, math.min(20, math.floor(n))) saveCurrentProfile() end
  end
  cavebotSettingsModal:show()
  cavebotSettingsModal:raise()
  cavebotSettingsModal:focus()
end

function saveCavebotSettingsModal()
  local s = charConfig.cavebot.settings
  s.stopMonsters = parseNum(cavebotSettingsModal:getChildById('cbStopMonstersEdit'), 3, 1, 20)
  s.walkMonsters = parseNum(cavebotSettingsModal:getChildById('cbWalkMonstersEdit'), 1, 0, 20)
  local glbChk = cavebotSettingsModal:getChildById('cbLureGlobalModeCheck')
  s.lureMode = (glbChk and glbChk:isChecked()) and 'global' or 'box'
  s.dynamicLure = cavebotSettingsModal:getChildById('cbDynamicLureCheck'):isChecked()
  local lureGrid = cavebotSettingsModal:getChildById('cbLureGrid')
  if lureGrid then
    s.lureSpeeds = s.lureSpeeds or {}
    for i = 0, 5 do
      local e = lureGrid:getChildById('cbLure' .. i)
      if e then s.lureSpeeds[i] = parseNum(e, s.lureSpeeds[i] or 100, 0, 100) end
    end
  end
  syncCavebotSpeedEditState()
  cavebotSettingsModal:hide()
  saveCurrentProfile()
end

-- ============================================================================

function loadCavebotUI()
  local cBody = panels.cavebot and panels.cavebot:getChildById('bodyPanel')
  if not cBody then return end
  local cbTop = cBody:getChildById('cbTopControlsBox')
  cbTop:getChildById('enableCavebotCheck'):setChecked(charConfig.cavebot.enabled == true)
  cbTop:getChildById('autoRecDistEdit'):setText(tostring(charConfig.cavebot.autoRecDist or 3))
  cbTop:getChildById('cbWalkSpeedEdit'):setText(tostring((charConfig.cavebot.settings and charConfig.cavebot.settings.walkSpeedPct) ~= nil and charConfig.cavebot.settings.walkSpeedPct or 100))
  cbTop:getChildById('startNearestCheck'):setChecked(charConfig.cavebot.startNearest ~= false)
  cbTop:getChildById('showWaypointsCheck'):setChecked(charConfig.cavebot.showWaypoints ~= false)
  local floorChk = cbTop:getChildById('showFloorWpCheck')
  if floorChk then floorChk:setChecked(charConfig.cavebot.showWaypointsFloor ~= false) end
  local ignUnreachChk = cbTop:getChildById('ignoreUnreachableCheck')
  if ignUnreachChk then ignUnreachChk:setChecked(charConfig.cavebot.ignoreUnreachable ~= false) end
  if cbTop:getChildById('antiTrapCheck') then
    cbTop:getChildById('antiTrapCheck'):setChecked(charConfig.cavebot.antiTrap == true)
  end
  syncCavebotSpeedEditState()
  local huntEdit = cBody:getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit')
  if huntEdit then huntEdit:setText(charConfig.cavebot.huntName or '') end
  local cbAct = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  renderItemSlot(cbAct:getChildById('ropeSlot'), charConfig.cavebot.ropeId)
  renderItemSlot(cbAct:getChildById('shovelSlot'), charConfig.cavebot.shovelId)
  setCavebotDirOffset('C')
  refreshCavebotUI()
end

function setupCavebotCallbacks()
  -- Cavebot Tab Wiring
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local cbTop = cBody:getChildById('cbTopControlsBox')
  cbTop:getChildById('enableCavebotCheck').onCheckChange = function(w, ch)
    charConfig.cavebot.enabled = ch
    if ch then
      if cavebotAutoRec then
        cavebotAutoRec = false
        cbTop:getChildById('autoRecCheck'):setChecked(false)
      end
      if charConfig.cavebot.startNearest then
        selectNearestCavebotWaypoint()
      end
    end
    updateStatsUI()
    refreshCavebotUI()
    saveCurrentProfile()
  end
  local distEdit = cbTop:getChildById('autoRecDistEdit')
  distEdit.onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then charConfig.cavebot.autoRecDist = math.max(1, math.min(15, math.floor(n))) saveCurrentProfile() end
  end
  local function releaseDistFocus()
    local rootPanel = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if rootPanel then rootPanel:focus() end
  end
  local moveKeys = {}
  for _, kn in ipairs({ 'KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyUp', 'KeyDown', 'KeyLeft', 'KeyRight', 'KeyQ', 'KeyE', 'KeyZ', 'KeyC' }) do
    local kc = rawget(_G, kn)
    if kc then moveKeys[kc] = true end
  end
  distEdit.onKeyDown = function(w, keyCode, mods)
    if moveKeys[keyCode] then releaseDistFocus() end
    return false
  end
  panels.cavebot.onMousePress = function(w, mousePos, button)
    if distEdit:isFocused() and not distEdit:containsPoint(mousePos) then releaseDistFocus() end
    return false
  end
  distEdit.onFocusChange = nil
  cbTop:getChildById('cbWalkSpeedEdit').onTextChange = function(w, txt)
    if helperSpeedUiLock then return end
    local n = tonumber(txt)
    if n and charConfig.cavebot and charConfig.cavebot.settings then
      local clamped = math.max(0, math.min(100, math.floor(n)))
      if clamped ~= n then
        helperSpeedUiLock = true
        w:setText(tostring(clamped), true)
        helperSpeedUiLock = false
      end
      charConfig.cavebot.settings.walkSpeedPct = clamped
      saveCurrentProfile()
    end
  end
  local ignUnreachChk = cbTop:getChildById('ignoreUnreachableCheck')
  if ignUnreachChk then
    ignUnreachChk.onCheckChange = function(w, ch)
      if isLoadingUI then return end
      charConfig.cavebot.ignoreUnreachable = (ch == true)
      saveCurrentProfile()
    end
  end
  local antiTrapChk = cbTop:getChildById('antiTrapCheck')
  if antiTrapChk then
    antiTrapChk.onCheckChange = function(w, ch)
      if isLoadingUI then return end
      charConfig.cavebot.antiTrap = (ch == true)
      saveCurrentProfile()
    end
  end
  cbTop:getChildById('startNearestCheck').onCheckChange = function(w, ch)
    charConfig.cavebot.startNearest = ch
    saveCurrentProfile()
  end
  cBody:getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit').onTextChange = function(w, txt)
    charConfig.cavebot.huntName = txt
  end

  local cbAct = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  local rSlot = cbAct:getChildById('ropeSlot')
  bindSlotClicks(rSlot, function()
    openItemSelector('Select Rope Item', 'tool', charConfig.cavebot.ropeId, function(it)
      charConfig.cavebot.ropeId = it.id
      renderItemSlot(rSlot, it.id)
    end)
  end, function()
    charConfig.cavebot.ropeId = 3003
    renderItemSlot(rSlot, 3003)
  end)
  attachItemDropHandler(rSlot, function(id) charConfig.cavebot.ropeId = id renderItemSlot(rSlot, id) end)

  local shSlot = cbAct:getChildById('shovelSlot')
  bindSlotClicks(shSlot, function()
    openItemSelector('Select Shovel Item', 'tool', charConfig.cavebot.shovelId, function(it)
      charConfig.cavebot.shovelId = it.id
      renderItemSlot(shSlot, it.id)
    end)
  end, function()
    charConfig.cavebot.shovelId = 5710
    renderItemSlot(shSlot, 5710)
  end)
  attachItemDropHandler(shSlot, function(id) charConfig.cavebot.shovelId = id renderItemSlot(shSlot, id) end)

  -- Hide built-in mini buttons inside cavebotMinimap cleanly
  local cbMap = cBody:getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  if cbMap then
    for _, cid in ipairs({'floorUpButton', 'floorDownButton', 'zoomInButton', 'zoomOutButton', 'resetButton'}) do
      local c = cbMap:getChildById(cid)
      if c then c:hide() end
    end
  end

  -- Helper Language Combos (Bottom bar + Settings tab, synced per character)
end

function runCavebotAutoRec(player, pPos, now)
  -- Keep Cavebot Minimap centered & run AutoRec (configurable SQM + Stand on stairs/teleport + immediate Node)
  if helperWindow and helperWindow:isVisible() and panels and panels.cavebot and panels.cavebot:isVisible() then
    centerCavebotMinimap()
  end
  if cavebotAutoRec and pPos then
    local recDist = math.max(1, tonumber(charConfig.cavebot.autoRecDist) or 3)
    local wps = charConfig.cavebot.waypoints
    local lastWpPos = (#wps > 0) and getWaypointPos(wps[#wps]) or nil
    if lastAutoRecPos and (lastAutoRecPos.z ~= pPos.z or getDistanceBetween(lastAutoRecPos, pPos) >= 8) then
      local standPos = (lastAutoRecPos.z ~= pPos.z) and resolveFloorChangeStandPos(lastAutoRecPos, pPos) or lastAutoRecPos
      if not lastWpPos or lastWpPos.x ~= standPos.x or lastWpPos.y ~= standPos.y or lastWpPos.z ~= standPos.z then
        table.insert(wps, string.format('Stand: %d, %d, %d', standPos.x, standPos.y, standPos.z))
      end
      table.insert(wps, string.format('Node: %d, %d, %d', pPos.x, pPos.y, pPos.z))
      lastAutoRecPos = { x = pPos.x, y = pPos.y, z = pPos.z }
      selectedCavebotWpIdx = #wps
      refreshCavebotUI(true)
      saveCurrentProfileThrottled()
    elseif not lastAutoRecPos or getDistanceBetween(lastAutoRecPos, pPos) >= recDist then
      if not lastWpPos or lastWpPos.x ~= pPos.x or lastWpPos.y ~= pPos.y or lastWpPos.z ~= pPos.z then
        table.insert(wps, string.format('Node: %d, %d, %d', pPos.x, pPos.y, pPos.z))
        selectedCavebotWpIdx = #wps
        refreshCavebotUI(true)
        saveCurrentProfileThrottled()
      end
      lastAutoRecPos = { x = pPos.x, y = pPos.y, z = pPos.z }
    end
  end

  tickFloorMarkers(now)
end

local ANTI_TRAP_DIRS = {
  { x = 0, y = -1, dir = North },
  { x = 1, y = 0, dir = East },
  { x = 0, y = 1, dir = South },
  { x = -1, y = 0, dir = West },
  { x = 1, y = -1, dir = NorthEast },
  { x = 1, y = 1, dir = SouthEast },
  { x = -1, y = 1, dir = SouthWest },
  { x = -1, y = -1, dir = NorthWest }
}

function runCavebotTick(player, pPos, now, nearbyMonsters)
  -- 4. CAVEBOT ENGINE (OTClient-native Percentage Speed + Dynamic Lure + Stand vs Node)
  local okCb, errCb = pcall(function()
  if charConfig.cavebot.antiTrap == true and not player:hasState(PlayerStates.Pz) and (now - lastAntiTrapTime) >= 500 then
    local freeDir, freeCount = nil, 0
    for _, d in ipairs(ANTI_TRAP_DIRS) do
      local tp = { x = pPos.x + d.x, y = pPos.y + d.y, z = pPos.z }
      local tile = g_map.getTile(tp)
      if tile and tile:isWalkable(false) and not tile:hasFloorChange() then
        freeCount = freeCount + 1
        freeDir = d.dir
      end
    end
    if freeDir and freeCount >= 1 and freeCount <= 2 then
      g_game.walk(freeDir)
      lastAntiTrapTime = now
      return
    end
  end
  if charConfig.cavebot.enabled then
    local lastManual = (modules.game_interface and tonumber(modules.game_interface.lastManualWalk)) or 0
    local manualGrace = math.max(420, ((player.getStepDuration and player:getStepDuration()) or 200) + 180)
    local isManualKeyHeld = false
    if g_keyboard and g_keyboard.isKeyPressed and not isTypingInTextEdit() then
      for _, kCode in ipairs({ KeyUp, KeyDown, KeyLeft, KeyRight }) do
        if kCode and g_keyboard.isKeyPressed(kCode) then
          isManualKeyHeld = true
          break
        end
      end
    end
    if isManualKeyHeld or (now - lastManual) < manualGrace then
      lastCavebotStepTime = now
      return
    end

    local cb = charConfig.cavebot
    local cbS = cb.settings or {}
    local cbMonsters = nearbyMonsters
    if cb.ignoreUnreachable ~= false and #nearbyMonsters > 0 then
      cbMonsters = {}
      for _, m in ipairs(nearbyMonsters) do
        if isMonsterReachable(pPos, m.creature, now) then
          cbMonsters[#cbMonsters + 1] = m
        end
      end
    end
    local mobIdx = math.min(5, #cbMonsters)
    local activeSpeed = (cbS.dynamicLure ~= false and cbS.lureSpeeds and tonumber(cbS.lureSpeeds[mobIdx]))
      or tonumber(cbS.walkSpeedPct)
      or 100
    activeSpeed = math.max(0, math.min(100, math.floor(activeSpeed)))
    if cbS.dynamicLure ~= false and panels.cavebot then
      local bp = panels.cavebot:getChildById('bodyPanel')
      local tb = bp and bp:getChildById('cbTopControlsBox')
      local speedEd = tb and tb:getChildById('cbWalkSpeedEdit')
      if speedEd and speedEd:getText() ~= tostring(activeSpeed) then
        helperSpeedUiLock = true
        speedEd:setText(tostring(activeSpeed), true)
        helperSpeedUiLock = false
      end
    end
    local stepDelayMs = (activeSpeed >= 100) and 0 or math.max(120, math.floor(100 + (100 - activeSpeed) * 4.5))

    if activeSpeed <= 0 then
      if player:isAutoWalking() then
        player:stopAutoWalk()
      end
      lastCavebotStepTime = now
    else
      local stopCount = tonumber(cbS.stopMonsters) or 3
      local resumeCount = tonumber(cbS.walkMonsters) or 1
      local isGlobalLure = (cbS.lureMode == 'global')
      if resumeCount >= stopCount then
        resumeCount = math.max(0, stopCount - 1)
      end
      local wps = cb.waypoints or {}
      local idx = cb.currentWpIndex or 1
      if idx > #wps or idx < 1 then idx = 1 end
      local wpStr = wps[idx] or ''
      local wpLower = wpStr:lower()
      local wasPaused = cbPauseState

      local function advancePastSameBoxCoord()
        if #wps == 0 then return end
        local curPos = getWaypointPos(wps[cb.currentWpIndex or 1])
        local guard = 0
        repeat
          cb.currentWpIndex = ((cb.currentWpIndex or 1) % #wps) + 1
          guard = guard + 1
          local nxtStr = wps[cb.currentWpIndex] or ''
          local nxtLow = nxtStr:lower()
          local nxtPos = getWaypointPos(nxtStr)
          local sameCoord = curPos and nxtPos and curPos.x == nxtPos.x and curPos.y == nxtPos.y and curPos.z == nxtPos.z
          local isBoxType = (not nxtLow:find('^node')) and (not nxtLow:find('^rope')) and (not nxtLow:find('^hole'))
            and (not nxtLow:find('^shovel')) and (not nxtLow:find('^ladder')) and (not nxtLow:find('^use'))
          if not (sameCoord and isBoxType) then break end
        until guard >= #wps
      end

      if isGlobalLure then
        if #wps > 0 and (wpLower:find('^start lure') or wpLower:find('^end lure')) then
          cb.currentWpIndex = (idx % #wps) + 1
          idx = cb.currentWpIndex
          wpStr = wps[idx] or ''
          wpLower = wpStr:lower()
          cavebotAdvanceUI()
        end
        if #cbMonsters >= stopCount then
          cbPauseState = true
        elseif #cbMonsters <= resumeCount then
          cbPauseState = false
        end
      else
        -- BOX LURE: só segura em waypoint de lure/stand (não-Node); solta e avança na hora quando limpar
        if cbPauseState and #cbMonsters <= resumeCount then
          cbPauseState = false
          advancePastSameBoxCoord()
          cavebotAdvanceUI()
        end
        if wpLower:find('^node') then cbPauseState = false end
      end

      if cbPauseState and not wasPaused then
        if player:isAutoWalking() then player:stopAutoWalk() end
        cavebotAdvanceUI()
      end

      if not cbPauseState and #wps > 0 then
        local function walkToCoord(destPos, forceFallbackDir)
          if activeSpeed < 100 then
            if player:isAutoWalking() then
              player:stopAutoWalk()
            end
            if (now - lastCavebotStepTime) >= stepDelayMs then
              if getDistanceBetween(pPos, destPos) == 1 then
                local dir = getDirectionFromPos(pPos, destPos)
                if dir then g_game.walk(dir) end
              else
                local path = g_map.findPath(pPos, destPos, 5000, 0)
                if path and #path > 0 then
                  g_game.walk(path[1])
                end
              end
              lastCavebotStepTime = now
            end
          elseif not player:isAutoWalking() then
            local ok = player:autoWalk(destPos)
            if not ok then
              if forceFallbackDir and getDistanceBetween(pPos, destPos) == 1 then
                local dir = getDirectionFromPos(pPos, destPos)
                if dir then g_game.walk(dir) end
              else
                local path = g_map.findPath(pPos, destPos, 5000, 0)
                if path and #path > 0 then
                  g_game.walk(path[1])
                end
              end
            end
          end
        end

        idx = cb.currentWpIndex or 1
        if idx > #wps or idx < 1 then idx = 1 end
        wpStr = wps[idx] or ''
        wpLower = wpStr:lower()

        local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
        if x and y and z then
          local dest = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
          if dest.z ~= pPos.z then
            ruleCooldowns.zWait = ruleCooldowns.zWait or now
            if (now - ruleCooldowns.zWait) >= 250 then
              ruleCooldowns.zWait = nil
              cb.currentWpIndex = (idx % #wps) + 1
              cavebotAdvanceUI()
            end
          else
            ruleCooldowns.zWait = nil
            local isNode = wpLower:find('^node') ~= nil
            local isAction = (wpLower:find('^rope') or wpLower:find('^hole') or wpLower:find('^shovel')
              or wpLower:find('^ladder') or wpLower:find('^use')) ~= nil
            local acceptDist = (isNode or isAction) and 1 or 0
            local dist = getDistanceBetween(pPos, dest)
            if dist <= acceptDist and (not isGlobalLure) and (not isNode) and (not isAction)
               and not cbPauseState and #cbMonsters >= stopCount then
              cbPauseState = true  -- box lure: segura aqui até limpar
              if player:isAutoWalking() then player:stopAutoWalk() end
              cavebotAdvanceUI()
            elseif dist <= acceptDist then
              if wpLower:find('^rope') then
                local tile = g_map.getTile(dest)
                if tile and tile:getTopUseThing() then
                  g_game.useInventoryItemWith(cb.ropeId or 3003, tile:getTopUseThing())
                end
              elseif wpLower:find('^hole') or wpLower:find('^shovel') then
                local tile = g_map.getTile(dest)
                if tile and tile:getTopUseThing() then
                  g_game.useInventoryItemWith(cb.shovelId or 5710, tile:getTopUseThing())
                end
              elseif wpLower:find('^ladder') or wpLower:find('^use') then
                local tile = g_map.getTile(dest)
                if tile and tile:getTopUseThing() then
                  g_game.use(tile:getTopUseThing())
                end
              end
              if (not isGlobalLure) and (not isNode) and (not isAction) then
                advancePastSameBoxCoord()
              else
                cb.currentWpIndex = (idx % #wps) + 1
              end
              cavebotAdvanceUI()
              local nextStr = wps[cb.currentWpIndex] or ''
              local nx, ny, nz = nextStr:match('(%d+),%s*(%d+),%s*(%d+)')
              if nx and tonumber(nz) == pPos.z then
                local nextDest = { x = tonumber(nx), y = tonumber(ny), z = tonumber(nz) }
                local nextLower = nextStr:lower()
                local nextForce = (nextLower:find('^stand') or nextLower:find('^hole')) ~= nil
                walkToCoord(nextDest, nextForce)
              end
            else
              local forceDir = (wpLower:find('^stand') or wpLower:find('^hole')) ~= nil
              walkToCoord(dest, forceDir)
            end
          end
        else
          cb.currentWpIndex = (idx % #wps) + 1
        end
      end
      lastCavebotTime = now
    end
  end
  end)
  if not okCb then helperTickError('cavebot', errCb) end
end

