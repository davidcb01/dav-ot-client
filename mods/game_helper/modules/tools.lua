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
  if uBox:getChildById('autoAolCheck') then uBox:getChildById('autoAolCheck'):setChecked(tl.autoAol == true) end
  if uBox:getChildById('autoQuiverCheck') then uBox:getChildById('autoQuiverCheck'):setChecked(tl.autoQuiver == true) end
  if uBox:getChildById('keepBpCheck') then uBox:getChildById('keepBpCheck'):setChecked(tl.keepBpOpen == true) end
  if uBox:getChildById('nextBpCheck') then uBox:getChildById('nextBpCheck'):setChecked(tl.nextBpFull == true) end
  if uBox:getChildById('autoPartyCheck') then uBox:getChildById('autoPartyCheck'):setChecked(tl.autoParty == true) end
  if uBox:getChildById('autoOberonCheck') then uBox:getChildById('autoOberonCheck'):setChecked(tl.autoOberon == true) end

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
  if uBox:getChildById('autoAolCheck') then
    uBox:getChildById('autoAolCheck').onCheckChange = function(w, ch) charConfig.tools.autoAol = (ch == true) saveCurrentProfile() end
    uBox:getChildById('autoQuiverCheck').onCheckChange = function(w, ch) charConfig.tools.autoQuiver = (ch == true) saveCurrentProfile() end
    uBox:getChildById('keepBpCheck').onCheckChange = function(w, ch) charConfig.tools.keepBpOpen = (ch == true) saveCurrentProfile() end
    uBox:getChildById('nextBpCheck').onCheckChange = function(w, ch) charConfig.tools.nextBpFull = (ch == true) saveCurrentProfile() end
    uBox:getChildById('autoPartyCheck').onCheckChange = function(w, ch) charConfig.tools.autoParty = (ch == true) saveCurrentProfile() end
    uBox:getChildById('autoOberonCheck').onCheckChange = function(w, ch) charConfig.tools.autoOberon = (ch == true) saveCurrentProfile() end
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

  if tl.autoAol and (now - lastAutoAolTime) >= 1200 then
    local neck = player:getInventoryItem(InventorySlotNeck)
    if not neck or neck:getId() ~= 3057 then
      local foundAol = nil
      for _, container in pairs(g_game.getContainers() or {}) do
        for _, item in ipairs(container:getItems() or {}) do
          if item and item:getId() == 3057 then
            foundAol = item
            break
          end
        end
        if foundAol then break end
      end
      if foundAol then
        g_game.move(foundAol, { x = 65535, y = InventorySlotNeck, z = 0 }, 1)
      else
        g_game.talk('!aol')
      end
    end
    lastAutoAolTime = now
  end

  if tl.autoQuiver and (now - lastQuiverTime) >= 200 then
    local rightItem = player:getInventoryItem(InventorySlotRight)
    if rightItem then
      local qId = rightItem:getId()
      local quiverContainer = nil
      for _, container in pairs(g_game.getContainers() or {}) do
        local rootItem = container:getContainerItem()
        if rootItem and rootItem:getId() == qId then
          quiverContainer = container
          break
        end
      end
      if not quiverContainer then
        g_game.open(rightItem)
      else
        local freeSlot = nil
        for s = 0, quiverContainer:getCapacity() - 1 do
          if not quiverContainer:getItem(s) then
            freeSlot = s
            break
          end
        end
        if freeSlot then
          for _, container in pairs(g_game.getContainers() or {}) do
            if container ~= quiverContainer then
              for _, item in ipairs(container:getItems() or {}) do
                if item and DEFAULT_QUIVER_AMMO_SET and DEFAULT_QUIVER_AMMO_SET[item:getId()] then
                  g_game.move(item, quiverContainer:getSlotPosition(freeSlot), item:getCount())
                  lastQuiverTime = now
                  freeSlot = nil
                  break
                end
              end
            end
            if not freeSlot then break end
          end
        end
      end
    end
    lastQuiverTime = now
  end

  if tl.keepBpOpen and (now - lastKeepBpTime) >= 1500 then
    local backItem = player:getInventoryItem(InventorySlotBack)
    if backItem then
      local bId = backItem:getId()
      local isOpen = false
      for _, container in pairs(g_game.getContainers() or {}) do
        local rootItem = container:getContainerItem()
        if rootItem and rootItem:getId() == bId then
          isOpen = true
          break
        end
      end
      if not isOpen then
        g_game.open(backItem)
      end
    end
    lastKeepBpTime = now
  end

  if tl.nextBpFull and (now - lastNextBpTime) >= 1000 then
    for _, container in pairs(g_game.getContainers() or {}) do
      local rootItem = container:getContainerItem()
      if rootItem and DEFAULT_BP_CONTAINER_SET and DEFAULT_BP_CONTAINER_SET[rootItem:getId()]
         and container:getCapacity() == #(container:getItems() or {}) then
        local opened = false
        for _, item in ipairs(container:getItems() or {}) do
          if item and DEFAULT_BP_CONTAINER_SET[item:getId()] then
            g_game.open(item, container)
            opened = true
            break
          end
        end
        if opened then break end
      end
    end
    lastNextBpTime = now
  end

  if tl.autoParty and (now - lastAutoPartyTime) >= 1200 then
    if player:isPartyLeader() then
      local sh = player:getShield()
      if sh ~= 10 and sh ~= 7 and g_game.partyShareExperience then
        g_game.partyShareExperience(true)
      end
    else
      for _, spec in ipairs(g_map.getSpectators(pPos, false) or {}) do
        if spec:isPlayer() and spec ~= player and spec:getShield() == 1 and g_game.partyJoin then
          g_game.partyJoin(spec:getId())
          break
        end
      end
    end
    lastAutoPartyTime = now
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

  if tl.autoParty and player:isPartyLeader() and name and name ~= player:getName() then
    local lowTxt = tostring(text or ''):lower()
    if (lowTxt == 'pt' or lowTxt == 'party' or lowTxt:find('%f[%a]pt%f[%A]') ~= nil) and not lowTxt:find('!party', 1, true) then
      local pPos = player:getPosition()
      if pPos then
        for _, spec in ipairs(g_map.getSpectators(pPos, true) or {}) do
          if spec:isPlayer() and spec:getName() == name and spec:getShield() == 0 and g_game.partyInvite then
            g_game.partyInvite(spec:getId())
            break
          end
        end
      end
    end
  end
end
