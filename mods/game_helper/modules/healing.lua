-- Healing tab UI, callbacks, and tick engine

function switchHealingSubTab(sub)
  currentHealingSubTab = sub
  local h = panels.healing
  local bar = h:getChildById('subTabBar')
  local bSelf = bar:getChildById('subTabSelfBtn')
  local bSio = bar:getChildById('subTabSioBtn')
  local bMas = bar:getChildById('subTabMasResBtn')
  if bSelf then bSelf:setColor(sub == 'self' and '#f0d080' or '#b0b0b0') end
  if bSio then bSio:setColor(sub == 'sio' and '#f0d080' or '#b0b0b0') end
  if bMas then bMas:setColor(sub == 'masres' and '#f0d080' or '#b0b0b0') end

  h:getChildById('selfHealingContainer'):setVisible(sub == 'self')
  h:getChildById('sioHealingContainer'):setVisible(sub == 'sio')
  h:getChildById('masResHealingContainer'):setVisible(sub == 'masres')
end


-- VOCATION VISIBILITY & DYNAMIC HEALING LISTS
-- ============================================================================

function applyVocationVisibility()
  local h = panels.healing
  if not h then return end
  local voc = currentVocName or detectPlayerVocation()
  local bar = h:getChildById('subTabBar')
  local isDruidOrMonk = (voc == 'Druid' or voc == 'Monk')
  local hasUtamo = (voc == 'Sorcerer' or voc == 'Druid' or voc == 'Monk')
  local hasRecovery = (voc == 'Knight' or voc == 'Paladin' or voc == 'Monk')

  bar:getChildById('subTabSioBtn'):setVisible(isDruidOrMonk)
  bar:getChildById('subTabMasResBtn'):setVisible(isDruidOrMonk)
  if not isDruidOrMonk and (currentHealingSubTab == 'sio' or currentHealingSubTab == 'masres') then
    switchHealingSubTab('self')
  end

  local sioBox = h:getChildById('sioHealingContainer'):getChildById('sioBox')
  if sioBox then
    local sioChk = sioBox:getChildById('sioEnableCheck')
    if sioChk then
      sioChk:setText(ht(voc == 'Monk' and 'Enable Restore Balance (Friend)' or 'Enable Exura Sio (Friend)'))
    end
    local granChk = sioBox:getChildById('granSioEnableCheck')
    if granChk then
      granChk:setVisible(voc == 'Druid')
    end
  end

  local exBox = h:getChildById('selfHealingContainer'):getChildById('extraHealingBox')
  exBox:getChildById('quickSioSlot'):setVisible(isDruidOrMonk)
  exBox:getChildById('quickSioCheck'):setVisible(isDruidOrMonk)
  exBox:getChildById('manaShieldSlot'):setVisible(hasUtamo)
  exBox:getChildById('manaShieldCheck'):setVisible(hasUtamo)
  exBox:getChildById('recoverySlot'):setVisible(hasRecovery)
  exBox:getChildById('recoverySpellCheck'):setVisible(hasRecovery)
  exBox:getChildById('recoveryHpLbl'):setVisible(hasRecovery)
  exBox:getChildById('recoveryPctEdit'):setVisible(hasRecovery)
end


function refreshHealingSpellsListUI()
  local vp = getVocProfile()
  local list = panels.healing:getChildById('selfHealingContainer'):getChildById('mainBox'):getChildById('leftCol'):getChildById('spellHealList')
  list:destroyChildren()

  local spells = vp.healing.spells
  for idx, sp in ipairs(spells) do
    local row = g_ui.createWidget('HealingSpellListRow', list)
    local slot = row:getChildById('spellSlot')
    local nameLbl = row:getChildById('spellNameLabel')
    local wordsLbl = row:getChildById('spellWordsLabel')
    local modeCombo = row:getChildById('modeCombo')
    local pctEdit = row:getChildById('pctEdit')
    local minMpEdit = row:getChildById('minMpEdit')
    local enCheck = row:getChildById('enableCheck')

    renderSpellSlot(slot, sp)
    nameLbl:setText(sp.words ~= '' and (sp.name or sp.words) or ht('Empty Spell'))
    wordsLbl:setText(sp.words ~= '' and sp.words or ht('Click icon to pick'))

    local modeLabelByKey = { hp = 'HP<=', mp_low = 'MP<=', mp_high = 'MP>=' }
    local modeKeyByLabel = { ['HP<='] = 'hp', ['MP<='] = 'mp_low', ['MP>='] = 'mp_high' }
    modeCombo:addOption('HP<=')
    modeCombo:addOption('MP<=')
    modeCombo:addOption('MP>=')

    local function syncModeComboColor()
      local m = sp.mode or 'hp'
      if m == 'mp_low' or m == 'mp_high' then
        modeCombo:setColor('#8ec5ff')
      else
        modeCombo:setColor('#ff9999')
      end
    end
    modeCombo:setCurrentOption(modeLabelByKey[sp.mode or 'hp'] or 'HP<=', true)
    syncModeComboColor()
    pctEdit:setText(tostring(sp.pct or 80))
    minMpEdit:setText(tostring(sp.minMp or 0))
    enCheck:setChecked(sp.enabled ~= false)

    bindSlotClicks(slot, function()
      openSpellSelector('Select Healing Spell', 2, sp, function(chosen)
        sp.words = chosen.words
        sp.name = chosen.name
        sp.clientId = chosen.clientId
        refreshHealingSpellsListUI()
        saveCurrentProfile()
      end)
    end, function()
      sp.words = ''
      sp.name = ''
      sp.clientId = 0
      refreshHealingSpellsListUI()
      saveCurrentProfile()
    end)

    modeCombo.onOptionChange = function(w, text)
      sp.mode = modeKeyByLabel[text] or 'hp'
      syncModeComboColor()
      saveCurrentProfile()
    end

    pctEdit.onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        sp.pct = math.max(0, math.min(100, math.floor(n)))
        saveCurrentProfile()
      end
    end
    minMpEdit.onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        sp.minMp = math.max(0, math.min(100, math.floor(n)))
        saveCurrentProfile()
      end
    end
    enCheck.onCheckChange = function(w, checked)
      sp.enabled = checked
      saveCurrentProfile()
    end
    row:getChildById('upBtn').onClick = function()
      local liveSpells = getVocProfile().healing.spells
      if idx > 1 and liveSpells[idx] and liveSpells[idx - 1] then
        liveSpells[idx], liveSpells[idx - 1] = liveSpells[idx - 1], liveSpells[idx]
        refreshHealingSpellsListUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      local liveSpells = getVocProfile().healing.spells
      if idx < #liveSpells and liveSpells[idx] and liveSpells[idx + 1] then
        liveSpells[idx], liveSpells[idx + 1] = liveSpells[idx + 1], liveSpells[idx]
        refreshHealingSpellsListUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      local liveSpells = getVocProfile().healing.spells
      table.remove(liveSpells, idx)
      refreshHealingSpellsListUI()
      saveCurrentProfile()
    end)
  end
  installClickOutsideUnfocus(list)
end

function addHealingSpellRule()
  local vp = getVocProfile()
  table.insert(vp.healing.spells, { words = '', name = '', clientId = 0, pct = 80, minMp = 0, mode = 'hp', enabled = true })
  refreshHealingSpellsListUI()
  saveCurrentProfile()
end

function refreshHealingPotionsListUI()
  local vp = getVocProfile()
  local list = panels.healing:getChildById('selfHealingContainer'):getChildById('mainBox'):getChildById('rightCol'):getChildById('potionHealList')
  list:destroyChildren()

  local potions = vp.healing.potions
  for idx, pt in ipairs(potions) do
    local row = g_ui.createWidget('HealingPotionListRow', list)
    local slot = row:getChildById('itemSlot')
    local barType = row:getChildById('barType')
    local nameLbl = row:getChildById('itemNameLabel')
    local ptypeCombo = row:getChildById('ptypeCombo')
    local pctEdit = row:getChildById('pctEdit')
    local enCheck = row:getChildById('enableCheck')

    renderItemSlot(slot, pt.id)
    renderPotionTypeBar(barType, pt.ptype)
    local info = pt.id and pt.id > 0 and findItemInCatalog(pt.id) or nil
    nameLbl:setText(info and info.name or ht('Empty / Drop Potion'))

    local catalogPtype = info and info.ptype or nil
    local ptypeLabelByKey = { hp = 'HP%', mp = 'MP%' }
    local ptypeKeyByLabel = { ['HP%'] = 'hp', ['MP%'] = 'mp' }
    if catalogPtype == 'mp' then
      ptypeCombo:addOption('MP%')
      pt.ptype = 'mp'
    elseif catalogPtype == 'hp' then
      ptypeCombo:addOption('HP%')
      pt.ptype = 'hp'
    else
      ptypeCombo:addOption('HP%')
      ptypeCombo:addOption('MP%')
      if pt.ptype ~= 'hp' and pt.ptype ~= 'mp' then pt.ptype = 'hp' end
    end
    renderPotionTypeBar(barType, pt.ptype)

    local function syncPtypeCombo()
      local curKey = (pt.ptype == 'mp') and 'mp' or 'hp'
      ptypeCombo:setCurrentOption(ptypeLabelByKey[curKey] or 'HP%', true)
      if curKey == 'mp' then
        ptypeCombo:setColor('#8ec5ff')
      else
        ptypeCombo:setColor('#ff9999')
      end
    end
    syncPtypeCombo()
    pctEdit:setText(tostring(pt.pct or 50))
    enCheck:setChecked(pt.enabled ~= false)

    bindSlotClicks(slot, function()
      openItemSelector('Select Healing Potion', 'potion', pt.id, function(it)
        pt.id = it.id
        if it.ptype == 'mp' or it.ptype == 'hp' then
          pt.ptype = it.ptype
        elseif it.ptype == 'spirit' and pt.ptype ~= 'hp' and pt.ptype ~= 'mp' then
          pt.ptype = 'hp'
        end
        refreshHealingPotionsListUI()
        saveCurrentProfile()
      end)
    end, function()
      pt.id = 0
      refreshHealingPotionsListUI()
      saveCurrentProfile()
    end)

    attachItemDropHandler(slot, function(droppedId)
      pt.id = droppedId
      local cat = findItemInCatalog(droppedId)
      if cat and (cat.ptype == 'mp' or cat.ptype == 'hp') then
        pt.ptype = cat.ptype
      elseif pt.ptype ~= 'hp' and pt.ptype ~= 'mp' then
        pt.ptype = 'hp'
      end
      refreshHealingPotionsListUI()
      saveCurrentProfile()
    end)

    barType.onClick = function()
      if catalogPtype == 'mp' or catalogPtype == 'hp' then
        pt.ptype = catalogPtype
      else
        pt.ptype = (pt.ptype == 'mp') and 'hp' or 'mp'
      end
      renderPotionTypeBar(barType, pt.ptype)
      syncPtypeCombo()
      saveCurrentProfile()
    end
    ptypeCombo.onOptionChange = function(w, text)
      pt.ptype = ptypeKeyByLabel[text] or 'hp'
      renderPotionTypeBar(barType, pt.ptype)
      syncPtypeCombo()
      saveCurrentProfile()
    end
    pctEdit.onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        pt.pct = math.max(0, math.min(100, math.floor(n)))
        saveCurrentProfile()
      end
    end
    enCheck.onCheckChange = function(w, checked)
      pt.enabled = checked
      saveCurrentProfile()
    end
    row:getChildById('upBtn').onClick = function()
      local livePotions = getVocProfile().healing.potions
      if idx > 1 and livePotions[idx] and livePotions[idx - 1] then
        livePotions[idx], livePotions[idx - 1] = livePotions[idx - 1], livePotions[idx]
        refreshHealingPotionsListUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      local livePotions = getVocProfile().healing.potions
      if idx < #livePotions and livePotions[idx] and livePotions[idx + 1] then
        livePotions[idx], livePotions[idx + 1] = livePotions[idx + 1], livePotions[idx]
        refreshHealingPotionsListUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      local livePotions = getVocProfile().healing.potions
      table.remove(livePotions, idx)
      refreshHealingPotionsListUI()
      saveCurrentProfile()
    end)
  end
  installClickOutsideUnfocus(list)
end

function addHealingPotionRule()
  local vp = getVocProfile()
  table.insert(vp.healing.potions, { id = 0, pct = 50, ptype = 'mp', enabled = true })
  refreshHealingPotionsListUI()
  saveCurrentProfile()
end

-- ============================================================================

function getSortedHealSpells(list)
  local arr = {}
  for i, sp in ipairs(list or {}) do
    local isMp = (sp.mode == 'mp_low' or sp.mode == 'mp_high')
    arr[#arr + 1] = { sp = sp, i = i, g = isMp and 2 or 1 }
  end
  table.sort(arr, function(a, b)
    if a.g ~= b.g then return a.g < b.g end
    if a.g == 1 then
      local pa, pb = tonumber(a.sp.pct) or 80, tonumber(b.sp.pct) or 80
      if pa ~= pb then return pa < pb end
    end
    return a.i < b.i
  end)
  local out = {}
  for k, e in ipairs(arr) do out[k] = e.sp end
  return out
end


function loadHealingUI()
  -- 1. Healing UI
  refreshHealingSpellsListUI()
  refreshHealingPotionsListUI()
  local exBox = panels.healing:getChildById('selfHealingContainer'):getChildById('extraHealingBox')
  renderSpellSlot(exBox:getChildById('cureParaSlot'), vp.healing.curePara)
  exBox:getChildById('cureParaCheck'):setChecked(vp.healing.curePara.enabled == true)
  renderSpellSlot(exBox:getChildById('quickSioSlot'), vp.healing.partyHeal)
  exBox:getChildById('quickSioCheck'):setChecked(vp.healing.partyHeal.enabled == true)
  renderSpellSlot(exBox:getChildById('manaShieldSlot'), vp.healing.manaShield)
  exBox:getChildById('manaShieldCheck'):setChecked(vp.healing.manaShield.enabled == true)
  if exBox:getChildById('utamoBelowEdit') then exBox:getChildById('utamoBelowEdit'):setText(tostring(vp.healing.manaShield.belowHp or 100)) end
  if exBox:getChildById('utamoRecoverCheck') then exBox:getChildById('utamoRecoverCheck'):setChecked(vp.healing.manaShield.removeOnRecovery == true) end
  if exBox:getChildById('utamoAboveEdit') then exBox:getChildById('utamoAboveEdit'):setText(tostring(vp.healing.manaShield.aboveHp or 70)) end
  if exBox:getChildById('antiLagCheck') then exBox:getChildById('antiLagCheck'):setChecked(vp.healing.manaShield.antiLag == true) end
  local de = vp.healing.defEquip or {}
  if exBox:getChildById('autoSsaCheck') then exBox:getChildById('autoSsaCheck'):setChecked(de.ssaEnabled == true) end
  if exBox:getChildById('autoSsaHpEdit') then exBox:getChildById('autoSsaHpEdit'):setText(tostring(de.ssaHp or 60)) end
  if exBox:getChildById('autoMightCheck') then exBox:getChildById('autoMightCheck'):setChecked(de.mightEnabled == true) end
  if exBox:getChildById('autoMightHpEdit') then exBox:getChildById('autoMightHpEdit'):setText(tostring(de.mightHp or 60)) end
  if exBox:getChildById('autoEringCheck') then exBox:getChildById('autoEringCheck'):setChecked(de.eringEnabled == true) end
  if exBox:getChildById('autoEringHpEdit') then exBox:getChildById('autoEringHpEdit'):setText(tostring(de.eringHp or 45)) end
  renderSpellSlot(exBox:getChildById('recoverySlot'), vp.healing.recovery)
  exBox:getChildById('recoverySpellCheck'):setChecked(vp.healing.recovery.enabled == true)
  exBox:getChildById('recoveryPctEdit'):setText(tostring(vp.healing.recovery.pct or 95))
  exBox:getChildById('enableHealingCheck'):setChecked(vp.healing.enabled == true)

  -- Sio & Mas Res UI
  local sioBox = panels.healing:getChildById('sioHealingContainer'):getChildById('sioBox')
  sioBox:getChildById('sioEnableCheck'):setChecked(vp.healing.sio.enabled == true)
  sioBox:getChildById('sioSelfHpEdit'):setText(tostring(vp.healing.sio.selfHp or 70))
  sioBox:getChildById('sioSelfMpEdit'):setText(tostring(vp.healing.sio.selfMp or 15))
  sioBox:getChildById('granSioEnableCheck'):setChecked(vp.healing.granSio.enabled == true)
  for _, vName in ipairs({'Knight', 'Paladin', 'Monk', 'Sorcerer', 'Druid'}) do
    local vr = sioBox:getChildById('sioVoc' .. vName)
    local vd = vp.healing.sio.vocs[vName]
    if vr and vd then
      vr:getChildById('vocCheck'):setText(vName)
      vr:getChildById('vocCheck'):setChecked(vd.enabled ~= false)
      vr:getChildById('vocHpEdit'):setText(tostring(vd.hp or 80))
      vr:getChildById('vocPrioEdit'):setText(tostring(vd.prio or 1))
    end
  end
  local sioFilt = panels.healing:getChildById('sioHealingContainer'):getChildById('sioFiltersBox')
  sioFilt:getChildById('sioPartyCheck'):setChecked(vp.healing.sioFilters.party ~= false)
  sioFilt:getChildById('sioGuildCheck'):setChecked(vp.healing.sioFilters.guild ~= false)
  sioFilt:getChildById('sioAllScreenCheck'):setChecked(vp.healing.sioFilters.allScreen == true)
  sioFilt:getChildById('sioFriendsEdit'):setText(vp.healing.sioFilters.extraFriends or '')

  local masBox = panels.healing:getChildById('masResHealingContainer'):getChildById('masResBox')
  renderSpellSlot(masBox:getChildById('masResSlot'), vp.healing.masRes)
  masBox:getChildById('masResEnableCheck'):setChecked(vp.healing.masRes.enabled == true)
  masBox:getChildById('masResCountEdit'):setText(tostring(vp.healing.masRes.minPlayers or 2))
  masBox:getChildById('masResHpEdit'):setText(tostring(vp.healing.masRes.hp or 85))
  masBox:getChildById('masResMpEdit'):setText(tostring(vp.healing.masRes.selfMp or 20))
  masBox:getChildById('masResCheckParty'):setChecked(vp.healing.masRes.checkParty ~= false)
  masBox:getChildById('masResCheckGuild'):setChecked(vp.healing.masRes.checkGuild ~= false)
  masBox:getChildById('masResIncludeSelf'):setChecked(vp.healing.masRes.includeSelf ~= false)

  -- 2. Tools UI
end

function setupHealingCallbacks()
  -- Healing Extra Slots & Checkboxes
  local exBox = panels.healing:getChildById('selfHealingContainer'):getChildById('extraHealingBox')
  bindSlotClicks(exBox:getChildById('cureParaSlot'), function()
    local vp = getVocProfile()
    openSpellSelector('Select Anti-Paralyze Spell', 'haste', vp.healing.curePara, function(sp)
      vp.healing.curePara.words, vp.healing.curePara.name, vp.healing.curePara.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(exBox:getChildById('cureParaSlot'), vp.healing.curePara)
    end)
  end, function()
    local vp = getVocProfile()
    vp.healing.curePara.words, vp.healing.curePara.clientId = '', 0
    renderSpellSlot(exBox:getChildById('cureParaSlot'), vp.healing.curePara)
  end)
  exBox:getChildById('cureParaCheck').onCheckChange = function(w, checked)
    getVocProfile().healing.curePara.enabled = checked
    saveCurrentProfile()
  end

  bindSlotClicks(exBox:getChildById('quickSioSlot'), function()
    local vp = getVocProfile()
    openSpellSelector('Select Quick Sio Spell', 'party', vp.healing.partyHeal, function(sp)
      vp.healing.partyHeal.words, vp.healing.partyHeal.name, vp.healing.partyHeal.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(exBox:getChildById('quickSioSlot'), vp.healing.partyHeal)
    end)
  end, function()
    local vp = getVocProfile()
    vp.healing.partyHeal.words, vp.healing.partyHeal.clientId = '', 0
    renderSpellSlot(exBox:getChildById('quickSioSlot'), vp.healing.partyHeal)
  end)
  exBox:getChildById('quickSioCheck').onCheckChange = function(w, checked)
    getVocProfile().healing.partyHeal.enabled = checked
    saveCurrentProfile()
  end

  bindSlotClicks(exBox:getChildById('manaShieldSlot'), function()
    local vp = getVocProfile()
    openSpellSelector('Select Magic Shield Spell', 'manashield', vp.healing.manaShield, function(sp)
      vp.healing.manaShield.words, vp.healing.manaShield.name, vp.healing.manaShield.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(exBox:getChildById('manaShieldSlot'), vp.healing.manaShield)
      saveCurrentProfile()
    end)
  end, function()
    local vp = getVocProfile()
    vp.healing.manaShield.words, vp.healing.manaShield.clientId = '', 0
    renderSpellSlot(exBox:getChildById('manaShieldSlot'), vp.healing.manaShield)
    saveCurrentProfile()
  end)
  exBox:getChildById('manaShieldCheck').onCheckChange = function(w, checked)
    getVocProfile().healing.manaShield.enabled = checked
    saveCurrentProfile()
  end
  if exBox:getChildById('utamoBelowEdit') then
    exBox:getChildById('utamoBelowEdit').onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then getVocProfile().healing.manaShield.belowHp = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end
    end
  end
  if exBox:getChildById('utamoRecoverCheck') then
    exBox:getChildById('utamoRecoverCheck').onCheckChange = function(w, checked)
      getVocProfile().healing.manaShield.removeOnRecovery = checked
      saveCurrentProfile()
    end
  end
  if exBox:getChildById('utamoAboveEdit') then
    exBox:getChildById('utamoAboveEdit').onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then getVocProfile().healing.manaShield.aboveHp = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end
    end
  end
  if exBox:getChildById('antiLagCheck') then
    exBox:getChildById('antiLagCheck').onCheckChange = function(w, checked)
      getVocProfile().healing.manaShield.antiLag = checked
      saveCurrentProfile()
    end
  end
  if exBox:getChildById('autoSsaCheck') then
    exBox:getChildById('autoSsaCheck').onCheckChange = function(w, ch) getVocProfile().healing.defEquip.ssaEnabled = ch saveCurrentProfile() end
    exBox:getChildById('autoSsaHpEdit').onTextChange = function(w, txt) local n = tonumber(txt) if n then getVocProfile().healing.defEquip.ssaHp = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end end
    exBox:getChildById('autoMightCheck').onCheckChange = function(w, ch) getVocProfile().healing.defEquip.mightEnabled = ch saveCurrentProfile() end
    exBox:getChildById('autoMightHpEdit').onTextChange = function(w, txt) local n = tonumber(txt) if n then getVocProfile().healing.defEquip.mightHp = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end end
    exBox:getChildById('autoEringCheck').onCheckChange = function(w, ch) getVocProfile().healing.defEquip.eringEnabled = ch saveCurrentProfile() end
    exBox:getChildById('autoEringHpEdit').onTextChange = function(w, txt) local n = tonumber(txt) if n then getVocProfile().healing.defEquip.eringHp = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end end
  end

  bindSlotClicks(exBox:getChildById('recoverySlot'), function()
    local vp = getVocProfile()
    openSpellSelector('Select Recovery Spell', 'recovery', vp.healing.recovery, function(sp)
      vp.healing.recovery.words, vp.healing.recovery.name, vp.healing.recovery.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(exBox:getChildById('recoverySlot'), vp.healing.recovery)
      saveCurrentProfile()
    end)
  end, function()
    local vp = getVocProfile()
    vp.healing.recovery.words, vp.healing.recovery.clientId = '', 0
    renderSpellSlot(exBox:getChildById('recoverySlot'), vp.healing.recovery)
    saveCurrentProfile()
  end)
  exBox:getChildById('recoverySpellCheck').onCheckChange = function(w, checked)
    getVocProfile().healing.recovery.enabled = checked
    saveCurrentProfile()
  end
  exBox:getChildById('recoveryPctEdit').onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then getVocProfile().healing.recovery.pct = math.max(0, math.min(100, math.floor(n))) saveCurrentProfile() end
  end
  exBox:getChildById('enableHealingCheck').onCheckChange = function(w, checked)
    getVocProfile().healing.enabled = checked
    updateStatsUI()
    saveCurrentProfile()
  end

  -- Sio & Mas Res Wiring
  local sioBox = panels.healing:getChildById('sioHealingContainer'):getChildById('sioBox')
  sioBox:getChildById('sioEnableCheck').onCheckChange = function(w, ch) getVocProfile().healing.sio.enabled = ch saveCurrentProfile() end
  sioBox:getChildById('granSioEnableCheck').onCheckChange = function(w, ch) getVocProfile().healing.granSio.enabled = ch saveCurrentProfile() end
  sioBox:getChildById('sioSelfHpEdit').onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then
      local v = math.max(0, math.min(100, math.floor(n)))
      local vp = getVocProfile()
      vp.healing.sio.selfHp = v
      vp.healing.granSio.selfHp = v
      saveCurrentProfile()
    end
  end
  sioBox:getChildById('sioSelfMpEdit').onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then
      local v = math.max(0, math.min(100, math.floor(n)))
      local vp = getVocProfile()
      vp.healing.sio.selfMp = v
      vp.healing.granSio.selfMp = v
      saveCurrentProfile()
    end
  end
  for _, vName in ipairs({'Knight', 'Paladin', 'Monk', 'Sorcerer', 'Druid'}) do
    local vr = sioBox:getChildById('sioVoc' .. vName)
    vr:getChildById('vocCheck').onCheckChange = function(w, ch)
      local vp = getVocProfile()
      vp.healing.sio.vocs[vName].enabled = ch
      vp.healing.granSio.vocs[vName].enabled = ch
      saveCurrentProfile()
    end
    vr:getChildById('vocHpEdit').onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        local hp = math.max(0, math.min(100, math.floor(n)))
        local vp = getVocProfile()
        vp.healing.sio.vocs[vName].hp = hp
        vp.healing.granSio.vocs[vName].hp = math.max(10, hp - 20)
        saveCurrentProfile()
      end
    end
    vr:getChildById('vocPrioEdit').onTextChange = function(w, txt)
      local n = tonumber(txt)
      if n then
        local pr = math.max(1, math.min(5, math.floor(n)))
        local vp = getVocProfile()
        vp.healing.sio.vocs[vName].prio = pr
        vp.healing.granSio.vocs[vName].prio = pr
        saveCurrentProfile()
      end
    end
  end
  local sioFilt = panels.healing:getChildById('sioHealingContainer'):getChildById('sioFiltersBox')
  sioFilt:getChildById('sioPartyCheck').onCheckChange = function(w, ch) getVocProfile().healing.sioFilters.party = ch saveCurrentProfile() end
  sioFilt:getChildById('sioGuildCheck').onCheckChange = function(w, ch) getVocProfile().healing.sioFilters.guild = ch saveCurrentProfile() end
  sioFilt:getChildById('sioAllScreenCheck').onCheckChange = function(w, ch) getVocProfile().healing.sioFilters.allScreen = ch saveCurrentProfile() end
  sioFilt:getChildById('sioFriendsEdit').onTextChange = function(w, txt) getVocProfile().healing.sioFilters.extraFriends = txt saveCurrentProfile() end

  local masBox = panels.healing:getChildById('masResHealingContainer'):getChildById('masResBox')
  bindSlotClicks(masBox:getChildById('masResSlot'), function()
    local mr = getVocProfile().healing.masRes
    openSpellSelector('Select Mas Res Spell', 'party', mr, function(sp)
      mr.words, mr.name, mr.clientId = sp.words, sp.name, sp.clientId
      renderSpellSlot(masBox:getChildById('masResSlot'), mr)
    end)
  end, function()
    local mr = getVocProfile().healing.masRes
    mr.words, mr.clientId = '', 0
    renderSpellSlot(masBox:getChildById('masResSlot'), mr)
  end)
  masBox:getChildById('masResEnableCheck').onCheckChange = function(w, ch) getVocProfile().healing.masRes.enabled = ch saveCurrentProfile() end
  masBox:getChildById('masResCountEdit').onTextChange = function(w, txt) local n = tonumber(txt) if n then getVocProfile().healing.masRes.minPlayers = math.max(1, math.min(20, math.floor(n))) saveCurrentProfile() end end
  masBox:getChildById('masResHpEdit').onTextChange = function(w, txt) local n = tonumber(txt) if n then getVocProfile().healing.masRes.hp = math.max(1, math.min(100, math.floor(n))) saveCurrentProfile() end end
  masBox:getChildById('masResMpEdit').onTextChange = function(w, txt) local n = tonumber(txt) if n then getVocProfile().healing.masRes.selfMp = math.max(0, math.min(100, math.floor(n))) saveCurrentProfile() end end
  masBox:getChildById('masResCheckParty').onCheckChange = function(w, ch) getVocProfile().healing.masRes.checkParty = ch saveCurrentProfile() end
  masBox:getChildById('masResCheckGuild').onCheckChange = function(w, ch) getVocProfile().healing.masRes.checkGuild = ch saveCurrentProfile() end
  masBox:getChildById('masResIncludeSelf').onCheckChange = function(w, ch) getVocProfile().healing.masRes.includeSelf = ch saveCurrentProfile() end

  -- Tools Tab Wiring
end

local function equipDefenseItemById(player, itemId, slot)
  if g_game.equipItemId then
    g_game.equipItemId(itemId)
    return true
  end
  for _, container in pairs(g_game.getContainers() or {}) do
    for _, item in ipairs(container:getItems() or {}) do
      if item and item:getId() == itemId then
        g_game.move(item, { x = 65535, y = slot, z = 0 }, 1)
        return true
      end
    end
  end
  return false
end

function runHealingTick(player, pPos, now, hpPct, mpPct, inPz, isParalyzed, hasUtamo, vp)
  -- 1. AUTO HEALING (Unlimited Spells & Potions + Strict Module Gate)
  local okHeal, errHeal = pcall(function()
    if vp.healing.enabled then
      local ms = vp.healing.manaShield or {}
      local isMage = (currentVocName == 'Sorcerer' or currentVocName == 'Druid' or currentVocName == 'Monk')
      local curPing = (g_game.getPing and g_game.getPing()) or 0
      local highPing = ms.antiLag and curPing >= (ms.antiLagPing or 200)
      local msSpell = (ms.words and ms.words ~= '') and ms.words or 'utamo vita'

      if highPing and not inPz and not hasUtamo and isMage and (now - lastAutoUtamoTime) >= 1000 then
        g_game.talk(msSpell)
        antiLagShieldActive = true
        lastAutoUtamoTime = now
        lastCastTime = now
      elseif antiLagShieldActive and ms.antiLag and curPing <= 180 and hasUtamo and (now - lastAutoUtamoTime) >= 1000 then
        g_game.talk('exana vita')
        antiLagShieldActive = false
        lastAutoUtamoTime = now
        lastCastTime = now
      elseif ms.enabled and isMage and ms.words ~= '' and not inPz and (now - lastAutoUtamoTime) >= 1000 then
        if hpPct <= (ms.belowHp or 100) and not hasUtamo then
          g_game.talk(ms.words)
          lastAutoUtamoTime = now
          lastCastTime = now
        elseif ms.removeOnRecovery and hpPct >= (ms.aboveHp or 70) and hasUtamo then
          g_game.talk('exana vita')
          lastAutoUtamoTime = now
          lastCastTime = now
        end
      end

      local de = vp.healing.defEquip
      if de and not inPz and (now - lastEquipDefenseTime) >= 200 then
        if de.ssaEnabled and hpPct <= (de.ssaHp or 60) then
          local neck = player:getInventoryItem(InventorySlotNeck)
          local nid = neck and neck:getId() or 0
          if nid ~= 3081 and nid ~= 9302 then
            equipDefenseItemById(player, 3081, InventorySlotNeck)
          end
        end
        local finger = player:getInventoryItem(InventorySlotFinger)
        local fid = finger and finger:getId() or 0
        if de.eringEnabled and hpPct <= (de.eringHp or 45) then
          if fid ~= 3088 and fid ~= 3051 then
            equipDefenseItemById(player, 3051, InventorySlotFinger)
          end
        elseif de.mightEnabled and hpPct <= (de.mightHp or 60) then
          if fid ~= 3048 then
            equipDefenseItemById(player, 3048, InventorySlotFinger)
          end
        end
        lastEquipDefenseTime = now
      end

      if vp.healing.curePara.enabled and vp.healing.curePara.words ~= '' and isParalyzed and (now - lastCastTime) >= 250 then
        g_game.talk(vp.healing.curePara.words)
        lastCastTime = now
      end

      if (now - lastCastTime) >= 950 then
        for _, sp in ipairs(getSortedHealSpells(vp.healing.spells)) do
          if sp and sp.enabled ~= false and sp.words and sp.words ~= '' and mpPct >= (tonumber(sp.minMp) or 0)
            and not isSpellOnClientCooldown(sp.words, now) then
            local thresh = tonumber(sp.pct) or 80
            local triggered = false
            if sp.mode == 'mp_low' then
              triggered = (mpPct <= thresh)
            elseif sp.mode == 'mp_high' then
              triggered = (mpPct >= thresh)
            else
              triggered = (hpPct <= thresh)
            end
            if triggered then
              g_game.talk(sp.words)
              lastCastTime = now
              break
            end
          end
        end
      end

      if (now - lastPotionTime) >= 950 then
        for _, pt in ipairs(vp.healing.potions) do
          if pt and pt.enabled ~= false and pt.id and pt.id > 0 then
            local thresh = tonumber(pt.pct) or 50
            local shouldUse = false
            if pt.ptype == 'mp' and mpPct <= thresh then
              shouldUse = true
            elseif pt.ptype ~= 'mp' and hpPct <= thresh then
              shouldUse = true
            end
            if shouldUse then
              g_game.useInventoryItemWith(pt.id, player)
              lastPotionTime = now
              break
            end
          end
        end
      end

      if currentVocName == 'Druid' or currentVocName == 'Monk' then
        local function resolveFriendVocRule(cfg, p)
          if not cfg or not cfg.vocs then return nil end
          local vocName = getCreatureVocName(p)
          if vocName then
            return cfg.vocs[vocName]
          end
          if cfg.vocs.Knight and cfg.vocs.Knight.enabled then
            return cfg.vocs.Knight
          end
          local bestRule = nil
          for _, r in pairs(cfg.vocs) do
            if type(r) == 'table' and r.enabled then
              if not bestRule or (tonumber(r.hp) or 0) > (tonumber(bestRule.hp) or 0) then
                bestRule = r
              end
            end
          end
          return bestRule
        end

        local function tryFriendHealConfig(cfg)
          if not cfg or not cfg.enabled or not cfg.words or cfg.words == '' then return false end
          if hpPct < (cfg.selfHp or 60) or mpPct < (cfg.selfMp or 15) then return false end
          if isSpellOnClientCooldown(cfg.words, now) then return false end
          local bestCandidate, bestEff = nil, 999
          for _, p in ipairs(nearbyPlayers) do
            local fp = p:getPosition()
            if fp and fp.z == pPos.z and math.abs(pPos.x - fp.x) <= 7 and math.abs(pPos.y - fp.y) <= 5
               and isFriendAllowed(p, vp.healing.sioFilters) then
              local vRule = resolveFriendVocRule(cfg, p)
              if vRule and vRule.enabled then
                local fHp = p:getHealthPercent()
                if fHp <= (vRule.hp or 80) then
                  local eff = fHp - ((5 - (tonumber(vRule.prio) or 3)) * 8)
                  if eff < bestEff then
                    bestEff, bestCandidate = eff, p
                  end
                end
              end
            end
          end
          if bestCandidate then
            g_game.talk(cfg.words .. ' "' .. bestCandidate:getName())
            lastCastTime = now
            return true
          end
          return false
        end

        if (now - lastCastTime) >= 1000 then
          local granHandled = (currentVocName == 'Druid') and tryFriendHealConfig(vp.healing.granSio) or false
          local mrHandled = false
          if not granHandled then
            local mr = vp.healing.masRes
            if mr and mr.enabled and mr.words ~= '' and mpPct >= (mr.selfMp or 20)
               and not isSpellOnClientCooldown(mr.words, now) then
              local lowFriends = 0
              local mrThresh = mr.hp or 85
              if mr.includeSelf ~= false and hpPct <= mrThresh then lowFriends = lowFriends + 1 end
              for _, p in ipairs(nearbyPlayers) do
                if getDistanceBetween(pPos, p:getPosition()) <= 3 and isFriendAllowed(p, { party = mr.checkParty, guild = mr.checkGuild }) then
                  if p:getHealthPercent() <= mrThresh then lowFriends = lowFriends + 1 end
                end
              end
              if lowFriends >= (mr.minPlayers or 2) then
                g_game.talk(mr.words)
                lastCastTime = now
                mrHandled = true
              end
            end
          end
          if not granHandled and not mrHandled then
            if not tryFriendHealConfig(vp.healing.sio) and vp.healing.partyHeal.enabled and vp.healing.partyHeal.words ~= ''
               and not isSpellOnClientCooldown(vp.healing.partyHeal.words, now) then
              local minHp = vp.healing.sio and vp.healing.sio.selfHp or 60
              local minMp = vp.healing.sio and vp.healing.sio.selfMp or 15
              if hpPct >= minHp and mpPct >= minMp then
                for _, p in ipairs(nearbyPlayers) do
                  local fp = p:getPosition()
                  if fp and fp.z == pPos.z and math.abs(pPos.x - fp.x) <= 7 and math.abs(pPos.y - fp.y) <= 5
                     and isFriendAllowed(p, vp.healing.sioFilters) and p:getHealthPercent() <= (vp.healing.partyHeal.pct or 75) then
                    g_game.talk(vp.healing.partyHeal.words .. ' "' .. p:getName())
                    lastCastTime = now
                    break
                  end
                end
              end
            end
          end
        end
      end

      if vp.healing.recovery.enabled and vp.healing.recovery.words ~= '' and not inPz
        and hpPct <= (vp.healing.recovery.pct or 95)
        and (now - (ruleCooldowns.recovery or -60000)) >= 60000 and (now - lastCastTime) >= 950 then
        g_game.talk(vp.healing.recovery.words)
        ruleCooldowns.recovery = now
        lastCastTime = now
      end
    end
  end)
  if not okHeal then helperTickError('healing', errHeal) end

end
