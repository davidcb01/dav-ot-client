-- Keyboard shortcuts, unfocus guard, window/tab controls, spell/item/IDs modals, and i18n

-- KEYBOARD, DELETE GUARD & HOTKEY SYSTEM
-- ============================================================================

KEY_NAMES = {
  [KeyF1] = 'F1', [KeyF2] = 'F2', [KeyF3] = 'F3', [KeyF4] = 'F4',
  [KeyF5] = 'F5', [KeyF6] = 'F6', [KeyF7] = 'F7', [KeyF8] = 'F8',
  [KeyF9] = 'F9', [KeyF10] = 'F10', [KeyF11] = 'F11', [KeyF12] = 'F12',
  [KeyInsert] = 'Insert', [KeyDelete] = 'Delete', [KeyHome] = 'Home',
  [KeyEnd] = 'End', [KeyPageUp] = 'PageUp', [KeyPageDown] = 'PageDown',
  [KeyPause] = 'Pause', [KeySpace] = 'Space', [KeyTab] = 'Tab'
}

boundHelperShortcuts = {}
hookedKeyWidgets = {}

function unbindShortcutKeys()
  for _, entry in ipairs(boundHelperShortcuts) do
    pcall(function()
      if entry.widget and entry.fn then
        g_keyboard.unbindKeyDown(entry.key, entry.fn, entry.widget)
      elseif entry.fn then
        g_keyboard.unbindKeyDown(entry.key, entry.fn)
      end
    end)
  end
  boundHelperShortcuts = {}
  shortcutActions = {}
end

function isChatCurrentlyEnabled()
  if modules and modules.game_console and modules.game_console.isChatEnabled then
    local ok, res = pcall(modules.game_console.isChatEnabled)
    if ok then return res == true end
  end
  return false
end

function isNonTextShortcutKey(keyStr, keyCode, mods)
  local m = tonumber(mods) or (g_keyboard and g_keyboard.getModifiers and g_keyboard.getModifiers()) or 0
  if bit and bit.band then
    local ctrlMask = (KeyboardCtrlModifier or 0) + (KeyboardPrimaryModifier or 0) + (KeyboardAltModifier or 0) + (KeyboardMetaModifier or 0)
    if bit.band(m, ctrlMask) ~= 0 then
      return true
    end
  end
  if keyStr then
    local lower = keyStr:lower()
    if lower:find('ctrl%+') or lower:find('alt%+') or lower:find('cmd%+') or lower:find('meta%+') then
      return true
    end
    local baseLower = lower:match('[^+]+$') or lower
    if baseLower:match('^f%d+$') or baseLower == 'pause' or baseLower == 'insert' or baseLower == 'home' or baseLower == 'end'
       or baseLower == 'pageup' or baseLower == 'pagedown' or baseLower == 'delete' or baseLower == 'printscreen' or baseLower == 'scrolllock' then
      return true
    end
  end
  if keyCode and ((KeyF1 and keyCode >= KeyF1 and KeyF12 and keyCode <= KeyF12)
     or keyCode == KeyPause or keyCode == KeyInsert or keyCode == KeyHome or keyCode == KeyEnd
     or keyCode == KeyPageUp or keyCode == KeyPageDown or keyCode == KeyDelete) then
    return true
  end
  return false
end

function getDeepFocusedWidget()
  local cur = g_ui.getRootWidget()
  while cur and cur.getFocusedChild do
    local nxt = cur:getFocusedChild()
    if not nxt or nxt == cur then break end
    cur = nxt
  end
  return cur
end

function unfocusActiveHelperTextEdit(mousePos)
  local focused = getDeepFocusedWidget()
  if not focused or focused:getClassName() ~= 'UITextEdit' then return end
  if focused.getId and focused:getId() == 'consoleTextEdit' then return end
  if mousePos and focused.containsPoint and focused:containsPoint(mousePos) then return end
  local p = focused.getParent and focused:getParent() or nil
  while p do
    if p.focusChild then
      pcall(function() p:focusChild(nil, MouseFocusReason) end)
    end
    p = p.getParent and p:getParent() or nil
  end
end

function installClickOutsideUnfocus(rootW)
  if not rootW or (rootW.isDestroyed and rootW:isDestroyed()) then return end
  local cls = rootW.getClassName and rootW:getClassName() or ''
  if cls ~= 'UITextEdit' and not rootW._helperUnfocusHooked then
    rootW._helperUnfocusHooked = true
    local prevPress = rootW.onMousePress
    rootW.onMousePress = function(w, mousePos, mouseButton)
      unfocusActiveHelperTextEdit(mousePos)
      if prevPress then
        return prevPress(w, mousePos, mouseButton)
      end
      return false
    end
  end
  if rootW.getChildren then
    for _, ch in ipairs(rootW:getChildren()) do
      installClickOutsideUnfocus(ch)
    end
  end
end

function shouldBlockShortcutForFocusedEdit(keyStr, keyCode, mods)
  local focused = getDeepFocusedWidget()
  if not focused or focused:getClassName() ~= 'UITextEdit' then
    return false
  end

  local isConsoleEdit = (focused.getId and focused:getId() == 'consoleTextEdit')
  if isConsoleEdit then
    if not isChatCurrentlyEnabled() then
      return false
    end
    return not isNonTextShortcutKey(keyStr, keyCode, mods)
  end

  -- Inside Helper/other modal UITextEdit: protect typing, Home/End/Insert/Delete, but allow F-keys/Pause/Ctrl/Alt combos
  local m = tonumber(mods) or (g_keyboard and g_keyboard.getModifiers and g_keyboard.getModifiers()) or 0
  if bit and bit.band then
    local ctrlMask = (KeyboardCtrlModifier or 0) + (KeyboardPrimaryModifier or 0) + (KeyboardAltModifier or 0) + (KeyboardMetaModifier or 0)
    if bit.band(m, ctrlMask) ~= 0 then
      return false
    end
  end
  if keyCode and ((KeyF1 and keyCode >= KeyF1 and KeyF12 and keyCode <= KeyF12) or keyCode == KeyPause) then
    return false
  end
  if keyStr then
    local lower = keyStr:lower()
    local baseLower = lower:match('[^+]+$') or lower
    if lower:find('ctrl%+') or lower:find('alt%+') or baseLower:match('^f%d+$') or baseLower == 'pause' then
      return false
    end
  end
  return true
end

function isTypingInTextEdit()
  return shouldBlockShortcutForFocusedEdit(nil, nil, 0)
end

function normalizeShortcutKey(keyStr)
  if not keyStr or keyStr == '' then return nil end
  local clean = tostring(keyStr):gsub('^%s+', ''):gsub('%s+$', '')
  if clean == '' then return nil end
  if retranslateKeyComboDesc then
    local ok, norm = pcall(retranslateKeyComboDesc, clean)
    if ok and norm and norm ~= '' then
      return norm
    end
  end
  return clean
end

STANDALONE_MODIFIER_DESCS = {
  Ctrl = true, Control = true, Alt = true, Option = true, Shift = true, Meta = true, Win = true, Cmd = true, Super = true
}

function isStandaloneModifierKeyCode(keyCode)
  return keyCode == KeyEscape or keyCode == KeyShift or keyCode == KeyCtrl or keyCode == KeyControl
     or keyCode == KeyCtrlCmd or keyCode == KeyAlt or keyCode == KeyAltOpt or keyCode == KeyMeta
end

function resolvePressedKeyString(keyCode, keyboardModifiers)
  if isStandaloneModifierKeyCode(keyCode) then
    return nil
  end
  if determineKeyComboDesc then
    local ok, desc = pcall(determineKeyComboDesc, keyCode, keyboardModifiers)
    if ok and desc and desc ~= '' and not STANDALONE_MODIFIER_DESCS[desc] then
      return desc
    end
  end
  local base = KEY_NAMES[keyCode]
  if not base and keyCode and keyCode >= 33 and keyCode <= 126 then
    base = string.upper(string.char(keyCode))
  end
  if not base then return nil end
  local prefix = ''
  local mods = tonumber(keyboardModifiers) or 0
  if bit and bit.band then
    local ctrlMask = (KeyboardCtrlModifier or 0) + (KeyboardPrimaryModifier or 0)
    if bit.band(mods, ctrlMask) ~= 0 then prefix = prefix .. 'Ctrl+' end
    if bit.band(mods, KeyboardAltModifier or 0) ~= 0 then prefix = prefix .. 'Alt+' end
    if bit.band(mods, KeyboardShiftModifier or 0) ~= 0 then prefix = prefix .. 'Shift+' end
  end
  return normalizeShortcutKey(prefix .. base) or (prefix .. base)
end

function executeShortcutAction(desc, fn)
  local now = g_clock.millis()
  if desc == lastShortcutDesc and (now - lastShortcutEventTime) < 60 then
    return true
  end
  lastShortcutDesc = desc
  lastShortcutEventTime = now
  fn()
  return true
end

function tryDispatchHelperShortcut(keyCode, keyboardModifiers)
  if keyCaptureModal and keyCaptureModal:isVisible() and activeKeyCaptureSlot then
    return false
  end
  if not g_game.isOnline() then
    return false
  end
  local desc = resolvePressedKeyString(keyCode, keyboardModifiers)
  if not desc or desc == '' then return false end
  local normDesc = normalizeShortcutKey(desc) or desc
  local fn = shortcutActions[normDesc] or shortcutActions[desc]
  if not fn then return false end
  if shouldBlockShortcutForFocusedEdit(normDesc, keyCode, keyboardModifiers) then
    return false
  end
  return executeShortcutAction(normDesc, fn)
end

function attachGlobalKeyHookToWidget(w)
  if not w or (w.isDestroyed and w:isDestroyed()) then return end
  for _, existing in ipairs(hookedKeyWidgets) do
    if existing == w then return end
  end
  connect(w, { onKeyDown = onGlobalKeyDown }, true)
  table.insert(hookedKeyWidgets, w)
end

function detachAllGlobalKeyHooks()
  for _, w in ipairs(hookedKeyWidgets) do
    if w and (not w.isDestroyed or not w:isDestroyed()) then
      pcall(disconnect, w, { onKeyDown = onGlobalKeyDown })
    end
  end
  hookedKeyWidgets = {}
end

function refreshGlobalKeyHooks()
  local gameRoot = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
  local rightPanel = modules.game_interface and modules.game_interface.getRightPanel and modules.game_interface.getRightPanel()
  local leftPanel = modules.game_interface and modules.game_interface.getLeftPanel and modules.game_interface.getLeftPanel()
  local bottomPanel = modules.game_interface and modules.game_interface.getBottomPanel and modules.game_interface.getBottomPanel()
  local consolePanel = modules.game_console and modules.game_console.consolePanel
  local consoleEdit = consolePanel and consolePanel.getChildById and consolePanel:getChildById('consoleTextEdit')
  if not consoleEdit and rootWidget and rootWidget.recursiveGetChildById then
    consoleEdit = rootWidget:recursiveGetChildById('consoleTextEdit')
  end
  if not consolePanel and consoleEdit and consoleEdit.getParent then
    consolePanel = consoleEdit:getParent()
  end
  for _, w in ipairs({ consoleEdit, consolePanel, gameRoot, rightPanel, leftPanel, bottomPanel, rootWidget }) do
    attachGlobalKeyHookToWidget(w)
  end
end

function rebuildShortcutBindings()
  unbindShortcutKeys()
  if not g_game.isOnline() then return end
  refreshGlobalKeyHooks()

  local k = charConfig.keys or {}
  local map = {
    { key = k.masterKey,        fn = function() toggleMaster() end },
    { key = k.healingKey,       fn = function() quickToggleFeature('healing') end },
    { key = k.shooterKey,       fn = function() quickToggleFeature('shooter') end },
    { key = k.targetKey,        fn = function() quickToggleFeature('target') end },
    { key = k.targetShooterKey, fn = function() quickToggleFeature('target_shooter') end },
    { key = k.presetKey,        fn = function() cycleShooterPreset() end },
    { key = k.followKey,        fn = function() quickToggleFeature('follow') end },
    { key = k.cavebotKey,       fn = function() quickToggleFeature('cavebot') end }
  }
  local gameRoot = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
  for _, item in ipairs(map) do
    local normKey = normalizeShortcutKey(item.key)
    if normKey then
      shortcutActions[normKey] = item.fn
      local targets = { rootWidget }
      if gameRoot and gameRoot ~= rootWidget then
        table.insert(targets, gameRoot)
      end
      for _, tgtW in ipairs(targets) do
        local boundCb = function(widget, keyCode, mods)
          if keyCaptureModal and keyCaptureModal:isVisible() and activeKeyCaptureSlot then
            return false
          end
          if not g_game.isOnline() then return false end
          if shouldBlockShortcutForFocusedEdit(normKey, keyCode, mods) then
            return false
          end
          return executeShortcutAction(normKey, item.fn)
        end
        local ok = pcall(g_keyboard.bindKeyDown, normKey, boundCb, tgtW, false)
        if ok then
          table.insert(boundHelperShortcuts, { key = normKey, fn = boundCb, widget = tgtW })
        end
      end
    end
  end
end

function installDeleteNoCloseGuard(win)
  if not win then return end
  local origOnKeyDown = win.onKeyDown
  win.onKeyDown = function(w, keyCode, mods)
    if tryDispatchHelperShortcut(keyCode, mods) then
      return true
    end
    if keyCode == KeyDelete and (mods == nil or mods == 0) then
      if isTypingInTextEdit() then
        return false
      end
      return true
    end
    if origOnKeyDown then
      return origOnKeyDown(w, keyCode, mods)
    end
    return false
  end
end

function openKeyCapture(slotKey, btnWidget)
  activeKeyCaptureSlot = slotKey
  activeKeyCaptureBtn = btnWidget
  local cur = (charConfig.keys and charConfig.keys[slotKey]) or ''
  if cur == '' then cur = 'None' end
  keyCaptureModal:getChildById('currentKeyLabel'):setText('Current: ' .. cur)
  keyCaptureModal:show()
  keyCaptureModal:raise()
  keyCaptureModal:focus()
  if keyCaptureModal.grabKeyboard then pcall(function() keyCaptureModal:grabKeyboard() end) end
end

function closeKeyCapture()
  activeKeyCaptureSlot = nil
  activeKeyCaptureBtn = nil
  if keyCaptureModal then
    if keyCaptureModal.ungrabKeyboard then pcall(function() keyCaptureModal:ungrabKeyboard() end) end
    keyCaptureModal:hide()
  end
end

function onGlobalKeyDown(widget, keyCode, keyboardModifiers)
  if keyCaptureModal and keyCaptureModal:isVisible() and activeKeyCaptureSlot then
    return keyCaptureModal.onKeyDown(keyCaptureModal, keyCode, keyboardModifiers)
  end
  if tryDispatchHelperShortcut(keyCode, keyboardModifiers) then
    return true
  end
  return false
end

function updateKeyButtonsUI()
  local k = charConfig.keys or {}
  local setKeyLabel = ht('Set Key')
  local function fmtKey(val)
    if val and val ~= '' then return setKeyLabel .. ' [' .. val .. ']' end
    return setKeyLabel
  end
  helperWindow:getChildById('bottomBar'):getChildById('setHelperKeyBtn'):setText(fmtKey(k.masterKey))
  panels.healing:getChildById('selfHealingContainer'):getChildById('extraHealingBox'):getChildById('healingSetKeyBtn'):setText(fmtKey(k.healingKey))
  panels.tools:getChildById('rightToolsCol'):getChildById('followBox'):getChildById('followSetKeyBtn'):setText(fmtKey(k.followKey))
  local sBody = panels.shooter:getChildById('bodyPanel')
  local sGlob = sBody:getChildById('shooterGlobalBox')
  sGlob:getChildById('shooterSetKeyBtn'):setText(fmtKey(k.shooterKey))
  sBody:getChildById('presetsBox'):getChildById('presetSetKeyBtn'):setText(fmtKey(k.presetKey))
  local tTop = panels.target:getChildById('targetTopBox')
  tTop:getChildById('targetSetKeyBtn'):setText(fmtKey(k.targetKey))
  panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox'):getChildById('cavebotSetKeyBtn'):setText(fmtKey(k.cavebotKey))
end

-- ============================================================================
-- TAB BAR, WINDOW & DAVHUD SHORTCUTS STATUS
-- ============================================================================

function updateHelperButtonIcon(isOpen)
  if not helperButton then return end
  local iconPath = isOpen and '/mods/game_helper/images/custom/helper_open' or '/mods/game_helper/images/custom/helper_closed'
  if helperButton.setImageSource then
    pcall(function() helperButton:setImageSource(iconPath) end)
  elseif helperButton.setIcon then
    pcall(function() helperButton:setIcon(iconPath) end)
  end
end

function setupTabIcons()
  local tabBar = helperWindow:getChildById('tabBar')
  local defs = {
    { id = 'tabHealing',  title = ht('HEALING'),  img = '/mods/game_helper/images/custom/tab_healing' },
    { id = 'tabTools',    title = ht('TOOLS'),    img = '/mods/game_helper/images/custom/tab_tools' },
    { id = 'tabShooter',  title = ht('SHOOTER'),  img = '/mods/game_helper/images/custom/tab_shooter' },
    { id = 'tabTarget',   title = ht('TARGET'),   img = '/mods/game_helper/images/custom/tab_target' },
    { id = 'tabCavebot',  title = ht('CAVEBOT'),  img = '/mods/game_helper/images/custom/tab_cavebot' },
    { id = 'tabSettings', title = ht('SETTINGS'), img = '/mods/game_helper/images/custom/tab_settings' }
  }
  for _, d in ipairs(defs) do
    local btn = tabBar:getChildById(d.id)
    if btn then
      local icon = btn:getChildById('tabIcon')
      local lbl = btn:getChildById('tabLabel')
      if icon then icon:setImageSource(d.img) end
      if lbl then
        lbl:setText(d.title)
        lbl:setVisible(true)
      end
    end
  end
end

function switchTab(tabName)
  currentTab = tabName
  local tabBar = helperWindow:getChildById('tabBar')
  local idMap = {
    healing = 'tabHealing',
    tools = 'tabTools',
    shooter = 'tabShooter',
    target = 'tabTarget',
    cavebot = 'tabCavebot',
    settings = 'tabSettings'
  }
  for k, id in pairs(idMap) do
    local btn = tabBar:getChildById(id)
    if btn then
      btn:setOn(k == tabName)
      local lbl = btn:getChildById('tabLabel')
      if lbl then
        lbl:setVisible(true)
        lbl:setColor(k == tabName and '#ffdd66' or '#dcdcdc')
      end
    end
  end
  for k, panel in pairs(panels) do
    if panel then
      panel:setVisible(k == tabName)
    end
  end
  if tabName == 'tools' then
    scanExerciseAssets(false)
  elseif tabName == 'cavebot' then
    centerCavebotMinimap()
    renderCavebotWaypointsOnMaps()
  elseif tabName == 'settings' and refreshSettingsTabUI then
    refreshSettingsTabUI()
  end
end


function updateMasterBarUI()
  local bar = helperWindow:getChildById('bottomBar')
  local val = bar:getChildById('statusValueLabel')
  local icon = bar:getChildById('statusIcon')
  local btn = bar:getChildById('masterToggleBtn')
  local on = charConfig.masterEnabled
  val:setText(on and ht('Enabled') or ht('Disabled'))
  val:setColor(on and '#22ee22' or '#ee4444')
  icon:setImageSource(on and '/images/ui/icon-yes' or '/images/ui/createaccount/icon-no')
  btn:setText(on and ht('On') or ht('Off'))
  btn:setOn(on and true or false)
end

function updateStatsUI()
  if not statsWindow then return end
  local c = statsWindow:getChildById('contentsPanel')
  local vp = getVocProfile()
  local mOn = charConfig.masterEnabled
  local vocLbl = c:getChildById('vocLabel')
  if vocLbl then vocLbl:setText(ht('Voc:') .. ' ' .. (currentVocName or ht('Unknown'))) end

  local function setStatBtn(id, label, active)
    local b = c:getChildById(id)
    if not b then return end
    local on = mOn and active
    b:setText(ht(label) .. ': ' .. (on and 'ON' or 'OFF'))
    b:setOn(on and true or false)
  end
  setStatBtn('statHealBtn', 'Healing', vp.healing.enabled)
  setStatBtn('statShooterBtn', 'DAVCaster', vp.shooter.enabled)
  setStatBtn('statTargetBtn', 'Auto Target', vp.target.enabled)
  setStatBtn('statCavebotBtn', 'Cavebot', charConfig.cavebot.enabled)
end

function toggle()
  if not g_game.isOnline() or not helperWindow then return end
  if helperWindow:isVisible() then
    hide()
  else
    show()
  end
end

function show()
  if not g_game.isOnline() or not helperWindow then return end
  helperWindow:show()
  helperWindow:raise()
  helperWindow:focus()
  if helperButton then
    helperButton:setOn(true)
    updateHelperButtonIcon(true)
  end
  if charConfig.windowPos and charConfig.windowPos.x and charConfig.windowPos.y then
    helperWindow:setPosition(charConfig.windowPos)
  end
  applyVocationVisibility()
  if currentTab == 'cavebot' then
    centerCavebotMinimap()
    renderCavebotWaypointsOnMaps()
  end
end

function hide()
  if helperWindow then helperWindow:hide() end
  if helperButton then
    helperButton:setOn(false)
    updateHelperButtonIcon(false)
  end
end

function toggleStatsWindow()
  if not g_game.isOnline() or not statsWindow then return end
  if statsWindow:isVisible() then
    statsWindow:close()
  else
    statsWindow:open()
  end
end

function toggleMaster()
  charConfig.masterEnabled = not charConfig.masterEnabled
  updateMasterBarUI()
  updateStatsUI()
  saveCurrentProfile()
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage(htf('[DAVCaster] Helper %s', ht(charConfig.masterEnabled and 'ENABLED' or 'DISABLED')))
  end
end

-- ============================================================================
-- VISUAL SLOT HELPERS (Spells & Items + Drag-and-Drop)
-- ============================================================================

function renderSpellSlot(slotWidget, spellEntry)
  if not slotWidget then return end
  local icon = slotWidget:getChildById('icon')
  if not icon then return end
  if spellEntry and spellEntry.words and spellEntry.words ~= '' then
    local spData = findSpellByWords(spellEntry.words)
    local cid = (spData and spData.clientId and spData.clientId > 0 and spData.clientId)
      or (tonumber(spellEntry.clientId) and tonumber(spellEntry.clientId) > 0 and tonumber(spellEntry.clientId))
      or 1
    spellEntry.clientId = cid
    if spData and spData.name and (not spellEntry.name or spellEntry.name == '') then
      spellEntry.name = spData.name
    end
    icon:setImageSource('/images/game/spells/spell-icons-32x32')
    icon:setImageClip(getSpellClip(cid))
    icon:setVisible(true)
    slotWidget:setTooltip(htf('%s (%s)\nLeft-click to select | Right-click to clear', (spData and spData.name) or spellEntry.name or spellEntry.words, spellEntry.words))
  else
    icon:setImageSource('')
    icon:setVisible(false)
    slotWidget:setTooltip(ht('Empty Spell Slot\nLeft-click to select spell'))
  end
end

function setVirtualUIItem(itemW, itemId)
  if not itemW then return end
  local id = tonumber(itemId) or 0
  if id > 0 then
    local itemObj = Item and Item.create and Item.create(id, 1) or nil
    if itemObj and itemW.setItem then
      itemW:setItem(itemObj)
    else
      itemW:setItemId(id)
    end
    itemW:setVisible(true)
  else
    if itemW.setItem then itemW:setItem(nil) end
    itemW:setItemId(0)
    itemW:setVisible(false)
  end
end

function renderItemSlot(slotWidget, itemId)
  if not slotWidget then return end
  local itemW = slotWidget:getChildById('item')
  if not itemW then return end
  local id = tonumber(itemId) or 0
  if id > 0 then
    setVirtualUIItem(itemW, id)
    local info = findItemInCatalog(id)
    slotWidget:setTooltip(htf('%s (ID: %d)\nClick or Drop Item from BP | Right-click to clear', info and info.name or ('Item #' .. id), id))
  else
    setVirtualUIItem(itemW, 0)
    slotWidget:setTooltip(ht('Empty Item Slot\nClick to choose OR Drop Item from BP'))
  end
end

function renderPotionTypeBar(barWidget, ptype)
  if not barWidget then return end
  local c1, c2, c3 = '#444444', '#444444', '#444444'
  if ptype == 'mp' then
    c1, c2, c3 = '#2b78e4', '#2b78e4', '#2b78e4'
  elseif ptype == 'hp' then
    c1, c2, c3 = '#cc3333', '#cc3333', '#cc3333'
  elseif ptype == 'spirit' then
    c1, c2, c3 = '#cc3333', '#9944cc', '#2b78e4'
  end
  local b1 = barWidget:getChildById('bar1')
  local b2 = barWidget:getChildById('bar2')
  local b3 = barWidget:getChildById('bar3')
  if b1 then b1:setBackgroundColor(c1) end
  if b2 then b2:setBackgroundColor(c2) end
  if b3 then b3:setBackgroundColor(c3) end
end

function bindSlotClicks(slotWidget, onLeftClick, onRightClear)
  if not slotWidget then return end
  slotWidget.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      onLeftClick()
      return true
    elseif mouseButton == MouseRightButton then
      onRightClear()
      saveCurrentProfile()
      return true
    end
    return false
  end
end

function attachItemDropHandler(slotWidget, onItemIdDropped)
  if not slotWidget then return end
  slotWidget.onDrop = function(widget, droppedWidget, mousePos)
    if droppedWidget and droppedWidget.getItem then
      local it = droppedWidget:getItem()
      if it and it.getId then
        local id = tonumber(it:getId()) or 0
        if id > 0 then
          onItemIdDropped(id)
          saveCurrentProfile()
          return true
        end
      end
    end
    return false
  end
end

-- ============================================================================
-- SPELL & ITEM SELECTOR MODALS (Strict Vocation Filter + Reliable OK/Apply)
-- ============================================================================

COMBAT_SUPPORT_WORDS = {
  ['utito tempo'] = true, ['utito tempo san'] = true, ['utamo tempo'] = true,
  ['exeta res'] = true, ['exeta amp res'] = true, ['exana amp res'] = true,
  ['uteta res eq'] = true, ['uteta res sac'] = true, ['uteta res ven'] = true,
  ['uteta res dru'] = true, ['uteta res nia'] = true, ['utamo nia'] = true,
  ['utito nia'] = true, ['utevo nia'] = true, ['exeta pug'] = true,
  ['utito virtu'] = true, ['utori virtu'] = true, ['exori mas res'] = true
}
local HASTE_WORDS = { ['utani hur'] = true, ['utani gran hur'] = true, ['utani tempo hur'] = true, ['utamo tempo san'] = true }
local MANASHIELD_WORDS = { ['utamo vita'] = true, ['exana vita'] = true, ['utamo tempo'] = true, ['utamo tempo nia'] = true, ['utamo tio'] = true }
local RECOVERY_WORDS = { ['utura'] = true, ['utura gran'] = true, ['utura nia'] = true, ['utura tio'] = true }
local PARTY_WORDS = { ['exura sio'] = true, ['exura gran sio'] = true, ['exura gran mas res'] = true, ['exura mas res'] = true, ['exura tio sio'] = true, ['exura mas nia'] = true }

function openSpellSelector(title, groupFilter, currentSpell, onSelectCallback)
  activeSpellSlotCallback = onSelectCallback
  activeSpellFilterGroup = groupFilter
  activeSpellSlotSelected = currentSpell and deepCopy(currentSpell) or nil

  spellSelectorModal:setText(title or 'Select Spell')
  local searchEdit = spellSelectorModal:getChildById('searchEdit')
  local paramEdit = spellSelectorModal:getChildById('paramEdit')
  if searchEdit then searchEdit:setText('') end
  if paramEdit then paramEdit:setText((currentSpell and currentSpell.param) or '') end

  populateSpellSelectorList()
  spellSelectorModal:show()
  spellSelectorModal:raise()
  spellSelectorModal:focus()
end

function populateSpellSelectorList()
  if not spellSelectorModal then return end
  local list = spellSelectorModal:getChildById('spellList')
  local searchEdit = spellSelectorModal:getChildById('searchEdit')
  local filterPanel = spellSelectorModal:getChildById('filterPanel')
  local onlyVocCheck = filterPanel and filterPanel:getChildById('onlyVocationCheck')
  if not list then return end

  list:destroyChildren()
  local filterText = searchEdit and searchEdit:getText():lower() or ''
  local onlyVoc = onlyVocCheck and onlyVocCheck:isChecked()
  local vocMatches = getVocMatchTable(currentVocName)

  local allSpells = {}
  local seenWords = {}

  local function addCandidate(spName, spData)
    if not spData or not spData.words then return end
    local wKey = spData.words:lower()
    if seenWords[wKey] then return end
    if wKey:sub(1, 1) == '#' or wKey:sub(1, 5) == 'aleta' then return end

    local grp = 1
    if spData.group then
      for gId, _ in pairs(spData.group) do
        grp = gId
        break
      end
    end

    local fGroup = activeSpellFilterGroup
    if fGroup == 2 or fGroup == 'healing' then
      if spData.type == 'Conjure' or grp ~= 2 then return end
      if PARTY_WORDS[wKey] and currentVocName ~= 'Druid' and currentVocName ~= 'Monk' then return end
    elseif fGroup == 1 or fGroup == 'attack' then
      if spData.type == 'Conjure' then return end
      if grp ~= 1 and not COMBAT_SUPPORT_WORDS[wKey] then return end
    elseif fGroup == 'haste' then
      if not HASTE_WORDS[wKey] then return end
    elseif fGroup == 'manashield' then
      if not MANASHIELD_WORDS[wKey] then return end
    elseif fGroup == 'party' then
      if not PARTY_WORDS[wKey] then return end
    elseif fGroup == 'recovery' then
      if not RECOVERY_WORDS[wKey] then return end
    elseif fGroup == 3 or fGroup == 'support' then
      if spData.type == 'Conjure' or grp ~= 3 then return end
    end

    if onlyVoc and spData.vocations then
      local matched = false
      for _, vId in ipairs(spData.vocations) do
        if vocMatches[vId] then matched = true break end
      end
      if not matched then return end
    end

    local displayName = spData.name or spName or spData.words
    if filterText ~= '' then
      if not displayName:lower():find(filterText, 1, true) and not wKey:find(filterText, 1, true) then
        return
      end
    end

    seenWords[wKey] = true
    local cid = SPELL_CLIENTID_OVERRIDES[wKey] or tonumber(spData.clientId) or 1
    if cid <= 0 then cid = math.max(1, tonumber(spData.id) or 1) end

    table.insert(allSpells, {
      name = displayName,
      words = spData.words,
      clientId = cid,
      level = tonumber(spData.level) or 1,
      group = grp,
      parameter = spData.parameter
    })
  end

  if SpellInfo and SpellInfo['Default'] then
    for sName, sData in pairs(SpellInfo['Default']) do
      addCandidate(sName, sData)
    end
  end
  for _, ex in ipairs(EXTRA_SPELLS) do
    addCandidate(ex.name, ex)
  end

  table.sort(allSpells, function(a, b) return a.name:lower() < b.name:lower() end)

  local firstRow = nil
  for _, sp in ipairs(allSpells) do
    local row = g_ui.createWidget('SpellSelectorRow', list)
    if not firstRow then firstRow = row end
    local iconFrame = row:getChildById('iconFrame')
    local icon = (iconFrame and iconFrame:getChildById('spellIcon')) or row:recursiveGetChildById('spellIcon')
    local nameLbl = row:getChildById('spellNameLabel')
    local wordsLbl = row:getChildById('spellWordsLabel')
    local grpIcon = row:getChildById('groupIcon')
    local lvlLbl = row:getChildById('levelLabel')

    if icon then
      icon:setImageSource('/images/game/spells/spell-icons-32x32')
      icon:setImageClip(getSpellClip(sp.clientId))
    end
    if nameLbl then nameLbl:setText(sp.name) end
    if wordsLbl then wordsLbl:setText(sp.words) end
    if grpIcon then
      local grpX = math.max(0, math.min(60, (sp.group - 1) * 20))
      grpIcon:setImageClip(grpX .. ' 0 20 20')
    end
    if lvlLbl then lvlLbl:setText('Level: ' .. tostring(sp.level)) end

    row.spellData = sp
    row.onClick = function(w)
      activeSpellSlotSelected = w.spellData
      list:focusChild(w, MouseFocusReason)
    end
    row.onFocusChange = function(w, focused)
      if focused then
        activeSpellSlotSelected = w.spellData
      end
    end
    row.onDoubleClick = function(w)
      activeSpellSlotSelected = w.spellData
      confirmSpellSelection(true)
    end
  end

  if firstRow and (not activeSpellSlotSelected or not activeSpellSlotSelected.words) then
    activeSpellSlotSelected = firstRow.spellData
  end
end

function confirmSpellSelection(closeModal)
  if activeSpellSlotSelected and activeSpellSlotCallback then
    local paramEdit = spellSelectorModal:getChildById('paramEdit')
    local param = paramEdit and paramEdit:getText() or ''
    local chosen = deepCopy(activeSpellSlotSelected)
    if param ~= '' then
      chosen.words = chosen.words .. ' "' .. param
      chosen.param = param
    end
    activeSpellSlotCallback(chosen)
    saveCurrentProfile()
  end
  if closeModal and spellSelectorModal then
    spellSelectorModal:hide()
  end
end

function openItemSelector(title, categoryFilter, currentItemId, onSelectCallback)
  activeItemSlotCallback = onSelectCallback
  activeItemCategoryFilter = categoryFilter
  activeItemSlotSelected = findItemInCatalog(currentItemId)

  itemSelectorModal:setText(title or 'Select Item')
  local searchEdit = itemSelectorModal:getChildById('searchEdit')
  local customIdEdit = itemSelectorModal:getChildById('customIdEdit')
  if searchEdit then searchEdit:setText('') end
  if customIdEdit then customIdEdit:setText((currentItemId and currentItemId > 0) and tostring(currentItemId) or '') end

  populateItemSelectorList()
  itemSelectorModal:show()
  itemSelectorModal:raise()
  itemSelectorModal:focus()
end

function populateItemSelectorList()
  if not itemSelectorModal then return end
  local list = itemSelectorModal:getChildById('itemList')
  local searchEdit = itemSelectorModal:getChildById('searchEdit')
  if not list then return end

  list:destroyChildren()
  local filterText = searchEdit and searchEdit:getText():lower() or ''

  for _, it in ipairs(ITEM_CATALOG) do
    local catOk = (not activeItemCategoryFilter) or (activeItemCategoryFilter == 'all') or (it.cat == activeItemCategoryFilter)
    local textOk = (filterText == '') or it.name:lower():find(filterText, 1, true) or tostring(it.id):find(filterText, 1, true)
    if catOk and textOk then
      local row = g_ui.createWidget('ItemSelectorRow', list)
      local itemIcon = row:recursiveGetChildById('itemIcon')
      local nameLbl = row:getChildById('itemNameLabel')
      local descLbl = row:getChildById('itemDescLabel')
      local idLbl = row:getChildById('idLabel')

      if itemIcon then setVirtualUIItem(itemIcon, it.id) end
      if nameLbl then nameLbl:setText(it.name) end
      if descLbl then descLbl:setText(it.desc or '') end
      if idLbl then idLbl:setText('ID: ' .. tostring(it.id)) end

      row.itemData = it
      row.onClick = function(w)
        activeItemSlotSelected = w.itemData
        local customIdEdit = itemSelectorModal:getChildById('customIdEdit')
        if customIdEdit then customIdEdit:setText(tostring(w.itemData.id)) end
        list:focusChild(w, MouseFocusReason)
      end
      row.onFocusChange = function(w, focused)
        if focused then
          activeItemSlotSelected = w.itemData
          local customIdEdit = itemSelectorModal:getChildById('customIdEdit')
          if customIdEdit then customIdEdit:setText(tostring(w.itemData.id)) end
        end
      end
      row.onDoubleClick = function(w)
        activeItemSlotSelected = w.itemData
        confirmItemSelection()
      end
    end
  end
end

function confirmItemSelection()
  local customIdEdit = itemSelectorModal:getChildById('customIdEdit')
  local customId = customIdEdit and tonumber(customIdEdit:getText()) or 0
  local chosen = activeItemSlotSelected
  if customId and customId > 100 and (not chosen or chosen.id ~= customId) then
    chosen = findItemInCatalog(customId)
  end
  if chosen and activeItemSlotCallback then
    activeItemSlotCallback(chosen)
    saveCurrentProfile()
  end
  if itemSelectorModal then
    itemSelectorModal:hide()
  end
end

-- ============================================================================

function isClickInsideAnyChild(parent, childNames, mousePos)
  if not mousePos then return false end
  for _, cid in ipairs(childNames) do
    local c = parent:getChildById(cid)
    if c and c:isVisible() and c:containsPoint(mousePos) then
      return true
    end
  end
  return false
end

function bindDeleteButton(btn, fn)
  if not btn then return end
  if btn.setFocusable then btn:setFocusable(false) end
  if btn.setPhantom then btn:setPhantom(false) end
  btn.onClick = function(w)
    fn(w)
  end
end


function refreshIdsMenuList()
  if not idsMenuModal then return end
  local list = idsMenuModal:getChildById('idsList')
  list:destroyChildren()
  idsMenuModal:getChildById('followSubRow'):setVisible(activeIdsTab == 'follow')

  if activeIdsTab == 'follow' then
    local cats = { stairs = 'fCatStairs', rope = 'fCatRope', use = 'fCatUse', teleport = 'fCatTeleport', avoid = 'fCatAvoid' }
    local fRow = idsMenuModal:getChildById('followSubRow')
    for c, bId in pairs(cats) do
      local b = fRow:getChildById(bId)
      if b then b:setColor(c == activeFollowIdCat and '#5ce65c' or '#dfdfdf') end
    end
    local arr = charConfig.customIds.follow[activeFollowIdCat] or {}
    for idx, idVal in ipairs(arr) do
      local row = g_ui.createWidget('IdsMenuRow', list)
      local icon = row:getChildById('idItemIcon')
      if icon then icon:setItemId(tonumber(idVal) or 0) end
      row:getChildById('idLabel'):setText(string.format('ID: %d (%s)', tonumber(idVal) or 0, activeFollowIdCat))
      bindDeleteButton(row:getChildById('idDelBtn'), function()
        table.remove(arr, idx)
        refreshIdsMenuList()
        saveCurrentProfile()
      end)
    end
  elseif activeIdsTab == 'dummys' then
    for k, name in pairs(EXERCISE_DUMMY_CATALOG) do
      local row = g_ui.createWidget('IdsMenuRow', list)
      row:getChildById('idItemIcon'):setItemId(k)
      row:getChildById('idLabel'):setText(string.format('%d - %s (built-in)', k, name))
      row:getChildById('idDelBtn'):setVisible(false)
    end
    for kStr, name in pairs(charConfig.customIds.dummys or {}) do
      local row = g_ui.createWidget('IdsMenuRow', list)
      row:getChildById('idItemIcon'):setItemId(tonumber(kStr) or 0)
      row:getChildById('idLabel'):setText(string.format('%s - %s (custom)', kStr, name))
      bindDeleteButton(row:getChildById('idDelBtn'), function()
        charConfig.customIds.dummys[kStr] = nil
        refreshIdsMenuList()
        saveCurrentProfile()
      end)
    end
  elseif activeIdsTab == 'weapons' then
    for k, name in pairs(EXERCISE_WEAPON_CATALOG) do
      local row = g_ui.createWidget('IdsMenuRow', list)
      row:getChildById('idItemIcon'):setItemId(k)
      row:getChildById('idLabel'):setText(string.format('%d - %s (built-in)', k, name))
      row:getChildById('idDelBtn'):setVisible(false)
    end
    for kStr, name in pairs(charConfig.customIds.weapons or {}) do
      local row = g_ui.createWidget('IdsMenuRow', list)
      row:getChildById('idItemIcon'):setItemId(tonumber(kStr) or 0)
      row:getChildById('idLabel'):setText(string.format('%s - %s (custom)', kStr, name))
      bindDeleteButton(row:getChildById('idDelBtn'), function()
        charConfig.customIds.weapons[kStr] = nil
        refreshIdsMenuList()
        saveCurrentProfile()
      end)
    end
  end
end

function switchIdsMenuTab(tab)
  activeIdsTab = tab or 'follow'
  if idsMenuModal then
    local top = idsMenuModal:getChildById('idsTopTabs')
    top:getChildById('idsTabFollow'):setColor(activeIdsTab == 'follow' and '#ffdd66' or '#dfdfdf')
    top:getChildById('idsTabDummys'):setColor(activeIdsTab == 'dummys' and '#ffdd66' or '#dfdfdf')
    top:getChildById('idsTabWeapons'):setColor(activeIdsTab == 'weapons' and '#ffdd66' or '#dfdfdf')
  end
  refreshIdsMenuList()
end

function switchFollowIdCategory(cat)
  activeFollowIdCat = cat or 'stairs'
  refreshIdsMenuList()
end

function addCustomIdFromModal()
  if not idsMenuModal then return end
  local row = idsMenuModal:getChildById('addIdRow')
  local num = tonumber(row:getChildById('addIdEdit'):getText())
  if not num or num <= 0 then return end
  local lbl = row:getChildById('addIdNameEdit'):getText()
  if not lbl or lbl == '' then lbl = 'Custom ID ' .. num end

  if activeIdsTab == 'follow' then
    local arr = charConfig.customIds.follow[activeFollowIdCat]
    local exists = false
    for _, v in ipairs(arr) do if tonumber(v) == num then exists = true break end end
    if not exists then table.insert(arr, num) end
    if activeFollowIdCat == 'stairs' or activeFollowIdCat == 'teleport' then
      charConfig.customIds.follow.avoid = charConfig.customIds.follow.avoid or {}
      local avoidArr = charConfig.customIds.follow.avoid
      local avoidExists = false
      for _, v in ipairs(avoidArr) do if tonumber(v) == num then avoidExists = true break end end
      if not avoidExists then table.insert(avoidArr, num) end
    end
  elseif activeIdsTab == 'dummys' then
    charConfig.customIds.dummys[tostring(num)] = lbl
    scanExerciseAssets(false)
  elseif activeIdsTab == 'weapons' then
    charConfig.customIds.weapons[tostring(num)] = lbl
    scanExerciseAssets(false)
  end
  row:getChildById('addIdEdit'):setText('')
  row:getChildById('addIdNameEdit'):setText('')
  refreshIdsMenuList()
  saveCurrentProfile()
end

function openIdsMenu()
  if not idsMenuModal then return end
  switchIdsMenuTab(activeIdsTab)
  idsMenuModal:show()
  idsMenuModal:raise()
  idsMenuModal:focus()
end

function closeIdsMenu()
  if idsMenuModal then idsMenuModal:hide() end
  saveCurrentProfile()
end

-- ============================================================================
-- QUICK TOGGLES & UI PROFILE HYDRATION
-- ============================================================================

function quickToggleFeature(feat)
  local vp = getVocProfile()
  local msg = ''
  if feat == 'healing' then
    vp.healing.enabled = not (vp.healing.enabled == true)
    panels.healing:getChildById('selfHealingContainer'):getChildById('extraHealingBox'):getChildById('enableHealingCheck'):setChecked(vp.healing.enabled, true)
    msg = 'Auto Healing: ' .. (vp.healing.enabled and 'ON' or 'OFF')
  elseif feat == 'shooter' then
    vp.shooter.enabled = not (vp.shooter.enabled == true)
    panels.shooter:getChildById('bodyPanel'):getChildById('shooterGlobalBox'):getChildById('enableShooterCheck'):setChecked(vp.shooter.enabled, true)
    msg = 'DAVCaster Shooter: ' .. (vp.shooter.enabled and 'ON' or 'OFF')
  elseif feat == 'target' then
    vp.target.enabled = not (vp.target.enabled == true)
    if panels.target then
      panels.target:getChildById('targetTopBox'):getChildById('targetEnableCheck'):setChecked(vp.target.enabled, true)
    end
    msg = 'Auto Target: ' .. (vp.target.enabled and 'ON' or 'OFF')
  elseif feat == 'target_shooter' then
    local nextState = not ((vp.shooter.enabled == true) and (vp.target.enabled == true))
    vp.shooter.enabled = nextState
    vp.target.enabled = nextState
    local sg = panels.shooter:getChildById('bodyPanel'):getChildById('shooterGlobalBox')
    sg:getChildById('enableShooterCheck'):setChecked(nextState, true)
    if panels.target then
      panels.target:getChildById('targetTopBox'):getChildById('targetEnableCheck'):setChecked(nextState, true)
    end
    msg = 'Target & Shooter: ' .. (nextState and 'ON' or 'OFF')
  elseif feat == 'follow' then
    charConfig.tools.follow.enabled = not (charConfig.tools.follow.enabled == true)
    panels.tools:getChildById('rightToolsCol'):getChildById('followBox'):getChildById('followEnableCheck'):setChecked(charConfig.tools.follow.enabled, true)
    msg = 'Follow: ' .. (charConfig.tools.follow.enabled and 'ON' or 'OFF')
  elseif feat == 'cavebot' then
    charConfig.cavebot.enabled = not (charConfig.cavebot.enabled == true)
    if charConfig.cavebot.enabled and charConfig.cavebot.startNearest then
      selectNearestCavebotWaypoint()
    end
    panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox'):getChildById('enableCavebotCheck'):setChecked(charConfig.cavebot.enabled, true)
    refreshCavebotUI()
    msg = 'Cavebot: ' .. (charConfig.cavebot.enabled and 'ON' or 'OFF')
  end
  updateStatsUI()
  saveCurrentProfile()
  if modules.game_textmessage and msg ~= '' then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] ' .. msg)
  end
end

function getComboOptionData(cb, fallback)
  if not cb then return fallback end
  local opt = cb.getCurrentOption and cb:getCurrentOption() or nil
  if opt and opt.data ~= nil then return opt.data end
  if opt and opt.text ~= nil then return opt.text end
  return fallback
end

function populateTranslatedCombos()
  local prevShooter = refreshingShooterUI
  local prevTarget = refreshingTargetUI
  refreshingShooterUI = true
  refreshingTargetUI = true

  -- Tools: Follow mode
  if panels.tools then
    local fBox = panels.tools:getChildById('rightToolsCol'):getChildById('followBox')
    local fModeCb = fBox and fBox:getChildById('followModeCombo')
    if fModeCb and fModeCb.clearOptions then
      fModeCb:clearOptions()
      for _, opt in ipairs({ 'Default', 'Front', 'Back', 'Left', 'Right' }) do
        fModeCb:addOption(ht(opt), opt)
      end
      local curMode = (charConfig and charConfig.tools and charConfig.tools.follow and charConfig.tools.follow.mode) or 'Default'
      fModeCb:setCurrentOptionByData(curMode, true)
    end
    local fDistCb = fBox and fBox:getChildById('followDistCombo')
    if fDistCb and fDistCb.clearOptions then
      fDistCb:clearOptions()
      for _, dOpt in ipairs({ 1, 2, 3, 4 }) do
        fDistCb:addOption(tostring(dOpt), dOpt)
      end
      local curDist = math.max(1, math.min(4, tonumber(charConfig and charConfig.tools and charConfig.tools.follow and charConfig.tools.follow.dist) or 1))
      fDistCb:setCurrentOptionByData(curDist, true)
    end
  end

  -- Shooter: ruleTypeCombo, rulePriorityCombo
  if panels.shooter then
    local ed = panels.shooter:getChildById('bodyPanel'):getChildById('shooterEditorBox')
    if ed then
      local vp = getVocProfile()
      local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
      local r = selectedShooterRuleIdx and rules[selectedShooterRuleIdx] or nil

      local ruleTypeCb = ed:getChildById('ruleTypeCombo')
      if ruleTypeCb and ruleTypeCb.clearOptions then
        ruleTypeCb:clearOptions()
        for _, opt in ipairs({ 'Spell', 'Rune' }) do
          ruleTypeCb:addOption(ht(opt), opt)
        end
        ruleTypeCb:setCurrentOptionByData((r and r.type == 'R') and 'Rune' or 'Spell', true)
      end

      local rulePrioCb = ed:getChildById('rulePriorityCombo')
      if rulePrioCb and rulePrioCb.clearOptions then
        rulePrioCb:clearOptions()
        for _, opt in ipairs({ 'All Monsters', 'Target Name' }) do
          rulePrioCb:addOption(ht(opt), opt)
        end
        local prio = (r and r.priority == 'Target Name') and 'Target Name' or 'All Monsters'
        rulePrioCb:setCurrentOptionByData(prio, true)
      end
    end
  end

  -- Target: targetChaseCombo, tgtFilterCombo, tgtModeCombo
  if panels.target then
    local vp = getVocProfile()
    local tTop = panels.target:getChildById('targetTopBox')
    local tChaseCb = tTop and tTop:getChildById('targetChaseCombo')
    if tChaseCb and tChaseCb.clearOptions then
      tChaseCb:clearOptions()
      for _, opt in ipairs({ 'Stand', 'Chase' }) do
        tChaseCb:addOption(ht(opt), opt)
      end
      tChaseCb:setCurrentOptionByData((vp.target and vp.target.chase) and 'Chase' or 'Stand', true)
    end

    local tEd = panels.target:getChildById('targetEditorBox')
    local tgtRules = vp.target.rules or {}
    local tr = selectedTargetRuleIdx and tgtRules[selectedTargetRuleIdx] or nil
    local isAll = (not tr) or ((tr.allMonsters ~= false) and ((tr.name or '') == ''))

    local tgtFilterCb = tEd and tEd:getChildById('tgtFilterCombo')
    if tgtFilterCb and tgtFilterCb.clearOptions then
      tgtFilterCb:clearOptions()
      for _, opt in ipairs({ 'All Monsters', 'Target Name' }) do
        tgtFilterCb:addOption(ht(opt), opt)
      end
      tgtFilterCb:setCurrentOptionByData(isAll and 'All Monsters' or 'Target Name', true)
    end

    local tgtModeCb = tEd and tEd:getChildById('tgtModeCombo')
    if tgtModeCb and tgtModeCb.clearOptions then
      tgtModeCb:clearOptions()
      for _, opt in ipairs({ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I' }) do
        tgtModeCb:addOption(opt, opt)
      end
      local curM = (tr and tr.mode and tr.mode:match('^[A-I]$')) and tr.mode or 'A'
      tgtModeCb:setCurrentOptionByData(curM, true)
    end
  end

  refreshingShooterUI = prevShooter
  refreshingTargetUI = prevTarget
end


function applyHelperLanguage(skipListRefresh)
  setHelperLanguageState((charConfig and charConfig.language) or 'en')

  for _, w in ipairs({
    helperWindow,
    statsWindow,
    spellSelectorModal,
    itemSelectorModal,
    renamePresetModal,
    conditionSettingsModal,
    keyCaptureModal,
    cavebotSettingsModal,
    cbControlMiniHud,
    idsMenuModal,
    huntListModal,
    finisherSettingsModal
  }) do
    if w then translateWidgetTree(w) end
  end

  if helperWindow then
    setupTabIcons()
    updateMasterBarUI()
    updateKeyButtonsUI()
  end
  updateStatsUI()
  populateTranslatedCombos()
  syncLanguageCombos()

  if not skipListRefresh then
    refreshHealingSpellsListUI()
    refreshHealingPotionsListUI()
    refreshShooterRulesUI()
    refreshTargetRulesUI()
    refreshCavebotUI()
    onToggleCavebotAutoRec(cavebotAutoRec)
    if updateItemTimerCountdownUI then
      updateItemTimerCountdownUI(g_clock.millis())
    end
    refreshSettingsTabUI()
  end
  if applyVocationVisibility then
    applyVocationVisibility()
  end
end

function setHelperLanguage(lang, skipSave)
  local normalized = (lang == 'pt') and 'pt' or 'en'
  if charConfig then
    charConfig.language = normalized
  end
  setHelperLanguageState(normalized)
  applyHelperLanguage(false)
  if not skipSave then
    saveCurrentProfile()
  end
end

