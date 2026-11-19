-- Tools tab UI, exercise scanner, callbacks, and tick engine

-- TOOLS: LIVE EXERCISE SCANNER & FOLLOW HELPER
-- ============================================================================

local function updateExerciseUI()
  local tBody = panels.tools:getChildById('leftToolsCol'):getChildById('exerciseBox')
  if not tBody then return end
  local wIcons = tBody:getChildById('exerciseWeaponIcons')
  local dIcons = tBody:getChildById('exerciseDummyIcons')
  local selLbl = tBody:getChildById('exerciseSelectedLabel')
  local exCfg = charConfig.tools.exercise

  if wIcons then
    wIcons:destroyChildren()
    if #scannedExerciseWeapons > 0 then
      if selectedWeaponScanIdx > #scannedExerciseWeapons then selectedWeaponScanIdx = 1 end
      for idx, w in ipairs(scannedExerciseWeapons) do
        local slot = g_ui.createWidget('HelperItemSlot', wIcons)
        slot:setSize({ width = 34, height = 34 })
        slot:setImageSource('')
        renderItemSlot(slot, w.id)
        local isSel = (idx == selectedWeaponScanIdx)
        slot:setBackgroundColor(isSel and '#1f5a1f' or '#262626')
        slot:setBorderColor(isSel and '#5ce65c' or '#1a1a1a')
        slot:setBorderWidth(isSel and 2 or 1)
        slot:setTooltip(w.name .. ' (ID: ' .. w.id .. ')')
        slot.onMouseRelease = function(widget, mousePos, mouseButton)
          if mouseButton == MouseLeftButton then
            selectedWeaponScanIdx = idx
            exCfg.weaponId = w.id
            updateExerciseUI()
            saveCurrentProfile()
            return true
          end
        end
      end
      exCfg.weaponId = scannedExerciseWeapons[selectedWeaponScanIdx].id
    end
  end

  if dIcons then
    dIcons:destroyChildren()
    if #scannedScreenDummys > 0 then
      if selectedDummyScanIdx > #scannedScreenDummys then selectedDummyScanIdx = 1 end
      for idx, d in ipairs(scannedScreenDummys) do
        local slot = g_ui.createWidget('HelperItemSlot', dIcons)
        slot:setSize({ width = 34, height = 34 })
        slot:setImageSource('')
        renderItemSlot(slot, d.id)
        local isSel = (idx == selectedDummyScanIdx)
        slot:setBackgroundColor(isSel and '#1f5a1f' or '#262626')
        slot:setBorderColor(isSel and '#5ce65c' or '#1a1a1a')
        slot:setBorderWidth(isSel and 2 or 1)
        slot:setTooltip(d.name .. ' (ID: ' .. d.id .. ')')
        slot.onMouseRelease = function(widget, mousePos, mouseButton)
          if mouseButton == MouseLeftButton then
            selectedDummyScanIdx = idx
            exCfg.dummyId = d.id
            exCfg.dummyPos = d.pos
            updateExerciseUI()
            saveCurrentProfile()
            return true
          end
        end
      end
      exCfg.dummyId = scannedScreenDummys[selectedDummyScanIdx].id
      exCfg.dummyPos = scannedScreenDummys[selectedDummyScanIdx].pos
    end
  end

  if selLbl then
    local wName = (#scannedExerciseWeapons > 0 and scannedExerciseWeapons[selectedWeaponScanIdx]) and scannedExerciseWeapons[selectedWeaponScanIdx].name or ht('None in BP')
    local dName = (#scannedScreenDummys > 0 and scannedScreenDummys[selectedDummyScanIdx]) and scannedScreenDummys[selectedDummyScanIdx].name or ht('None on Screen')
    selLbl:setText(htf('Weapon: %s | Dummy: %s', wName, dName))
  end
end

function scanExerciseAssets(announce)
  scannedExerciseWeapons = {}
  scannedScreenDummys = {}
  local seenWeapons = {}
  local seenDummyCoords = {}

  -- Scan open containers + inventory slots for exercise weapons
  for _, cont in pairs(g_game.getContainers()) do
    for _, item in ipairs(cont:getItems()) do
      local id = item:getId()
      local wName = getExerciseWeaponName(id)
      if wName and not seenWeapons[id] then
        seenWeapons[id] = true
        table.insert(scannedExerciseWeapons, { id = id, name = wName })
      end
    end
  end
  local player = g_game.getLocalPlayer()
  if player then
    for slot = InventorySlotHead, InventorySlotAmmo do
      local invItem = player:getInventoryItem(slot)
      if invItem then
        local id = invItem:getId()
        local wName = getExerciseWeaponName(id)
        if wName and not seenWeapons[id] then
          seenWeapons[id] = true
          table.insert(scannedExerciseWeapons, { id = id, name = wName })
        end
      end
    end

    -- Scan visible tiles around player for actual Training Dummys
    local pPos = player:getPosition()
    if pPos then
      for dx = -7, 7 do
        for dy = -5, 5 do
          local tPos = { x = pPos.x + dx, y = pPos.y + dy, z = pPos.z }
          local tile = g_map.getTile(tPos)
          if tile then
            for _, thing in ipairs(tile:getThings()) do
              if thing:isItem() then
                local tid = thing:getId()
                local dName = getExerciseDummyName(tid)
                if dName then
                  local key = tid .. '@' .. tPos.x .. ',' .. tPos.y
                  if not seenDummyCoords[key] then
                    seenDummyCoords[key] = true
                    table.insert(scannedScreenDummys, {
                      id = tid,
                      name = string.format('%s [%d,%d]', dName, tPos.x, tPos.y),
                      pos = tPos
                    })
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  updateExerciseUI()
  if announce and modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage(htf('[DAVCaster] Found %d exercise weapon(s) in BP, %d dummy(s) on screen.', #scannedExerciseWeapons, #scannedScreenDummys))
  end
end


function updateItemTimerCountdownUI(now)
  if not helperWindow or not helperWindow:isVisible() or currentTab ~= 'tools' then return end
  local lbl = panels.tools:getChildById('leftToolsCol'):getChildById('itemTimerBox'):getChildById('itemTimerCountdownLabel')
  if not lbl then return end
  local it = charConfig.tools.itemTimer
  if not it.enabled then
    lbl:setText(ht('Next: Disabled'))
    lbl:setColor('#aaaaaa')
  else
    local rem = math.max(0, math.ceil(((lastItemTimerTime + ((it.sec or 610) * 1000)) - now) / 1000))
    lbl:setText(htf('Next: %ds', rem))
    lbl:setColor('#77ff77')
  end
end


function loadToolsUI()
  -- 2. Tools UI
  local tl = charConfig.tools
  local tLeft = panels.tools:getChildById('leftToolsCol')
  local mtBox = tLeft:getChildById('manaTrainBox')
  renderSpellSlot(mtBox:getChildById('manaTrainSlot'), tl.manaTrain)
  mtBox:getChildById('manaTrainPctEdit'):setText(tostring(tl.manaTrain.pct or 85))
  local mtSecEd = mtBox:getChildById('manaTrainSecEdit')
  if mtSecEd then mtSecEd:setText(tostring(tl.manaTrain.sec or 2)) end
  mtBox:getChildById('manaTrainPzCheck'):setChecked(tl.manaTrain.pzCast ~= false)
  mtBox:getChildById('manaTrainCheck'):setChecked(tl.manaTrain.enabled == true)

  local hBox = tLeft:getChildById('hasteBox')
  renderSpellSlot(hBox:getChildById('hasteSlot'), tl.haste)
  hBox:getChildById('hastePzCheck'):setChecked(tl.haste.pzCast ~= false)
  hBox:getChildById('hasteEnableCheck'):setChecked(tl.haste.enabled == true)

  local exBoxT = tLeft:getChildById('exerciseBox')
  exBoxT:getChildById('exerciseEnableCheck'):setChecked(tl.exercise.enabled == true)
  scanExerciseAssets(false)

  local itBox = tLeft:getChildById('itemTimerBox')
  renderItemSlot(itBox:getChildById('itemTimerSlot'), tl.itemTimer.itemId)
  itBox:getChildById('itemTimerSecEdit'):setText(tostring(tl.itemTimer.sec or 610))
  itBox:getChildById('itemTimerEnableCheck'):setChecked(tl.itemTimer.enabled == true)

  local tRight = panels.tools:getChildById('rightToolsCol')
  local fBox = tRight:getChildById('followBox')
  fBox:getChildById('followNameEdit'):setText(tl.follow.name or '')
  fBox:getChildById('followModeCombo'):setCurrentOptionByData(tl.follow.mode or 'Default', true)
  local fDistCb = fBox:getChildById('followDistCombo')
  if fDistCb and fDistCb.setCurrentOptionByData then
    fDistCb:setCurrentOptionByData(math.max(1, math.min(4, tonumber(tl.follow.dist) or 1)), true)
  end
  fBox:getChildById('followTurnCheck'):setChecked(tl.follow.turn == true)
  if fBox:getChildById('followDoorsCheck') then
    fBox:getChildById('followDoorsCheck'):setChecked(tl.follow.openDoors ~= false)
  end
  fBox:getChildById('followEnableCheck'):setChecked(tl.follow.enabled == true)

  local uBox = tRight:getChildById('utilsBox')
  uBox:getChildById('changeGoldCheck'):setChecked(tl.changeGold == true)
  uBox:getChildById('autoEatCheck'):setChecked(tl.autoEat == true)
  uBox:getChildById('autoBlessCheck'):setChecked(tl.autoBless == true)
  uBox:getChildById('antiAfkCheck'):setChecked(tl.antiAfk == true)
  if uBox:getChildById('autoOberonCheck') then uBox:getChildById('autoOberonCheck'):setChecked(tl.autoOberon == true) end
  local qCfg = tl.quiver or {}
  if uBox:getChildById('autoQuiverCheck') then uBox:getChildById('autoQuiverCheck'):setChecked(qCfg.enabled == true) end
  if uBox:getChildById('quiverAmmoSlot') then renderItemSlot(uBox:getChildById('quiverAmmoSlot'), qCfg.itemId or 35901) end
  if uBox:getChildById('quiverMinEdit') then uBox:getChildById('quiverMinEdit'):setText(tostring(qCfg.minQty or 100)) end
  if uBox:getChildById('quiverMaxEdit') then uBox:getChildById('quiverMaxEdit'):setText(tostring(qCfg.maxQty or 500)) end

  -- 3. Shooter UI
end

function setupToolsCallbacks()
  -- Tools Tab Wiring
  local tLeft = panels.tools:getChildById('leftToolsCol')
  local mtBox = tLeft:getChildById('manaTrainBox')
  bindSlotClicks(mtBox:getChildById('manaTrainSlot'), function()
    local mt = charConfig.tools.manaTrain
    openSpellSelector('Select Mana Training Spell', nil, mt, function(sp)
      mt.words, mt.name, mt.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(mtBox:getChildById('manaTrainSlot'), mt)
    end)
  end, function()
    charConfig.tools.manaTrain.words, charConfig.tools.manaTrain.clientId = '', 0
    renderSpellSlot(mtBox:getChildById('manaTrainSlot'), charConfig.tools.manaTrain)
  end)
  mtBox:getChildById('manaTrainPctEdit').onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then charConfig.tools.manaTrain.pct = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end
  end
  local mtSecEd = mtBox:getChildById('manaTrainSecEdit')
  if mtSecEd then
    mtSecEd.onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then charConfig.tools.manaTrain.sec = math.max(1, math.min(3600, math.floor(n))) saveCurrentProfile() end
    end
  end
  mtBox:getChildById('manaTrainPzCheck').onCheckChange = function(w, ch) charConfig.tools.manaTrain.pzCast = ch saveCurrentProfile() end
  mtBox:getChildById('manaTrainCheck').onCheckChange = function(w, ch) charConfig.tools.manaTrain.enabled = ch saveCurrentProfile() end

  local hBox = tLeft:getChildById('hasteBox')
  bindSlotClicks(hBox:getChildById('hasteSlot'), function()
    local hs = charConfig.tools.haste
    openSpellSelector('Select Haste Spell', 'haste', hs, function(sp)
      hs.words, hs.name, hs.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(hBox:getChildById('hasteSlot'), hs)
    end)
  end, function()
    charConfig.tools.haste.words, charConfig.tools.haste.clientId = '', 0
    renderSpellSlot(hBox:getChildById('hasteSlot'), charConfig.tools.haste)
  end)
  hBox:getChildById('hastePzCheck').onCheckChange = function(w, ch) charConfig.tools.haste.pzCast = ch saveCurrentProfile() end
  hBox:getChildById('hasteEnableCheck').onCheckChange = function(w, ch) charConfig.tools.haste.enabled = ch saveCurrentProfile() end

  local exBoxT = tLeft:getChildById('exerciseBox')
  exBoxT:getChildById('exerciseEnableCheck').onCheckChange = function(w, ch)
    charConfig.tools.exercise.enabled = ch
    if ch then scanExerciseAssets(false) end
    saveCurrentProfile()
  end

  local itBox = tLeft:getChildById('itemTimerBox')
  local itSlot = itBox:getChildById('itemTimerSlot')
  bindSlotClicks(itSlot, nil, function()
    charConfig.tools.itemTimer.itemId = 0
    renderItemSlot(itSlot, 0)
  end)
  attachItemDropHandler(itSlot, function(droppedId)
    charConfig.tools.itemTimer.itemId = droppedId
    renderItemSlot(itSlot, droppedId)
  end)
  itBox:getChildById('itemTimerSecEdit').onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then charConfig.tools.itemTimer.sec = math.max(1, math.min(86400, math.floor(n))) saveCurrentProfile() end
  end
  itBox:getChildById('itemTimerEnableCheck').onCheckChange = function(w, ch)
    charConfig.tools.itemTimer.enabled = ch
    if ch then
      local itemId = tonumber(charConfig.tools.itemTimer.itemId) or 0
      if itemId > 0 and g_game.isOnline() then
        g_game.useInventoryItem(itemId)
      end
      lastItemTimerTime = g_clock.millis()
    end
    saveCurrentProfile()
  end

  local tRight = panels.tools:getChildById('rightToolsCol')
  local fBox = tRight:getChildById('followBox')
  local fModeCb = fBox:getChildById('followModeCombo')
  for _, opt in ipairs({ 'Default', 'Front', 'Back', 'Left', 'Right' }) do
    fModeCb:addOption(ht(opt), opt)
  end
  fModeCb.onOptionChange = function(w, text, data)
    if isLoadingUI or refreshingLanguageCombos then return end
    charConfig.tools.follow.mode = getComboOptionData(w, data or text) or 'Default'
    saveCurrentProfile()
  end
  local fDistCb = fBox:getChildById('followDistCombo')
  for _, dOpt in ipairs({ 1, 2, 3, 4 }) do
    fDistCb:addOption(tostring(dOpt), dOpt)
  end
  fDistCb.onOptionChange = function(w, text, data)
    if isLoadingUI or refreshingLanguageCombos then return end
    local d = tonumber(getComboOptionData(w, data or text)) or 1
    charConfig.tools.follow.dist = math.max(1, math.min(4, math.floor(d)))
    saveCurrentProfile()
  end
  fBox:getChildById('followTurnCheck').onCheckChange = function(w, ch)
    if isLoadingUI then return end
    charConfig.tools.follow.turn = ch
    saveCurrentProfile()
  end
  if fBox:getChildById('followDoorsCheck') then
    fBox:getChildById('followDoorsCheck').onCheckChange = function(w, ch)
      if isLoadingUI then return end
      charConfig.tools.follow.openDoors = (ch == true)
      saveCurrentProfile()
    end
  end
  fBox:getChildById('followEnableCheck').onCheckChange = function(w, ch)
    if isLoadingUI then return end
    charConfig.tools.follow.enabled = ch
    resetFollowRuntimeState()
    updateStatsUI()
    saveCurrentProfile()
  end

  local uBox = tRight:getChildById('utilsBox')
  uBox:getChildById('changeGoldCheck').onCheckChange = function(w, ch) charConfig.tools.changeGold = ch saveCurrentProfile() end
  uBox:getChildById('autoEatCheck').onCheckChange = function(w, ch) charConfig.tools.autoEat = ch saveCurrentProfile() end
  uBox:getChildById('autoBlessCheck').onCheckChange = function(w, ch) charConfig.tools.autoBless = ch saveCurrentProfile() end
  uBox:getChildById('antiAfkCheck').onCheckChange = function(w, ch)
    charConfig.tools.antiAfk = ch
    antiAfkFirstDone = false
    lastAfkTime = g_clock.millis()
    saveCurrentProfile()
  end
  if uBox:getChildById('autoOberonCheck') then
    uBox:getChildById('autoOberonCheck').onCheckChange = function(w, ch) charConfig.tools.autoOberon = (ch == true) saveCurrentProfile() end
  end
  if uBox:getChildById('autoQuiverCheck') then
    uBox:getChildById('autoQuiverCheck').onCheckChange = function(w, ch)
      charConfig.tools.quiver = charConfig.tools.quiver or {}
      charConfig.tools.quiver.enabled = (ch == true)
      quiverRefillingActive = false
      saveCurrentProfile()
    end
  end
  local qSlot = uBox:getChildById('quiverAmmoSlot')
  if qSlot then
    bindSlotClicks(qSlot, function()
      local qCfg = charConfig.tools.quiver or {}
      openItemSelector('Select Ammo / Arrow / Bolt', 'ammo', qCfg.itemId, function(it)
        charConfig.tools.quiver.itemId = it.id
        renderItemSlot(qSlot, it.id)
        saveCurrentProfile()
      end)
    end, function()
      charConfig.tools.quiver.itemId = 0
      renderItemSlot(qSlot, 0)
      saveCurrentProfile()
    end)
    attachItemDropHandler(qSlot, function(droppedId)
      charConfig.tools.quiver.itemId = droppedId
      renderItemSlot(qSlot, droppedId)
      saveCurrentProfile()
    end)
  end
  if uBox:getChildById('quiverMinEdit') then
    uBox:getChildById('quiverMinEdit').onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        charConfig.tools.quiver.minQty = math.max(1, math.min(5000, math.floor(n)))
        saveCurrentProfile()
      end
    end
  end
  if uBox:getChildById('quiverMaxEdit') then
    uBox:getChildById('quiverMaxEdit').onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        charConfig.tools.quiver.maxQty = math.max(1, math.min(5000, math.floor(n)))
        saveCurrentProfile()
      end
    end
  end

  -- Shooter Tab Wiring (edicao em tempo real, sem botao Update)
end

function runToolsTick(player, pPos, now, mpPct, inPz, hasHaste)
  -- 3. TOOLS AUTOMATION
  local tl = charConfig.tools
  if tl.haste.enabled and tl.haste.words ~= '' and not hasHaste and (tl.haste.pzCast or not inPz)
     and (now - lastHasteTime) >= 2000 and not isSpellOnClientCooldown(tl.haste.words, now) then
    g_game.talk(tl.haste.words)
    lastHasteTime = now
    local hSp = findSpellByWords(tl.haste.words)
    if hSp and type(hSp.group) == 'table' then
      for gid, _ in pairs(hSp.group) do
        local gNum = tonumber(gid) or gid
        groupCooldownUntil[gNum] = math.max(groupCooldownUntil[gNum] or 0, now + 300)
      end
    end
  end

  local mtIntervalMs = math.max(1, tonumber(tl.manaTrain.sec) or 2) * 1000
  if tl.manaTrain.enabled and tl.manaTrain.words ~= '' and (tl.manaTrain.pzCast or not inPz)
     and mpPct >= (tonumber(tl.manaTrain.pct) or 85) and (now - lastManaTrainTime) >= mtIntervalMs
     and (now - lastCastTime) >= 1000 and not isSpellOnClientCooldown(tl.manaTrain.words, now) then
    g_game.talk(tl.manaTrain.words)
    lastManaTrainTime = now
  end

  if tl.exercise.enabled and inPz and (now - lastExerciseTime) >= 10000 then
    local training = player.isTraining and player:isTraining() or false
    if not training then
      if #scannedExerciseWeapons == 0 or #scannedScreenDummys == 0 then
        scanExerciseAssets(false)
      end
      local wId = tonumber(tl.exercise.weaponId) or 0
      local wItem = (wId > 0) and findContainerItemById(wId) or nil
      if not wItem and #scannedExerciseWeapons > 0 then
        wItem = findContainerItemById(scannedExerciseWeapons[1].id)
      end
      local dThing = findVisibleDummyThing(pPos, tonumber(tl.exercise.dummyId) or 28558)
      if wItem and dThing then
        g_game.useWith(wItem, dThing)
      end
    end
    lastExerciseTime = now
  end

    local hungryOk = true
    if PlayerStates.Hungry ~= nil then hungryOk = player:hasState(PlayerStates.Hungry) end
    if tl.autoEat and (now - lastEatTime) >= 15000 then
    local hungryOk = true
    if PlayerStates.Hungry ~= nil then hungryOk = player:hasState(PlayerStates.Hungry) end
    if hungryOk and now >= (ruleCooldowns.eatFullUntil or 0) then
      local ate = false
      for _, cont in pairs(g_game.getContainers()) do
        for _, item in ipairs(cont:getItems()) do
          if FOOD_ID_SET[item:getId()] then
            g_game.use(item)
            ate = true
            break
          end
        end
        if ate then break end
      end
      if ate then
        lastEatTime = now
      else
        lastEatTime = now - 12000  -- não achou: tenta de novo em 3 s
        if (now - (ruleCooldowns.eatWarnAt or -60000)) > 60000 then
          ruleCooldowns.eatWarnAt = now
          if modules.game_textmessage then
            modules.game_textmessage.displayStatusMessage('[DAVCaster] Auto Eat: nenhuma comida nos containers abertos')
          end
        end
      end
    end
  end

  if tl.changeGold and (now - lastGoldTime) >= 150 then
    local anyUsed = false
    for _, cid in ipairs({ 3031, 3035 }) do
      local used = false
      for _, cont in pairs(g_game.getContainers()) do
        for _, item in ipairs(cont:getItems()) do
          if item:getId() == cid and item:getCount() == 100 then
            if item.isMultiUse and item:isMultiUse() then
              g_game.useWith(item, item)
            else
              g_game.use(item)
            end
            used = true
            break
          end
        end
        if used then break end
      end
      if used then
        anyUsed = true
        lastGoldTime = now
        break
      end
    end
    if not anyUsed then
      lastGoldTime = now + 650
    end
  end

  if tl.autoBless and (now - lastBlessTime) >= 30000 then
    if not hasCoreBlessings(player) then
      g_game.talk('!bless')
      if g_game.requestBless then g_game.requestBless() end
    end
    lastBlessTime = now
  end

  if tl.antiAfk then
    local afkInterval = antiAfkFirstDone and 600000 or 3000
    if (now - lastAfkTime) >= afkInterval then
      g_game.turn((player:getDirection() + 1) % 4)
      lastAfkTime = now
      antiAfkFirstDone = true
    end
  end

  if tl.itemTimer.enabled and tl.itemTimer.itemId > 0 and (now - lastItemTimerTime) >= ((tl.itemTimer.sec or 610) * 1000) then
    g_game.useInventoryItem(tl.itemTimer.itemId)
    lastItemTimerTime = now
  end

  local qCfg = tl.quiver
  if qCfg and qCfg.enabled and (now - lastQuiverTime) >= 250 then
    local targetAmmoId = tonumber(qCfg.itemId) or 0
    local minQty = math.max(1, tonumber(qCfg.minQty) or 100)
    local maxQty = math.max(minQty, tonumber(qCfg.maxQty) or 500)

    local equippedQuiverIds = {}
    local closedQuiverItem = nil
    for _, slot in ipairs({ InventorySlotRight, InventorySlotLeft, InventorySlotAmmo }) do
      local eq = player:getInventoryItem(slot)
      if eq and eq.isContainer and eq:isContainer() then
        equippedQuiverIds[eq:getId()] = eq
      end
    end

    local openQuivers = {}
    local nonQuiverContainers = {}
    for _, container in pairs(g_game.getContainers() or {}) do
      local rootItem = container:getContainerItem()
      local rId = rootItem and rootItem:getId() or 0
      if rId > 0 and equippedQuiverIds[rId] then
        table.insert(openQuivers, container)
      else
        table.insert(nonQuiverContainers, container)
      end
    end

    for qId, eqItem in pairs(equippedQuiverIds) do
      local foundOpen = false
      for _, qc in ipairs(openQuivers) do
        local r = qc:getContainerItem()
        if r and r:getId() == qId then foundOpen = true break end
      end
      if not foundOpen then
        closedQuiverItem = eqItem
        break
      end
    end

    if closedQuiverItem then
      g_game.open(closedQuiverItem)
      lastQuiverTime = now
    else
      local totalAmmoInQuiver = 0
      local detectedAmmoId = targetAmmoId
      for _, qc in ipairs(openQuivers) do
        for _, item in ipairs(qc:getItems() or {}) do
          if item then
            local iid = item:getId()
            if (targetAmmoId > 0 and iid == targetAmmoId) or (targetAmmoId == 0 and DEFAULT_QUIVER_AMMO_SET and DEFAULT_QUIVER_AMMO_SET[iid]) then
              totalAmmoInQuiver = totalAmmoInQuiver + (item:getCount() or 1)
              if detectedAmmoId == 0 then detectedAmmoId = iid end
            end
          end
        end
      end

      if totalAmmoInQuiver < minQty then
        quiverRefillingActive = true
      elseif totalAmmoInQuiver >= maxQty then
        quiverRefillingActive = false
      end

      if quiverRefillingActive and totalAmmoInQuiver < maxQty and #openQuivers > 0 then
        local needed = maxQty - totalAmmoInQuiver
        local moveId = (targetAmmoId > 0) and targetAmmoId or (detectedAmmoId > 0 and detectedAmmoId or 35901)

        -- Destino em qualquer quiver com espaco (stack incompleto do mesmo item ou slot livre)
        local destPos = nil
        for _, qc in ipairs(openQuivers) do
          for s = 0, qc:getCapacity() - 1 do
            local existing = qc:getItem(s)
            if existing and existing:getId() == moveId and existing:getCount() < 100 then
              destPos = qc:getSlotPosition(s)
              break
            elseif not existing then
              destPos = qc:getSlotPosition(s)
              break
            end
          end
          if destPos then break end
        end

        if destPos then
          local movedFromOpen = false
          for _, bc in ipairs(nonQuiverContainers) do
            for _, item in ipairs(bc:getItems() or {}) do
              if item and item:getId() == moveId then
                g_game.move(item, destPos, math.min(needed, item:getCount() or 1))
                movedFromOpen = true
                break
              end
            end
            if movedFromOpen then break end
          end
          if not movedFromOpen and g_game.equipItemId then
            g_game.equipItemId(moveId)
          end
        end
      end
      lastQuiverTime = now
    end
  end

  runFollowEngine(player, pPos, now)
end

function onHelperTalk(name, level, mode, text)
  if not g_game.isOnline() or not charConfig or not charConfig.tools then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local now = g_clock.millis()
  local tl = charConfig.tools

  if tl.autoOberon and name and name ~= player:getName() then
    local lowName = tostring(name):lower()
    if lowName:find('oberon', 1, true) and (now - lastOberonTime) >= 3000 then
      local clean = tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')
      local resp = OBERON_EXACT_RESPONSES and OBERON_EXACT_RESPONSES[clean:lower()]
      if not resp then
        if clean:sub(1, 1):lower() == 't' then
          resp = 'Are you ever going to fight or do you prefer talking! Then let me show you the concept of mortality before it! Dare strike up a Minnesang and you will receive your last accolade!'
        else
          resp = 'Even before they smell your breath? Too bad you barely exist at all! SEHWO ASIMO, TOLIDO ESD Excuse me but I still do not get the message! Then why are we fighting alone right now? How appropriate, you look like something worms already got the better of!'
        end
      end
      if resp and resp ~= '' then
        lastOberonTime = now
        local delayMs = 1000 + ((g_game.getPing and g_game.getPing()) or 0)
        scheduleEvent(function()
          if g_game.isOnline() then
            g_game.talk(resp)
          end
        end, math.max(50, delayMs))
      end
    end
  end
end
