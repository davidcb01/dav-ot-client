-- DAVCaster - Native Helper & Automation (Modular Entry Point)

function loadProfileIntoUI()
  isLoadingUI = true
  refreshingShooterUI = true
  refreshingTargetUI = true
  setHelperLanguageState((charConfig and charConfig.language) or 'en')
  applyHelperLanguage(true)
  updateMasterBarUI()
  updateStatsUI()
  updateKeyButtonsUI()
  applyVocationVisibility()

  -- 1. Healing UI
  loadHealingUI()
  loadToolsUI()
  loadShooterUI()
  loadTargetUI()
  loadCavebotUI()
  refreshSettingsTabUI()
  syncLanguageCombos()
  refreshingShooterUI = false
  refreshingTargetUI = false
  isLoadingUI = false
end

function setupWidgetsAndCallbacks()
  helperWindow.onDragLeave = function()
    local pos = helperWindow:getPosition()
    if pos then
      charConfig.windowPos = { x = pos.x, y = pos.y }
      saveCurrentProfile()
    end
    return true
  end

  -- Delete guard & global helper shortcut dispatch on ALL helper windows & modals
  for _, win in ipairs({ helperWindow, statsWindow, spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, keyCaptureModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal, finisherSettingsModal }) do
    installDeleteNoCloseGuard(win)
  end

  -- Spell Selector Modal
  spellSelectorModal:getChildById('searchEdit').onTextChange = function() populateSpellSelectorList() end
  spellSelectorModal:getChildById('clearSearchBtn').onClick = function() spellSelectorModal:getChildById('searchEdit'):setText('') end
  spellSelectorModal:getChildById('filterPanel'):getChildById('onlyVocationCheck').onCheckChange = function() populateSpellSelectorList() end
  spellSelectorModal:getChildById('okBtn').onClick = function() confirmSpellSelection(true) end
  spellSelectorModal:getChildById('applyBtn').onClick = function() confirmSpellSelection(false) end
  spellSelectorModal:getChildById('cancelBtn').onClick = function() spellSelectorModal:hide() end

  -- Item Selector Modal
  itemSelectorModal:getChildById('searchEdit').onTextChange = function() populateItemSelectorList() end
  itemSelectorModal:getChildById('clearSearchBtn').onClick = function() itemSelectorModal:getChildById('searchEdit'):setText('') end
  itemSelectorModal:getChildById('okBtn').onClick = function() confirmItemSelection() end
  itemSelectorModal:getChildById('clearBtn').onClick = function()
    if activeItemSlotCallback then
      activeItemSlotCallback({ id = 0, name = '', ptype = 'hp' })
      saveCurrentProfile()
    end
    itemSelectorModal:hide()
  end
  itemSelectorModal:getChildById('cancelBtn').onClick = function() itemSelectorModal:hide() end

  -- Rename Preset Modal
  setupHealingCallbacks()
  setupToolsCallbacks()
  setupShooterCallbacks()
  setupTargetCallbacks()
  setupCavebotCallbacks()
  -- Helper Language Combos (Bottom bar + Settings tab, synced per character)
  local function initLangCombo(cb)
    if not cb then return end
    cb:addOption('English', 'en')
    cb:addOption('Portugu�s', 'pt')
    cb:setCurrentOptionByData(getHelperLanguage(), true)
    cb.onOptionChange = function(w, text, data)
      if refreshingLanguageCombos then return end
      local chosen = getComboOptionData(w, data)
      setHelperLanguage(chosen == 'pt' and 'pt' or 'en')
    end
  end

  local bBar = helperWindow:getChildById('bottomBar')
  initLangCombo(bBar and bBar:getChildById('helperLangCombo'))
  if panels.settings then
    local curBox = panels.settings:getChildById('currentProfileBox')
    initLangCombo(curBox and curBox:getChildById('settingsLangCombo'))
  end

  for _, w in ipairs({ helperWindow, statsWindow, spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal, finisherSettingsModal }) do
    installClickOutsideUnfocus(w)
  end
  local gameMap = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  for _, gw in ipairs({ rootWidget, gameMap }) do
    if gw and not gw._helperRootUnfocusHooked then
      gw._helperRootUnfocusHooked = true
      connect(gw, {
        onMousePress = function(w, mousePos)
          unfocusActiveHelperTextEdit(mousePos)
        end
      }, true)
    end
  end
end

-- ============================================================================

function onHelperTick()
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pPos = player:getPosition()
  local now = g_clock.millis()

  if pPos then
    if not playerStopTracker.pos or playerStopTracker.pos.x ~= pPos.x or playerStopTracker.pos.y ~= pPos.y or playerStopTracker.pos.z ~= pPos.z then
      playerStopTracker.pos = { x = pPos.x, y = pPos.y, z = pPos.z }
      playerStopTracker.since = now
    end
  end

  -- Keep Cavebot Minimap centered & run AutoRec (configurable SQM + Stand on stairs/teleport + immediate Node)
  runCavebotAutoRec(player, pPos, now)
  tickFloorMarkers(now)

  if helperSavePending and (now - (helperLastSaveAt or 0)) >= 5000 then
    helperSavePending = false
    helperLastSaveAt = now
    saveCurrentProfile()
  end

  updateItemTimerCountdownUI(now)

  -- STRICT MASTER GATE: Zero actions run when helper is disabled!
  if charConfig.masterEnabled ~= true then return end

  local hpPct = player:getHealthPercent()
  local maxMp = player:getMaxMana()
  local mpPct = (maxMp and maxMp > 0) and math.floor((player:getMana() * 100) / maxMp) or 100
  local inPz = player:hasState(PlayerStates.Pz)
  local isParalyzed = player:hasState(PlayerStates.Paralyze)
  local hasHaste = player:hasState(PlayerStates.Haste)
  local hasUtamo = player:hasState(PlayerStates.ManaShield)
  local hasFear = (PlayerStates.Fear ~= nil) and player:hasState(PlayerStates.Fear) or false
  local vp = getVocProfile()

  local nearbyMonsters, nearbyPlayers = getNearbyMonsters(pPos, 7, vp.shooter.ignoreList)
  local adjacentMonsters = 0
  for _, m in ipairs(nearbyMonsters) do
    if m.dist <= 1 then adjacentMonsters = adjacentMonsters + 1 end
  end

  -- 1. AUTO HEALING (Unlimited Spells & Potions + Strict Module Gate)
  runHealingTick(player, pPos, now, hpPct, mpPct, inPz, isParalyzed, hasUtamo, vp)
  currentTarget = runTargetTick(player, pPos, now, inPz, vp, nearbyMonsters, currentTarget)
  runShooterTick(player, pPos, now, mpPct, inPz, vp, nearbyMonsters, adjacentMonsters, currentTarget, nearbyPlayers)
  runToolsTick(player, pPos, now, mpPct, inPz, hasHaste)
  runCavebotTick(player, pPos, now, nearbyMonsters)
end

-- MODULE LIFECYCLE
-- ============================================================================

-- Quando o alvo muda por clique do jogador, reavalia na hora (sem esperar o proximo tick).
function onHelperAttackCreatureChange(creature, oldCreature)
  if not charConfig or charConfig.masterEnabled ~= true then return end
  local now = g_clock.millis()
  if (now - (ruleCooldowns.attackSent or 0)) < 120 then return end  -- foi o proprio helper que trocou
  ruleCooldowns.attackSent = 0
  addEvent(onHelperTick)
end

function onHelperTextMessage(mode, text)
  if text and text:lower():find('you are full', 1, true) then
    ruleCooldowns.eatFullUntil = g_clock.millis() + 600000
  end
end

function onHelperPlayerPosChange(player, newPos, oldPos)
  if not newPos or not oldPos then return end

  if newPos.z ~= oldPos.z then
    -- mudou de andar: tudo imediato (waypoints no mapa/chao, indice e proximo passo sem esperar 2.5s)
    ruleCooldowns.zWait = nil
    helperLastRenderZ = newPos.z
    local cb = charConfig and charConfig.cavebot
    if cb and cb.enabled and not cavebotAutoRec then
      local wps = cb.waypoints or {}
      local n = #wps
      local idx = cb.currentWpIndex or 1
      local guard = 0
      while n > 0 and guard < n do
        local z = (wps[idx] or ''):match('%d+,%s*%d+,%s*(%d+)')
        if z and tonumber(z) == oldPos.z then
          idx = (idx % n) + 1
          guard = guard + 1
        else
          break
        end
      end
      if idx ~= (cb.currentWpIndex or 1) then
        cb.currentWpIndex = idx
        cavebotAdvanceUI()
      end
    end
    if cb then
      renderCavebotWaypointsOnMaps()
    end
    if cb and cb.enabled and not cavebotAutoRec then
      addEvent(onHelperTick)
    end
  end

  if not cavebotAutoRec then return end
  if newPos.z == oldPos.z then return end
  local wps = charConfig.cavebot.waypoints
  -- Stand = tile exato da escada/buraco/rope no andar antigo, nunca 1 SQM depois
  local standPos = resolveFloorChangeStandPos(oldPos, newPos)
  local standStr = string.format('Stand: %d, %d, %d', standPos.x, standPos.y, standPos.z)
  local lx, ly, lz = (wps[#wps] or ''):match('^Node:%s*(%d+),%s*(%d+),%s*(%d+)')
  if lx and tonumber(lx) == standPos.x and tonumber(ly) == standPos.y and tonumber(lz) == standPos.z then
    wps[#wps] = standStr   -- o ultimo Node ja estava nesse tile: vira Stand (sem duplicar)
  else
    table.insert(wps, standStr)
  end
  table.insert(wps, string.format('Node: %d, %d, %d', newPos.x, newPos.y, newPos.z))
  lastAutoRecPos = { x = newPos.x, y = newPos.y, z = newPos.z }
  selectedCavebotWpIdx = #wps
  refreshCavebotUI(true)
  saveCurrentProfile()
end

function init()
  g_ui.importStyle('modals')
  helperWindow = g_ui.loadUI('helper', rootWidget)
  local container = helperWindow:getChildById('contentContainer')
  panels.healing  = g_ui.loadUI('healing', container)
  panels.tools    = g_ui.loadUI('tools', container)
  panels.shooter  = g_ui.loadUI('shooter', container)
  panels.target   = g_ui.loadUI('target', container)
  panels.cavebot  = g_ui.loadUI('cavebot', container)
  panels.settings = g_ui.loadUI('settings', container)

  spellSelectorModal     = g_ui.createWidget('SpellSelectorModal', rootWidget)
  itemSelectorModal      = g_ui.createWidget('ItemSelectorModal', rootWidget)
  renamePresetModal      = g_ui.createWidget('RenamePresetModal', rootWidget)
  conditionSettingsModal = g_ui.createWidget('ConditionSettingsModal', rootWidget)
  keyCaptureModal        = g_ui.createWidget('KeyCaptureModal', rootWidget)
  cavebotSettingsModal   = g_ui.createWidget('CavebotSettingsModal', rootWidget)
  cbControlMiniHud       = g_ui.createWidget('CbControlMiniHud', rootWidget)
  idsMenuModal           = g_ui.createWidget('IdsMenuModal', rootWidget)
  huntListModal          = g_ui.createWidget('HuntListModal', rootWidget)
  finisherSettingsModal  = g_ui.createWidget('FinisherSettingsModal', rootWidget)

  statsWindow = g_ui.loadUI('stats', modules.game_interface.getRightPanel())
  statsWindow:setup()
  statsWindow:close(true)
  statsWindow:hide()

  if modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
    helperButton = modules.game_mainpanel.addToggleButton(
      'davCasterBtn',
      tr('DAVCaster Helper'),
      '/mods/game_helper/images/custom/helper_closed',
      toggle,
      false,
      1
    )
    updateHelperButtonIcon(false)
  end

  if CharConfig then CharConfig.migrateLegacyNode(DAVHELPER_NS, DAVHELPER_LEGACY_NODE) end
  setupTabIcons()
  setupWidgetsAndCallbacks()
  applyHelperLanguage(true)
  switchTab('healing')
  switchHealingSubTab('self')

  local function onHelperVocationChange(localPlayer, vocation, oldVocation)
    if not g_game.isOnline() then return end
    local newVoc = detectPlayerVocation()
    if newVoc and newVoc ~= currentVocName then
      currentVocName = newVoc
      getVocProfile(currentVocName)
      loadProfileIntoUI()
    end
  end
  local function onHelperBlessingsChange(localPlayer, blessings, oldBlessings, blessVisualState)
    if not g_game.isOnline() then return end
    if localPlayer == g_game.getLocalPlayer() and blessVisualState ~= nil then
      lastBlessVisualState = tonumber(blessVisualState)
      if lastBlessVisualState and lastBlessVisualState < 2 then
        lastBlessDialogCoreOk = false
      end
    end
  end
  local function onHelperUpdateBlessDialog(data)
    if not g_game.isOnline() or type(data) ~= 'table' or type(data.blesses) ~= 'table' then return end
    local activeCount = 0
    for _, entry in ipairs(data.blesses) do
      if ((tonumber(entry.playerBlessCount) or 0) + (tonumber(entry.store) or 0)) >= 1 then
        activeCount = activeCount + 1
      end
    end
    local needed = math.min(5, math.max(1, #data.blesses - 1))
    lastBlessDialogCoreOk = (activeCount >= needed)
  end
  _G._davHelperOnVocChange = onHelperVocationChange
  _G._davHelperOnBlessingsChange = onHelperBlessingsChange
  _G._davHelperOnUpdateBlessDialog = onHelperUpdateBlessDialog

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onTextMessage = onHelperTextMessage,
    onTalk = onHelperTalk,
    onFollowingCreatureChange = onHelperFollowCreatureChange,
    onAttackingCreatureChange = onHelperAttackCreatureChange,
    onSpellCooldown = onHelperSpellCooldown,
    onSpellGroupCooldown = onHelperSpellGroupCooldown,
    onUpdateBlessDialog = _G._davHelperOnUpdateBlessDialog
  })
  connect(LocalPlayer, {
    onPositionChange = onHelperPlayerPosChange,
    onVocationChange = _G._davHelperOnVocChange,
    onBlessingsChange = _G._davHelperOnBlessingsChange
  })
  refreshGlobalKeyHooks()

  if not origGameLook and g_game and g_game.look then
    origGameLook = g_game.look
    g_game.look = function(thing, isBattleList)
      if idsMenuModal and idsMenuModal:isVisible() and thing and thing.getId then
        local addIdEdit = idsMenuModal:getChildById('addIdRow') and idsMenuModal:getChildById('addIdRow'):getChildById('addIdEdit')
        if addIdEdit and addIdEdit:isFocused() then
          local tid = tonumber(thing:getId())
          if tid and tid > 0 then
            addIdEdit:setText(tostring(tid))
          end
        end
      end
      return origGameLook(thing, isBattleList)
    end
  end

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  if origGameLook and g_game then
    g_game.look = origGameLook
    origGameLook = nil
  end
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onTextMessage = onHelperTextMessage,
    onTalk = onHelperTalk,
    onFollowingCreatureChange = onHelperFollowCreatureChange,
    onAttackingCreatureChange = onHelperAttackCreatureChange,
    onSpellCooldown = onHelperSpellCooldown,
    onSpellGroupCooldown = onHelperSpellGroupCooldown,
    onUpdateBlessDialog = _G._davHelperOnUpdateBlessDialog
  })
  _G._davHelperOnUpdateBlessDialog = nil
  if _G._davHelperOnVocChange or _G._davHelperOnBlessingsChange then
    disconnect(LocalPlayer, {
      onPositionChange = onHelperPlayerPosChange,
      onVocationChange = _G._davHelperOnVocChange,
      onBlessingsChange = _G._davHelperOnBlessingsChange
    })
    _G._davHelperOnVocChange = nil
    _G._davHelperOnBlessingsChange = nil
  end
  detachAllGlobalKeyHooks()
  clearTemporaryWaypointMarkers()
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  unbindShortcutKeys()
  closeKeyCapture()
  saveCurrentProfile()

  for _, w in ipairs({ spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, keyCaptureModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal, finisherSettingsModal, helperWindow, statsWindow, helperButton }) do
    if w then w:destroy() end
  end
  spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, keyCaptureModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal, finisherSettingsModal, helperWindow, statsWindow, helperButton = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
end

function onGameStart()
  isLoadingUI = false
  resetFollowRuntimeState()
  currentCharName = g_game.getCharacterName()
  currentVocName = detectPlayerVocation()
  lastAfkTime = g_clock.millis()
  antiAfkFirstDone = false
  lastItemTimerTime = g_clock.millis()
  lastBlessTime = -30000
  lastBlessVisualState = nil
  lastBlessDialogCoreOk = nil
  spellCooldownUntil = {}
  groupCooldownUntil = {}
  ruleCooldowns = {}
  lastCastTime = 0
  lastShooterCastTime = 0
  lastSupportShooterCastTime = 0
  lastPotionTime = 0
  lastCavebotTime = 0
  cbPauseState = false
  cavebotLureActive = false
  playerStopTracker = { pos = nil, since = 0 }
  loadCharacterProfile(currentCharName)

  if statsWindow then
    statsWindow:setupOnStart()
    updateStatsUI()
  end
  if helperWindow then
    helperWindow:hide()
    if helperButton then helperButton:setOn(false) end
  end
  if g_game.requestBless then
    g_game.requestBless()
  end
  rebuildShortcutBindings()

  if tickEvent then
    removeEvent(tickEvent)
  end
  tickEvent = cycleEvent(onHelperTick, 100)
end

function onGameEnd()
  isLoadingUI = false
  saveCurrentProfile()
  resetFollowRuntimeState()
  clearTemporaryWaypointMarkers()
  unbindShortcutKeys()
  closeKeyCapture()
  spellCooldownUntil = {}
  groupCooldownUntil = {}
  ruleCooldowns = {}
  lastCastTime = 0
  lastShooterCastTime = 0
  lastSupportShooterCastTime = 0
  lastPotionTime = 0
  lastCavebotTime = 0
  cbPauseState = false
  cavebotLureActive = false
  playerStopTracker = { pos = nil, since = 0 }
  cavebotAutoRec = false
  lastBlessVisualState = nil
  lastBlessDialogCoreOk = nil
  if cbControlMiniHud then cbControlMiniHud:hide() end
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  if statsWindow then statsWindow:close(true) end
  if helperWindow then helperWindow:hide() end
  if helperButton then helperButton:setOn(false) end
end
