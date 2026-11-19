-- Shooter tab UI, condition settings, presets, callbacks, and tick engine

-- SHOOTER ENGINE UI, CREATURE COUNT COMPARATOR & PRESET RENAME MODAL
-- ============================================================================

function formatRuleConditionSummary(rule)
  local op = rule.countOp or '>='
  local cVal = tonumber(rule.countVal) or 1
  local parts = {
    'MP>=' .. (rule.mpPct or 0) .. '%',
    string.format('Cr %s %d', op, cVal),
    'HP:' .. (rule.hpMin or 0) .. '-' .. (rule.hpMax or 100) .. '%'
  }
  if (rule.delay or 0) > 0 then
    table.insert(parts, rule.delay .. 'ms')
  end
  if rule.priority == 'Target Name' and rule.targetName and rule.targetName ~= '' then
    table.insert(parts, '[' .. rule.targetName .. ']')
  elseif rule.priority and rule.priority ~= 'All Monsters' then
    table.insert(parts, '[' .. rule.priority .. ']')
  end
  local c = rule.cond or {}
  if c.adjacent then table.insert(parts, 'Adj') end
  if c.trapped then table.insert(parts, 'Trap>=' .. (tonumber(c.trappedCount) or 8)) end
  if c.stopped then table.insert(parts, 'Stop>=' .. (tonumber(c.stoppedMs) or 1000) .. 'ms') end
  if c.faceTarget then table.insert(parts, 'Face') end
  return table.concat(parts, ' | ')
end

refreshingCondModalUI = false

function getActiveConditionRule()
  local vp = getVocProfile()
  local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
  return (selectedShooterRuleIdx and rules[selectedShooterRuleIdx]) or shooterDraftRule
end

function syncConditionSettingsModalUI()
  if not conditionSettingsModal then return end
  local r = getActiveConditionRule()
  if not r then return end
  r.cond = type(r.cond) == 'table' and r.cond or {}
  local c = r.cond
  refreshingCondModalUI = true
  conditionSettingsModal:getChildById('condTrapped'):setChecked(c.trapped == true)
  local trEdit = conditionSettingsModal:getChildById('condTrappedCount')
  if trEdit then trEdit:setText(tostring(c.trappedCount or 8)) end
  conditionSettingsModal:getChildById('condStopped'):setChecked(c.stopped == true)
  conditionSettingsModal:getChildById('condStoppedMs'):setText(tostring(c.stoppedMs or 1000))
  conditionSettingsModal:getChildById('condAdjacent'):setChecked(c.adjacent == true)
  conditionSettingsModal:getChildById('condFaceTarget'):setChecked(c.faceTarget == true)
  conditionSettingsModal:getChildById('condMomentum'):setChecked(c.momentum == true)
  refreshingCondModalUI = false
end

function loadSelectedShooterRuleIntoEditor()
  local sBody = panels.shooter:getChildById('bodyPanel')
  local ed = sBody:getChildById('shooterEditorBox')
  local vp = getVocProfile()
  local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
  local r = selectedShooterRuleIdx and rules[selectedShooterRuleIdx] or nil
  if not r then
    shooterDraftRule = nil
    ed:getChildById('ruleSpellNameLabel'):setText(ht('No rule selected'))
    renderSpellSlot(ed:getChildById('ruleSpellSlot'), nil)
    return
  end

  shooterDraftRule = normalizeShooterRule(deepCopy(r))
  local d = shooterDraftRule

  refreshingShooterUI = true
  local slot = ed:getChildById('ruleSpellSlot')
  if d.type == 'R' and d.itemId and d.itemId > 0 then
    slot:getChildById('icon'):setVisible(false)
    local itemW = slot:getChildById('dropItem') or g_ui.createWidget('UIItem', slot)
    itemW:setId('dropItem')
    itemW:setSize({ width = 32, height = 32 })
    itemW:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    itemW:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemW:setVirtual(true)
    itemW:setPhantom(true)
    setVirtualUIItem(itemW, d.itemId)
    ed:getChildById('ruleTypeCombo'):setCurrentOptionByData('Rune', true)
    ed:getChildById('ruleSpellNameLabel'):setText((d.name or ht('Rune')) .. ' (#' .. d.itemId .. ')')
  else
    local oldItem = slot:getChildById('dropItem')
    if oldItem then oldItem:setVisible(false) end
    renderSpellSlot(slot, d)
    ed:getChildById('ruleTypeCombo'):setCurrentOptionByData(d.type == 'R' and 'Rune' or 'Spell', true)
    ed:getChildById('ruleSpellNameLabel'):setText((d.words ~= '' and d.words) or d.name or ht('Click slot'))
  end

  local function setEditText(id, val)
    local w = ed:getChildById(id)
    if w and w:getText() ~= val then w:setText(val) end
  end

  ed:getChildById('ruleTargetReqCheck'):setChecked(d.requiresTarget ~= false)
  local prio = (d.priority == 'Target Name') and 'Target Name' or 'All Monsters'
  ed:getChildById('rulePriorityCombo'):setCurrentOptionByData(prio, true)
  local nameEdit = ed:getChildById('ruleTargetNameEdit')
  if nameEdit:getText() ~= (d.targetName or '') then nameEdit:setText(d.targetName or '') end
  nameEdit:setVisible(prio == 'Target Name')
  setEditText('ruleMpEdit', tostring(d.mpPct or 0))
  ed:getChildById('ruleCountModeCombo'):setCurrentOption(d.countOp or '>=', true)
  setEditText('ruleCreaturesEdit', tostring(d.countVal or 1))
  setEditText('ruleHpMinEdit', tostring(d.hpMin or 0))
  setEditText('ruleHpMaxEdit', tostring(d.hpMax or 100))
  setEditText('ruleDelayEdit', tostring(d.delay or 0))
  refreshingShooterUI = false
  if conditionSettingsModal and conditionSettingsModal:isVisible() then
    syncConditionSettingsModalUI()
  end
end

function updateSelectedShooterRowLabels()
  if not panels.shooter or not selectedShooterRuleIdx then return end
  local vp = getVocProfile()
  local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
  local rule = rules[selectedShooterRuleIdx]
  if not rule then return end
  local list = panels.shooter:getChildById('bodyPanel'):getChildById('shooterRulesList')
  if not list then return end
  for _, row in ipairs(list:getChildren()) do
    if row.ruleIdx == selectedShooterRuleIdx then
      local condLbl = row:getChildById('condSummaryLabel')
      if condLbl then condLbl:setText(formatRuleConditionSummary(rule)) end
      break
    end
  end
end

function refreshShooterRulesUI()
  local vp = getVocProfile()
  local sBody = panels.shooter:getChildById('bodyPanel')
  local list = sBody:getChildById('shooterRulesList')
  list:destroyChildren()

  local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
  if not selectedShooterRuleIdx or not rules[selectedShooterRuleIdx] then
    selectedShooterRuleIdx = (#rules > 0) and 1 or nil
  end

  for idx, rule in ipairs(rules) do
    local row = g_ui.createWidget('ShooterRuleRow', list)
    local iconFrame = row:getChildById('iconFrame')
    local spIcon = iconFrame:getChildById('spellIcon')
    local rnIcon = iconFrame:getChildById('runeIcon')
    local wordsLbl = row:getChildById('spellWordsLabel')
    local condLbl = row:getChildById('condSummaryLabel')
    local enCheck = row:getChildById('enableCheck')

    if rule.type == 'R' and rule.itemId and rule.itemId > 0 then
      spIcon:setVisible(false)
      setVirtualUIItem(rnIcon, rule.itemId)
      wordsLbl:setText(rule.name or ('Rune #' .. rule.itemId))
    else
      rnIcon:setVisible(false)
      spIcon:setVisible(true)
      local spData = findSpellByWords(rule.words)
      local cid = (spData and spData.clientId) or (tonumber(rule.clientId) or 1)
      spIcon:setImageClip(getSpellClip(cid))
      wordsLbl:setText(rule.words ~= '' and rule.words or rule.name or 'Spell')
    end

    condLbl:setText(formatRuleConditionSummary(rule))
    enCheck:setChecked(rule.enabled ~= false)

    enCheck.onCheckChange = function(w, checked)
      local liveVp = getVocProfile()
      local liveRules = liveVp.shooter.presets[liveVp.shooter.currentPreset] or {}
      if liveRules[idx] then
        liveRules[idx].enabled = checked
        saveCurrentProfile()
      end
    end
    row:getChildById('upBtn').onClick = function()
      local liveVp = getVocProfile()
      local liveRules = liveVp.shooter.presets[liveVp.shooter.currentPreset] or {}
      if idx > 1 and liveRules[idx] and liveRules[idx - 1] then
        liveRules[idx], liveRules[idx - 1] = liveRules[idx - 1], liveRules[idx]
        selectedShooterRuleIdx = idx - 1
        refreshShooterRulesUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      local liveVp = getVocProfile()
      local liveRules = liveVp.shooter.presets[liveVp.shooter.currentPreset] or {}
      if idx < #liveRules and liveRules[idx] and liveRules[idx + 1] then
        liveRules[idx], liveRules[idx + 1] = liveRules[idx + 1], liveRules[idx]
        selectedShooterRuleIdx = idx + 1
        refreshShooterRulesUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      local liveVp = getVocProfile()
      local liveRules = liveVp.shooter.presets[liveVp.shooter.currentPreset] or {}
      table.remove(liveRules, idx)
      selectedShooterRuleIdx = math.min(#liveRules, idx)
      if selectedShooterRuleIdx < 1 then selectedShooterRuleIdx = nil end
      refreshShooterRulesUI()
      saveCurrentProfile()
    end)

    row.ruleIdx = idx
    row.onClick = function(w, mousePos)
      if isClickInsideAnyChild(w, {'enableCheck', 'upBtn', 'downBtn', 'delBtn'}, mousePos) then
        return
      end
      selectedShooterRuleIdx = w.ruleIdx
      list:focusChild(w, MouseFocusReason)
      loadSelectedShooterRuleIntoEditor()
    end
    if idx == selectedShooterRuleIdx then
      list:focusChild(row, KeyboardFocusReason)
    end
  end
  installClickOutsideUnfocus(list)

  local pBox = sBody:getChildById('presetsBox')
  local pCombo = pBox:getChildById('presetCombo')
  refreshingShooterUI = true
  pCombo:clearOptions()
  local presetNames = {}
  for n, _ in pairs(vp.shooter.presets or {}) do table.insert(presetNames, n) end
  table.sort(presetNames)
  for _, n in ipairs(presetNames) do
    pCombo:addOption(n)
  end
  pCombo:setCurrentOption(vp.shooter.currentPreset or 'Hunt', true)
  refreshingShooterUI = false
  loadSelectedShooterRuleIntoEditor()
end

function openConditionSettingsModalForSelected()
  if not getActiveConditionRule() then return end
  syncConditionSettingsModalUI()
  conditionSettingsModal:show()
  conditionSettingsModal:raise()
  conditionSettingsModal:focus()
end

function cycleShooterPreset()
  local vp = getVocProfile()
  local names = {}
  for n, _ in pairs(vp.shooter.presets) do table.insert(names, n) end
  table.sort(names)
  if #names == 0 then return end
  local cur = vp.shooter.currentPreset
  local nextName = names[1]
  for i, n in ipairs(names) do
    if n == cur then
      nextName = names[(i % #names) + 1]
      break
    end
  end
  vp.shooter.currentPreset = nextName
  selectedShooterRuleIdx = 1
  refreshShooterRulesUI()
  saveCurrentProfile()
end

function createNewShooterPreset()
  local vp = getVocProfile()
  local idx = 1
  local name = 'Preset ' .. idx
  while vp.shooter.presets[name] do
    idx = idx + 1
    name = 'Preset ' .. idx
  end
  vp.shooter.presets[name] = {}
  vp.shooter.currentPreset = name
  selectedShooterRuleIdx = nil
  refreshShooterRulesUI()
  saveCurrentProfile()
end

function openRenameShooterPresetModal()
  local vp = getVocProfile()
  local edit = renamePresetModal:getChildById('renamePresetEdit')
  edit:setText(vp.shooter.currentPreset or 'Hunt')
  renamePresetModal:show()
  renamePresetModal:raise()
  renamePresetModal:focus()
  edit:focus()
end

function confirmRenamePreset()
  local vp = getVocProfile()
  local cur = vp.shooter.currentPreset
  local newName = renamePresetModal:getChildById('renamePresetEdit'):getText():gsub('^%s+', ''):gsub('%s+$', '')
  if newName == '' or newName == cur then
    renamePresetModal:hide()
    return
  end
  if vp.shooter.presets[newName] then
    if modules.game_textmessage then
      modules.game_textmessage.displayStatusMessage('[DAVCaster] A preset with that name already exists.')
    end
    return
  end
  vp.shooter.presets[newName] = deepCopy(vp.shooter.presets[cur] or {})
  vp.shooter.presets[cur] = nil
  vp.shooter.currentPreset = newName
  renamePresetModal:hide()
  refreshShooterRulesUI()
  saveCurrentProfile()
end

function duplicateShooterPreset()
  local vp = getVocProfile()
  local cur = vp.shooter.currentPreset
  local src = vp.shooter.presets[cur] or {}
  local name = cur .. ' (Copy)'
  local n = 2
  while vp.shooter.presets[name] do
    name = string.format('%s (Copy %d)', cur, n)
    n = n + 1
  end
  vp.shooter.presets[name] = deepCopy(src)
  vp.shooter.currentPreset = name
  selectedShooterRuleIdx = (#vp.shooter.presets[name] > 0) and 1 or nil
  refreshShooterRulesUI()
  saveCurrentProfile()
end

function deleteShooterPreset()
  local vp = getVocProfile()
  local count = 0
  for _ in pairs(vp.shooter.presets) do count = count + 1 end
  if count <= 1 then return end
  vp.shooter.presets[vp.shooter.currentPreset] = nil
  for n, _ in pairs(vp.shooter.presets) do
    vp.shooter.currentPreset = n
    break
  end
  selectedShooterRuleIdx = 1
  refreshShooterRulesUI()
  saveCurrentProfile()
end

-- ============================================================================

SHOOTER_COUNT_RANGE = {
  -- Adjacent / 1-SQM melee & close spells
  ['exori'] = 1, ['exori gran'] = 1, ['exori min'] = 1, ['exori max'] = 1,
  ['exori ico'] = 1, ['exori gran ico'] = 1, ['exori ico scu'] = 1,
  ['exeta res'] = 1, ['exeta pug'] = 1,
  ['exori infir pug'] = 1, ['exori pug'] = 1, ['exori gran pug'] = 1, ['exori gran nia'] = 1,
  -- 2-SQM spells
  ['exeta amp res'] = 2,
  -- 3-SQM area spells
  ['exori mas'] = 3, ['exevo mas san'] = 3, ['exori mas nia'] = 3, ['exori gran mas nia'] = 3,
  -- 4-SQM area spells
  ['exevo tempo mas san'] = 4,
  -- 5-SQM big UE spells
  ['exevo gran mas flam'] = 5, ['exevo gran mas vis'] = 5,
  ['exevo gran mas tera'] = 5, ['exevo gran mas frigo'] = 5,
}
function getRuleCountRange(rule, words)
  if rule.cond and rule.cond.adjacent then return 1 end
  local byWords = SHOOTER_COUNT_RANGE[(words or ''):lower()]
  if byWords then return byWords end
  return 7
end


function loadShooterUI()
  -- 3. Shooter UI
  local sGlob = panels.shooter:getChildById('bodyPanel'):getChildById('shooterGlobalBox')
  sGlob:getChildById('enableShooterCheck'):setChecked(vp.shooter.enabled == true, true)
  sGlob:getChildById('disablePzCheck'):setChecked(vp.shooter.disablePz ~= false)
  refreshShooterRulesUI()

  -- 4. Target UI
end

function setupShooterCallbacks()
  -- Rename Preset Modal
  renamePresetModal:getChildById('confirmRenameBtn').onClick = function() confirmRenamePreset() end
  renamePresetModal:getChildById('cancelRenameBtn').onClick = function() renamePresetModal:hide() end
  renamePresetModal:getChildById('renamePresetEdit').onKeyDown = function(w, keyCode)
    if keyCode == KeyEnter then
      confirmRenamePreset()
      return true
    end
    return false
  end

  -- Condition Settings Modal
  local function applyConditionSettingsFromModal(closeModal)
    local target = getActiveConditionRule()
    if target then
      target.cond = {
        trapped = conditionSettingsModal:getChildById('condTrapped'):isChecked(),
        trappedCount = parseNum(conditionSettingsModal:getChildById('condTrappedCount'), 8, 1, 8),
        stopped = conditionSettingsModal:getChildById('condStopped'):isChecked(),
        stoppedMs = parseNum(conditionSettingsModal:getChildById('condStoppedMs'), 1000, 0, 60000),
        adjacent = conditionSettingsModal:getChildById('condAdjacent'):isChecked(),
        faceTarget = conditionSettingsModal:getChildById('condFaceTarget'):isChecked(),
        momentum = conditionSettingsModal:getChildById('condMomentum'):isChecked()
      }
      updateSelectedShooterRowLabels()
      saveCurrentProfile()
    end
    if closeModal and conditionSettingsModal then
      conditionSettingsModal:hide()
    end
  end
  conditionSettingsModal:getChildById('updateCondBtn').onClick = function()
    applyConditionSettingsFromModal(true)
  end
  for _, cid in ipairs({ 'condTrapped', 'condStopped', 'condAdjacent', 'condFaceTarget', 'condMomentum' }) do
    local chk = conditionSettingsModal:getChildById(cid)
    if chk then
      chk.onCheckChange = function()
        if refreshingCondModalUI then return end
        applyConditionSettingsFromModal(false)
      end
    end
  end
  for _, cid in ipairs({ 'condTrappedCount', 'condStoppedMs' }) do
    local ed = conditionSettingsModal:getChildById(cid)
    if ed then
      ed.onTextChange = function()
        if refreshingCondModalUI then return end
        applyConditionSettingsFromModal(false)
      end
    end
  end

  -- Key Capture Modal

  -- Shooter Tab Wiring (edicao em tempo real, sem botao Update)
  local sBody = panels.shooter:getChildById('bodyPanel')
  local ed = sBody:getChildById('shooterEditorBox')
  local function ensureDraft()
    local vp = getVocProfile()
    local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    if selectedShooterRuleIdx and rules[selectedShooterRuleIdx] then
      return normalizeShooterRule(rules[selectedShooterRuleIdx])  -- regra real, edita ao vivo
    end
    if not shooterDraftRule then
      shooterDraftRule = normalizeShooterRule({ type = 'S', words = '', name = 'New', countVal = 1, countOp = '>=' })
    end
    return shooterDraftRule
  end
  local function liveTouch()
    updateSelectedShooterRowLabels()
    saveCurrentProfile()
  end
  local function renderDraftSlotPreview(d)
    local slot = ed:getChildById('ruleSpellSlot')
    if not d then return end
    if d.type == 'R' and d.itemId and d.itemId > 0 then
      slot:getChildById('icon'):setVisible(false)
      local itemW = slot:getChildById('dropItem') or g_ui.createWidget('UIItem', slot)
      itemW:setId('dropItem')
      itemW:setSize({ width = 32, height = 32 })
      itemW:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
      itemW:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      itemW:setVirtual(true)
      itemW:setPhantom(true)
      setVirtualUIItem(itemW, d.itemId)
      ed:getChildById('ruleSpellNameLabel'):setText((d.name or ht('Rune')) .. ' (#' .. d.itemId .. ')')
    else
      local oldItem = slot:getChildById('dropItem')
      if oldItem then oldItem:setVisible(false) end
      renderSpellSlot(slot, d)
      ed:getChildById('ruleSpellNameLabel'):setText((d.words ~= '' and d.words) or d.name or ht('Click slot'))
    end
  end
  bindSlotClicks(ed:getChildById('ruleSpellSlot'), function()
    local d = ensureDraft()
    if d.type == 'R' then
      openItemSelector('Select Attack Rune', 'rune', d.itemId, function(it)
        d.itemId, d.name, d.words = it.id, it.name, it.name
        renderDraftSlotPreview(d)
        if selectedShooterRuleIdx then refreshShooterRulesUI() saveCurrentProfile() end
      end)
    else
      openSpellSelector('Select Caster Spell', 1, d, function(sp)
        d.words, d.name, d.clientId = sp.words, sp.name, sp.clientId
        local low = (sp.words or ''):lower()
        if DEFAULT_ADJACENT_SPELLS[low] ~= nil then
          d.cond = d.cond or {}
          d.cond.adjacent = DEFAULT_ADJACENT_SPELLS[low]
        end
        if low == 'exeta amp res' or low == 'exeta res' or low == 'utito tempo' or low == 'exori mas' then
          d.requiresTarget = false
          ed:getChildById('ruleTargetReqCheck'):setChecked(false)
        end
        renderDraftSlotPreview(d)
        if selectedShooterRuleIdx then refreshShooterRulesUI() saveCurrentProfile() end
      end)
    end
  end, function()
    local d = ensureDraft()
    d.words, d.itemId, d.name, d.clientId = '', 0, '', 0
    renderDraftSlotPreview(d)
    if selectedShooterRuleIdx then refreshShooterRulesUI() saveCurrentProfile() end
  end)

  local ruleTypeCb = ed:getChildById('ruleTypeCombo')
  for _, opt in ipairs({ 'Spell', 'Rune' }) do ruleTypeCb:addOption(ht(opt), opt) end
  ruleTypeCb.onOptionChange = function(w, text, data)
    if refreshingShooterUI or refreshingLanguageCombos then return end
    local d = ensureDraft()
    local key = getComboOptionData(w, data or text)
    d.type = (key == 'Rune') and 'R' or 'S'
    renderDraftSlotPreview(d)
    liveTouch()
  end
  ed:getChildById('ruleTargetReqCheck').onCheckChange = function(w, ch)
    if refreshingShooterUI then return end
    ensureDraft().requiresTarget = ch
    liveTouch()
  end
  local rulePrioCb = ed:getChildById('rulePriorityCombo')
  for _, opt in ipairs({ 'All Monsters', 'Target Name' }) do rulePrioCb:addOption(ht(opt), opt) end
  rulePrioCb.onOptionChange = function(w, text, data)
    if refreshingShooterUI or refreshingLanguageCombos then return end
    local d = ensureDraft()
    d.priority = getComboOptionData(w, data or text) or 'All Monsters'
    ed:getChildById('ruleTargetNameEdit'):setVisible(d.priority == 'Target Name')
    liveTouch()
  end
  ed:getChildById('ruleTargetNameEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingShooterUI then return end
    ensureDraft().targetName = txt
    liveTouch()
  end
  ed:getChildById('ruleMpEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingShooterUI then return end
    local n = tonumber(txt)
    if n then ensureDraft().mpPct = math.max(0, math.min(100, math.floor(n))) liveTouch() end
  end
  local ruleCountCb = ed:getChildById('ruleCountModeCombo')
  for _, opt in ipairs({ '>=', '=', '<' }) do ruleCountCb:addOption(opt) end
  ruleCountCb.onOptionChange = function(w, text)
    if isLoadingUI or refreshingShooterUI then return end
    ensureDraft().countOp = text or '>='
    liveTouch()
  end
  ed:getChildById('ruleCreaturesEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingShooterUI then return end
    local n = tonumber(txt)
    if n then ensureDraft().countVal = math.max(0, math.min(30, math.floor(n))) liveTouch() end
  end
  ed:getChildById('ruleHpMinEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingShooterUI then return end
    local n = tonumber(txt)
    if n then ensureDraft().hpMin = math.max(0, math.min(100, math.floor(n))) liveTouch() end
  end
  ed:getChildById('ruleHpMaxEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingShooterUI then return end
    local n = tonumber(txt)
    if n then ensureDraft().hpMax = math.max(0, math.min(100, math.floor(n))) liveTouch() end
  end
  ed:getChildById('ruleDelayEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingShooterUI then return end
    local n = tonumber(txt)
    if n then ensureDraft().delay = math.max(0, math.min(600000, math.floor(n))) liveTouch() end
  end
  ed:getChildById('ruleUpBtn').onClick = function()
    local vp = getVocProfile()
    local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    local idx = selectedShooterRuleIdx
    if idx and idx > 1 then
      rules[idx], rules[idx - 1] = rules[idx - 1], rules[idx]
      selectedShooterRuleIdx = idx - 1
      refreshShooterRulesUI()
      saveCurrentProfile()
    end
  end
  ed:getChildById('ruleDownBtn').onClick = function()
    local vp = getVocProfile()
    local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    local idx = selectedShooterRuleIdx
    if idx and idx < #rules then
      rules[idx], rules[idx + 1] = rules[idx + 1], rules[idx]
      selectedShooterRuleIdx = idx + 1
      refreshShooterRulesUI()
      saveCurrentProfile()
    end
  end
  ed:getChildById('ruleDelBtn').onClick = function()
    local vp = getVocProfile()
    local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    if selectedShooterRuleIdx and rules[selectedShooterRuleIdx] then
      table.remove(rules, selectedShooterRuleIdx)
      selectedShooterRuleIdx = math.min(#rules, selectedShooterRuleIdx)
      if selectedShooterRuleIdx < 1 then selectedShooterRuleIdx = nil end
      refreshShooterRulesUI()
      saveCurrentProfile()
    end
  end
  ed:getChildById('ruleNewBtn').onClick = function()
    local vp = getVocProfile()
    local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    local nr = normalizeShooterRule({ type = 'S', words = '', name = 'New', countVal = 1, countOp = '>=' })
    table.insert(rules, nr)
    selectedShooterRuleIdx = #rules
    refreshShooterRulesUI()
    saveCurrentProfile()
  end
  ed:getChildById('ruleCondBtn').onClick = function() openConditionSettingsModalForSelected() end

  local sGlob = sBody:getChildById('shooterGlobalBox')
  sGlob:getChildById('enableShooterCheck').onCheckChange = function(w, ch)
    if isLoadingUI or refreshingShooterUI then return end
    getVocProfile().shooter.enabled = (ch == true)
    updateStatsUI()
    saveCurrentProfile()
  end
  sGlob:getChildById('disablePzCheck').onCheckChange = function(w, ch)
    getVocProfile().shooter.disablePz = ch
    saveCurrentProfile()
  end
  local presetCb = sBody:getChildById('presetsBox'):getChildById('presetCombo')
  presetCb.onOptionChange = function(w, text)
    if refreshingShooterUI or not text or text == '' then return end
    local vp = getVocProfile()
    if vp.shooter.presets[text] and vp.shooter.currentPreset ~= text then
      vp.shooter.currentPreset = text
      selectedShooterRuleIdx = (#vp.shooter.presets[text] > 0) and 1 or nil
      refreshShooterRulesUI()
      saveCurrentProfile()
    end
  end

  -- Target Tab Wiring
end

function runShooterTick(player, pPos, now, mpPct, inPz, vp, nearbyMonsters, adjacentMonsters, currentTarget)
  if charConfig.masterEnabled == true and vp.shooter.enabled == true and #nearbyMonsters > 0 and (not vp.shooter.disablePz or not inPz) then
    local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    local castGap = math.max(250, (tonumber(g_game.getPing and g_game.getPing()) or 0) + 120)
    local attackCastThisTick = (now - lastShooterCastTime) < castGap
    local supportCastThisTick = (now - lastSupportShooterCastTime) < castGap

    for rIdx = 1, #rules do
      local rule = rules[rIdx]
      if rule and rule.enabled ~= false then
        local c = rule.cond or {}
        local trimmedWords = (rule.words or ''):gsub('^%s+', ''):gsub('%s+$', '')
        local spData = (rule.type ~= 'R') and findSpellByWords(trimmedWords) or nil
        local isSupportSpell = (spData and type(spData.group) == 'table' and spData.group[3] ~= nil and spData.group[1] == nil) and true or false
        local groupCadenceOk = isSupportSpell and (not supportCastThisTick) or (not isSupportSpell and not attackCastThisTick)
        if groupCadenceOk then
          local wLower = trimmedWords:lower()
          local needTgt = (rule.requiresTarget ~= false)
          if COMBAT_SUPPORT_WORDS[wLower] or wLower == 'exori mas'
             or (spData and spData.needTarget == false) or (rule.priority == 'Target Name') then
            needTgt = false
          end
          local tgt = isValidMonsterCreature(currentTarget) and currentTarget or nil
          if (not needTgt) or tgt then
            local cntRange = getRuleCountRange(rule, trimmedWords)
            local tgtRangeOk = true
            if needTgt and tgt then
              local tPos = tgt:getPosition()
              local builtInRange = SHOOTER_COUNT_RANGE[wLower]
              local reqDist = c.adjacent and 1 or builtInRange
              if reqDist and tPos then
                tgtRangeOk = (getDistanceBetween(pPos, tPos) <= reqDist)
              end
            end
            local matchingCount = 0
            local firstInRangeCreature = nil
            for _, m in ipairs(nearbyMonsters) do
              if m.dist <= cntRange then
                matchingCount = matchingCount + 1
                if not firstInRangeCreature then firstInRangeCreature = m.creature end
              end
            end
            local nameOk = true
            local firstMatchedCreature = nil
            if rule.priority == 'Target Name' and rule.targetName and rule.targetName ~= '' then
              local filtSet = parseCommaSet(rule.targetName)
              matchingCount = 0
              for _, m in ipairs(nearbyMonsters) do
                local mLow = m.name:lower()
                local hit = false
                for tok, _ in pairs(filtSet) do
                  if mLow:find(tok, 1, true) then hit = true break end
                end
                if hit and m.dist <= 7 then
                  matchingCount = matchingCount + 1
                  if not firstMatchedCreature then firstMatchedCreature = m.creature end
                end
              end
              nameOk = matchingCount > 0
            end

            local countOk = checkCountCondition(matchingCount, rule.countOp or '>=', rule.countVal or 1)
            local hpRef = (rule.priority == 'Target Name') and (firstMatchedCreature or tgt) or (needTgt and tgt or (firstInRangeCreature or tgt))
            local hpRefVal = hpRef and hpRef:getHealthPercent() or 100
            local hpMinOk = (not hpRef) or (hpRefVal >= (tonumber(rule.hpMin) or 0))
            local maxVal = tonumber(rule.hpMax) or 100
            local hpMaxOk = (not hpRef) or (maxVal <= 0) or (hpRefVal <= maxVal)
            local mpOk = mpPct >= (tonumber(rule.mpPct) or 0)
            local delayMs = tonumber(rule.delay) or 0
            local hasServerId = (rule.type ~= 'R' and spData and spData.id) and true or false
            local lastRuleCast = hasServerId and math.max(confirmedSpellCastAt[spData.id] or 0, ruleCooldowns[rule] or 0) or (ruleCooldowns[rule] or 0)
            local cdOk = ((delayMs <= 0) or ((now - lastRuleCast) >= delayMs))
              and (not hasServerId or not rule._tryAt or ((now - rule._tryAt) >= 350))
              and (rule.type == 'R' or not isSpellOnClientCooldown(trimmedWords, now))
            local trapMin = math.max(1, math.min(8, tonumber(c.trappedCount) or 8))
            local trapOk = (not c.trapped) or (adjacentMonsters >= trapMin)
            local adjOk = true
            if c.adjacent then
              if needTgt and tgt and tgt:getPosition() then
                adjOk = (getDistanceBetween(pPos, tgt:getPosition()) <= 1)
              else
                adjOk = (adjacentMonsters >= 1)
              end
            end
            local stopOk = (not c.stopped) or ((now - playerStopTracker.since) >= (c.stoppedMs or 1000))

            if tgtRangeOk and nameOk and countOk and hpMinOk and hpMaxOk and mpOk and cdOk and trapOk and adjOk and stopOk then
              if c.faceTarget then
                local dirCounts = { [North] = 0, [South] = 0, [East] = 0, [West] = 0 }
                for _, m in ipairs(nearbyMonsters) do
                  local mp = m.creature:getPosition()
                  if mp then
                    local dx, dy = mp.x - pPos.x, mp.y - pPos.y
                    if math.abs(dx) >= math.abs(dy) then
                      if dx > 0 then dirCounts[East] = dirCounts[East] + 1 elseif dx < 0 then dirCounts[West] = dirCounts[West] + 1 end
                    else
                      if dy > 0 then dirCounts[South] = dirCounts[South] + 1 elseif dy < 0 then dirCounts[North] = dirCounts[North] + 1 end
                    end
                  end
                end
                local bestDir, bestCnt = nil, 0
                for d, cnt in pairs(dirCounts) do
                  if cnt > bestCnt then bestDir, bestCnt = d, cnt end
                end
                if bestDir and player:getDirection() ~= bestDir then
                  g_game.turn(bestDir)
                elseif tgt then
                  faceCreatureDirection(player, tgt)
                end
              end
              local runeTarget = firstMatchedCreature or tgt or (nearbyMonsters[1] and nearbyMonsters[1].creature) or nil
              if rule.type == 'R' then
                if rule.itemId and rule.itemId > 0 and isValidMonsterCreature(runeTarget) then
                  g_game.useInventoryItemWith(rule.itemId, runeTarget)
                  ruleCooldowns[rule] = now
                  lastShooterCastTime = now
                  attackCastThisTick = true
                  break
                end
              else
                if trimmedWords ~= '' then
                  g_game.talk(trimmedWords)
                  if hasServerId then
                    rule._tryAt = now
                    if type(spData.group) == 'table' then
                      for gid, _ in pairs(spData.group) do
                        local gNum = tonumber(gid) or gid
                        groupCooldownUntil[gNum] = math.max(groupCooldownUntil[gNum] or 0, now + math.max(castGap, 300))
                      end
                    end
                  else
                    ruleCooldowns[rule] = now
                  end
                  if isSupportSpell then
                    lastSupportShooterCastTime = now
                    supportCastThisTick = true
                  else
                    lastShooterCastTime = now
                    attackCastThisTick = true
                    break
                  end
                end
              end
            end
          end
        end
      end
    end
  end

end
