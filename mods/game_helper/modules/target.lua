-- Target tab UI, callbacks, and A-I evaluation engine

-- TARGET TAB & CUSTOM IDS MANAGER
-- ============================================================================

function loadSelectedTargetRuleIntoEditor()
  if not panels.target then return end
  local vp = getVocProfile()
  local rules = vp.target.rules or {}
  if not selectedTargetRuleIdx or not rules[selectedTargetRuleIdx] then
    selectedTargetRuleIdx = (#rules > 0) and 1 or nil
  end
  local ed = panels.target:getChildById('targetEditorBox')
  local r = selectedTargetRuleIdx and rules[selectedTargetRuleIdx]
  if not r then return end
  refreshingTargetUI = true
  local isAll = (r.allMonsters ~= false) and ((r.name or '') == '')
  local filterCb = ed:getChildById('tgtFilterCombo')
  if filterCb and filterCb.setCurrentOptionByData then
    filterCb:setCurrentOptionByData(isAll and 'All Monsters' or 'Target Name', true)
  end
  local nameEdit = ed:getChildById('tgtNameEdit')
  if nameEdit:getText() ~= (r.name or '') then nameEdit:setText(r.name or '') end
  nameEdit:setVisible(not isAll)
  local mc = ed:getChildById('tgtModeCombo')
  local ruleMode = (r.mode and r.mode:match('^[A-I]$')) and r.mode or 'A'
  if mc and mc.setCurrentOptionByData then mc:setCurrentOptionByData(ruleMode, true) end
  local hpMinEdit = ed:getChildById('tgtHpMinEdit')
  if hpMinEdit:getText() ~= tostring(r.hpMin or 0) then hpMinEdit:setText(tostring(r.hpMin or 0)) end
  local hpMaxEdit = ed:getChildById('tgtHpMaxEdit')
  if hpMaxEdit:getText() ~= tostring(r.hpMax or 100) then hpMaxEdit:setText(tostring(r.hpMax or 100)) end
  local intCheck = ed:getChildById('tgtInterruptCheck')
  if intCheck then intCheck:setChecked(r.interrupt == true) end
  refreshingTargetUI = false
end

function refreshTargetRulesUI()
  if not panels.target then return end
  local vp = getVocProfile()
  local list = panels.target:getChildById('targetRulesList')
  list:destroyChildren()
  for idx, r in ipairs(vp.target.rules or {}) do
    local row = g_ui.createWidget('TargetRuleRow', list)
    row:getChildById('ruleIdxLabel'):setText(tostring(idx))
    row:getChildById('ruleNameLabel'):setText((r.allMonsters == false or (r.name and r.name ~= '')) and ((r.name and r.name ~= '') and r.name or ht('Target Name...')) or ht('All Monsters'))
    row:getChildById('ruleModeLabel'):setText(ht('Mode ') .. ((r.mode and r.mode:match('^[A-I]$')) and r.mode or 'A'))
    local infoText = string.format('HP %d-%d%%', r.hpMin or 0, r.hpMax or 100)
    if r.interrupt then
      infoText = infoText .. ht(' | [Interrupt]')
    end
    row:getChildById('ruleInfoLabel'):setText(infoText)
    local chk = row:getChildById('ruleEnableCheck')
    chk:setChecked(r.enabled ~= false)
    chk.onCheckChange = function(w, ch)
      r.enabled = ch
      saveCurrentProfile()
    end
    local upBtn = row:getChildById('upBtn')
    local dnBtn = row:getChildById('downBtn')
    local dlBtn = row:getChildById('delBtn')
    if upBtn then
      upBtn.onClick = function()
        selectedTargetRuleIdx = idx
        moveTargetRule(-1)
      end
    end
    if dnBtn then
      dnBtn.onClick = function()
        selectedTargetRuleIdx = idx
        moveTargetRule(1)
      end
    end
    bindDeleteButton(dlBtn, function()
      selectedTargetRuleIdx = idx
      deleteTargetRule()
    end)
    row.ruleIdx = idx
    row.onClick = function(w, mousePos)
      if isClickInsideAnyChild(w, {'ruleEnableCheck', 'upBtn', 'downBtn', 'delBtn'}, mousePos) then
        return
      end
      selectedTargetRuleIdx = w.ruleIdx
      list:focusChild(w, MouseFocusReason)
      loadSelectedTargetRuleIntoEditor()
    end
    if idx == selectedTargetRuleIdx then
      list:focusChild(row, KeyboardFocusReason)
    end
  end
  if not selectedTargetRuleIdx and #(vp.target.rules or {}) > 0 then
    selectedTargetRuleIdx = 1
  end
  loadSelectedTargetRuleIntoEditor()
  installClickOutsideUnfocus(list)
end

function updateSelectedTargetRowLabels()
  if not panels.target or not selectedTargetRuleIdx then return end
  local vp = getVocProfile()
  local r = (vp.target.rules or {})[selectedTargetRuleIdx]
  if not r then return end
  local list = panels.target:getChildById('targetRulesList')
  if not list then return end
  for _, row in ipairs(list:getChildren()) do
    if row.ruleIdx == selectedTargetRuleIdx then
      row:getChildById('ruleNameLabel'):setText((r.allMonsters == false or (r.name and r.name ~= '')) and ((r.name and r.name ~= '') and r.name or ht('Target Name...')) or ht('All Monsters'))
      row:getChildById('ruleModeLabel'):setText(ht('Mode ') .. ((r.mode and r.mode:match('^[A-I]$')) and r.mode or 'A'))
      local infoText = string.format('HP %d-%d%%', r.hpMin or 0, r.hpMax or 100)
      if r.interrupt then
        infoText = infoText .. ht(' | [Interrupt]')
      end
      row:getChildById('ruleInfoLabel'):setText(infoText)
      break
    end
  end
end

function moveTargetRule(delta)
  local vp = getVocProfile()
  local rules = vp.target.rules
  local idx = selectedTargetRuleIdx
  if not idx or not rules[idx] then return end
  local nxt = idx + delta
  if nxt >= 1 and nxt <= #rules then
    rules[idx], rules[nxt] = rules[nxt], rules[idx]
    selectedTargetRuleIdx = nxt
    refreshTargetRulesUI()
    saveCurrentProfile()
  end
end

function deleteTargetRule()
  local vp = getVocProfile()
  local rules = vp.target.rules
  if selectedTargetRuleIdx and rules[selectedTargetRuleIdx] then
    table.remove(rules, selectedTargetRuleIdx)
    if #rules == 0 then
      table.insert(rules, { name = '', allMonsters = true, mode = 'A', hpMin = 0, hpMax = 100, interrupt = false, enabled = true })
    end
    selectedTargetRuleIdx = math.min(#rules, selectedTargetRuleIdx)
    refreshTargetRulesUI()
    saveCurrentProfile()
  end
end

function newTargetRule()
  local vp = getVocProfile()
  table.insert(vp.target.rules, { name = '', allMonsters = true, mode = 'A', hpMin = 0, hpMax = 100, interrupt = false, enabled = true })
  selectedTargetRuleIdx = #vp.target.rules
  refreshTargetRulesUI()
  saveCurrentProfile()
end


function refreshFinisherSettingsUI()
  if not finisherSettingsModal then return end
  local vp = getVocProfile()
  local fin = vp.target.finisher or {}
  refreshingFinisherUI = true
  local mCb = finisherSettingsModal:getChildById('finTopRow'):getChildById('finModeCombo')
  local cCb = finisherSettingsModal:getChildById('finTopRow'):getChildById('finChaseCombo')
  if mCb and mCb.setCurrentOptionByData then mCb:setCurrentOptionByData(fin.mode or 'A', true) end
  if cCb and cCb.setCurrentOptionByData then cCb:setCurrentOptionByData(fin.chaseMode or 'Chase', true) end
  refreshingFinisherUI = false

  local list = finisherSettingsModal:getChildById('finisherList')
  list:destroyChildren()
  local rules = fin.rules or {}
  for idx, r in ipairs(rules) do
    local row = g_ui.createWidget('FinisherRow', list)
    row:getChildById('idxLabel'):setText(tostring(idx))
    row:getChildById('nameLabel'):setText(r.name or '')
    row:getChildById('hpLabel'):setText(string.format('HP<=%d%%', tonumber(r.hp) or 30))
    local enChk = row:getChildById('enableCheck')
    enChk:setChecked(r.enabled ~= false)
    enChk.onCheckChange = function(w, ch)
      local liveFin = getVocProfile().target.finisher
      if liveFin and liveFin.rules[idx] then
        liveFin.rules[idx].enabled = (ch == true)
        saveCurrentProfile()
      end
    end
    row:getChildById('upBtn').onClick = function()
      local liveFin = getVocProfile().target.finisher
      if idx > 1 and liveFin and liveFin.rules[idx] then
        liveFin.rules[idx], liveFin.rules[idx - 1] = liveFin.rules[idx - 1], liveFin.rules[idx]
        refreshFinisherSettingsUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      local liveFin = getVocProfile().target.finisher
      if liveFin and idx < #liveFin.rules then
        liveFin.rules[idx], liveFin.rules[idx + 1] = liveFin.rules[idx + 1], liveFin.rules[idx]
        refreshFinisherSettingsUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      local liveFin = getVocProfile().target.finisher
      if liveFin and liveFin.rules[idx] then
        table.remove(liveFin.rules, idx)
        refreshFinisherSettingsUI()
        saveCurrentProfile()
      end
    end)
  end
  installClickOutsideUnfocus(list)
end

function openFinisherSettingsModal()
  if not finisherSettingsModal then return end
  refreshFinisherSettingsUI()
  finisherSettingsModal:show()
  finisherSettingsModal:raise()
  finisherSettingsModal:focus()
end

function loadTargetUI()
  -- 4. Target UI
  local vp = getVocProfile()
  if panels.target then
    local tgTop = panels.target:getChildById('targetTopBox')
    tgTop:getChildById('targetEnableCheck'):setChecked(vp.target.enabled == true, true)
    tgTop:getChildById('targetDisablePzCheck'):setChecked(vp.target.disablePz ~= false)
    tgTop:getChildById('targetRangeEdit'):setText(tostring(vp.target.maxRange or 7))
    tgTop:getChildById('targetChaseCombo'):setCurrentOptionByData(vp.target.chase and 'Chase' or 'Stand', true)
    tgTop:getChildById('targetKeepCheck'):setChecked(vp.target.keepTarget ~= false)
    if tgTop:getChildById('targetFinisherCheck') then
      tgTop:getChildById('targetFinisherCheck'):setChecked(vp.target.finisher and vp.target.finisher.enabled == true)
    end
    local tgLists = panels.target:getChildById('targetListsBox')
    tgLists:getChildById('targetIgnoreEdit'):setText(vp.target.ignoreList or '')
    refreshTargetRulesUI()
  end

  -- 5. Cavebot UI
end

function setupTargetCallbacks()
  -- Target Tab Wiring
  local tTop = panels.target:getChildById('targetTopBox')
  tTop:getChildById('targetEnableCheck').onCheckChange = function(w, ch)
    if isLoadingUI or refreshingTargetUI then return end
    getVocProfile().target.enabled = (ch == true)
    updateStatsUI()
    saveCurrentProfile()
  end
  tTop:getChildById('targetDisablePzCheck').onCheckChange = function(w, ch)
    getVocProfile().target.disablePz = ch
    saveCurrentProfile()
  end
  tTop:getChildById('targetRangeEdit').onTextChange = function(w, txt)
    if refreshingTargetUI then return end
    local n = tonumber(txt)
    if n then getVocProfile().target.maxRange = math.max(1, math.min(10, math.floor(n))) saveCurrentProfile() end
  end
  local tChaseCb = tTop:getChildById('targetChaseCombo')
  for _, opt in ipairs({ 'Stand', 'Chase' }) do tChaseCb:addOption(ht(opt), opt) end
  tChaseCb.onOptionChange = function(w, text, data)
    if refreshingTargetUI or refreshingLanguageCombos then return end
    local vp = getVocProfile()
    local key = getComboOptionData(w, data or text)
    vp.target.chaseMode = (key == 'Chase') and 'Chase' or 'Stand'
    vp.target.chase = (key == 'Chase')
    saveCurrentProfile()
  end
  tTop:getChildById('targetKeepCheck').onCheckChange = function(w, ch)
    if refreshingTargetUI then return end
    getVocProfile().target.keepTarget = ch
    saveCurrentProfile()
  end
  if tTop:getChildById('targetFinisherCheck') then
    tTop:getChildById('targetFinisherCheck').onCheckChange = function(w, ch)
      if refreshingTargetUI then return end
      local fin = getVocProfile().target.finisher
      if fin then fin.enabled = (ch == true) end
      saveCurrentProfile()
    end
  end

  if finisherSettingsModal then
    local fTop = finisherSettingsModal:getChildById('finTopRow')
    local fModeCb = fTop:getChildById('finModeCombo')
    for _, opt in ipairs({ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I' }) do
      fModeCb:addOption(opt, opt)
    end
    fModeCb.onOptionChange = function(w, text, data)
      if refreshingFinisherUI or refreshingLanguageCombos then return end
      local fin = getVocProfile().target.finisher
      if fin then fin.mode = getComboOptionData(w, data or text) or 'A' saveCurrentProfile() end
    end
    local fChaseCb = fTop:getChildById('finChaseCombo')
    for _, opt in ipairs({ { 'Chase', 'Chase' }, { 'Stand', 'Stand' }, { 'Keep Current', 'Keep' } }) do
      fChaseCb:addOption(ht(opt[1]), opt[2])
    end
    fChaseCb.onOptionChange = function(w, text, data)
      if refreshingFinisherUI or refreshingLanguageCombos then return end
      local fin = getVocProfile().target.finisher
      if fin then fin.chaseMode = getComboOptionData(w, data or text) or 'Chase' saveCurrentProfile() end
    end
    local fAddRow = finisherSettingsModal:getChildById('finAddRow')
    fAddRow:getChildById('finAddBtn').onClick = function()
      local nameEd = fAddRow:getChildById('finNameEdit')
      local hpEd = fAddRow:getChildById('finHpEdit')
      local nm = tostring(nameEd:getText() or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if nm == '' then return end
      local hpVal = math.max(1, math.min(100, math.floor(tonumber(hpEd:getText()) or 30)))
      local fin = getVocProfile().target.finisher
      table.insert(fin.rules, { name = nm, hp = hpVal, enabled = true })
      nameEd:setText('')
      refreshFinisherSettingsUI()
      saveCurrentProfile()
    end
  end

  local tEd = panels.target:getChildById('targetEditorBox')
  local tgtFilterCb = tEd:getChildById('tgtFilterCombo')
  for _, opt in ipairs({ 'All Monsters', 'Target Name' }) do tgtFilterCb:addOption(ht(opt), opt) end
  local tgtModeCb = tEd:getChildById('tgtModeCombo')
  for _, opt in ipairs({ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I' }) do
    tgtModeCb:addOption(opt, opt)
  end
  local function getSelTargetRule()
    local vp = getVocProfile()
    if selectedTargetRuleIdx and vp.target.rules[selectedTargetRuleIdx] then
      return vp.target.rules[selectedTargetRuleIdx]
    end
    return nil
  end
  tgtFilterCb.onOptionChange = function(w, text, data)
    if refreshingTargetUI or refreshingLanguageCombos then return end
    local r = getSelTargetRule()
    if not r then return end
    local key = getComboOptionData(w, data or text)
    r.allMonsters = (key == 'All Monsters')
    if r.allMonsters then r.name = '' end
    refreshTargetRulesUI()
    saveCurrentProfile()
    if not r.allMonsters then
      tEd:getChildById('tgtNameEdit'):focus()
    end
  end
  tEd:getChildById('tgtNameEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingTargetUI then return end
    local r = getSelTargetRule()
    if r then
      r.name = txt
      updateSelectedTargetRowLabels()
      saveCurrentProfile()
    end
  end
  tgtModeCb.onOptionChange = function(w, text, data)
    if isLoadingUI or refreshingTargetUI or refreshingLanguageCombos then return end
    local r = getSelTargetRule()
    if r then r.mode = getComboOptionData(w, data or text) or 'A' updateSelectedTargetRowLabels() saveCurrentProfile() end
  end
  tEd:getChildById('tgtHpMinEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingTargetUI then return end
    local r = getSelTargetRule()
    local n = tonumber(txt)
    if r and n then r.hpMin = math.max(0, math.min(100, math.floor(n))) updateSelectedTargetRowLabels() saveCurrentProfile() end
  end
  tEd:getChildById('tgtHpMaxEdit').onTextChange = function(w, txt)
    if isLoadingUI or refreshingTargetUI then return end
    local r = getSelTargetRule()
    local n = tonumber(txt)
    if r and n then r.hpMax = math.max(0, math.min(100, math.floor(n))) updateSelectedTargetRowLabels() saveCurrentProfile() end
  end
  tEd:getChildById('tgtInterruptCheck').onCheckChange = function(w, ch)
    if refreshingTargetUI then return end
    local r = getSelTargetRule()
    if r then r.interrupt = ch refreshTargetRulesUI() saveCurrentProfile() end
  end

  local tLists = panels.target:getChildById('targetListsBox')
  tLists:getChildById('targetIgnoreEdit').onTextChange = function(w, txt)
    if refreshingTargetUI then return end
    getVocProfile().target.ignoreList = txt
    saveCurrentProfile()
  end

  -- Cavebot Tab Wiring
end

function runTargetTick(player, pPos, now, inPz, vp, nearbyMonsters, currentTarget)
  -- 2. AUTO TARGETING (Modes A-I) & DAVCASTER SHOOTER
  local tgtCfg = vp.target or {}
  local currentTarget = g_game.getAttackingCreature()
  if charConfig.masterEnabled == true and tgtCfg.enabled == true and (not tgtCfg.disablePz or not inPz) then
    local desiredChase = (tgtCfg.chaseMode == 'Chase') and ChaseOpponent or DontChase
    if g_game.getChaseMode() ~= desiredChase then
      g_game.setChaseMode(desiredChase)
    end
    local maxRange = math.max(1, math.min(10, tonumber(tgtCfg.maxRange) or 7))
        local tgtMonsters
    if maxRange <= 7 and (tgtCfg.ignoreList or '') == (vp.shooter.ignoreList or '') then
      tgtMonsters = {}
      for _, m in ipairs(nearbyMonsters) do
        if m.dist <= maxRange then tgtMonsters[#tgtMonsters + 1] = m end
      end
    else
      tgtMonsters = getNearbyMonsters(pPos, maxRange, tgtCfg.ignoreList)
    end
    local ignoreSet = parseCommaSet(tgtCfg.ignoreList)
    if charConfig.cavebot and charConfig.cavebot.enabled and charConfig.cavebot.ignoreUnreachable ~= false and #tgtMonsters > 0 then
      local reachable = {}
      for _, m in ipairs(tgtMonsters) do
        if isMonsterReachable(pPos, m.creature, now) then
          reachable[#reachable + 1] = m
        end
      end
      if #reachable > 0 then
        tgtMonsters = reachable
      elseif isValidMonsterCreature(currentTarget) and not isMonsterReachable(pPos, currentTarget, now) then
        tgtMonsters = {}
      end
    end

    if #tgtMonsters > 0 then
      local function scoreCluster(m)
        local cnt = 0
        local mp = m.creature:getPosition()
        if mp then
          for _, other in ipairs(tgtMonsters) do
            local op = other.creature:getPosition()
            if op and getDistanceBetween(mp, op) <= 3 then cnt = cnt + 1 end
          end
        end
        return cnt
      end

      local function sortByTargetMode(list, modeLetter)
        local m = modeLetter or 'A'
        if m == 'E' then
          for _, item in ipairs(list) do item._cluster = scoreCluster(item) end
        end
        local function modeLess(a, b)
          if m == 'B' then                     -- mais longe
            return a.dist > b.dist
          elseif m == 'C' then                 -- menor vida
            if a.hp ~= b.hp then return a.hp < b.hp end
            return a.dist < b.dist
          elseif m == 'D' then                 -- maior vida
            if a.hp ~= b.hp then return a.hp > b.hp end
            return a.dist < b.dist
          elseif m == 'E' then                 -- melhor cluster
            if (a._cluster or 0) ~= (b._cluster or 0) then return (a._cluster or 0) > (b._cluster or 0) end
            return a.dist < b.dist
          elseif m == 'F' then                 -- perto + menor vida
            if a.dist ~= b.dist then return a.dist < b.dist end
            return a.hp < b.hp
          elseif m == 'G' then                 -- perto + maior vida
            if a.dist ~= b.dist then return a.dist < b.dist end
            return a.hp > b.hp
          elseif m == 'H' then                 -- longe + menor vida
            if a.dist ~= b.dist then return a.dist > b.dist end
            return a.hp < b.hp
          elseif m == 'I' then                 -- longe + maior vida
            if a.dist ~= b.dist then return a.dist > b.dist end
            return a.hp > b.hp
          end
          return a.dist < b.dist               -- A: mais perto
        end
        table.sort(list, function(a, b)
          if modeLess(a, b) then return true end
          if modeLess(b, a) then return false end
          -- empate total: prefere o alvo atual (nao fica trocando a toa), depois id fixo
          local aCur = (a.creature == currentTarget)
          local bCur = (b.creature == currentTarget)
          if aCur ~= bCur then return aCur end
          return (a.creature:getId() or 0) < (b.creature:getId() or 0)
        end)
      end

      local function matchesTargetRule(m, rule)
        local rMin = tonumber(rule.hpMin) or 0
        local rMax = tonumber(rule.hpMax) or 100
        if m.hp < rMin or (rMax > 0 and m.hp > rMax) then
          return false
        end
        local rName = (rule.name or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
        return (rule.allMonsters ~= false) or (rName == '') or (m.name:lower():find(rName, 1, true) ~= nil)
      end

      -- Verifica Finisher (prioridade de cima para baixo quando ativo)
      local chosen = nil
      local finisherActive = false
      local fin = tgtCfg.finisher
      if fin and fin.enabled == true and fin.rules then
        for _, fr in ipairs(fin.rules) do
          if fr and fr.enabled ~= false then
            local fName = tostring(fr.name or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
            local fHp = tonumber(fr.hp) or 30
            if fName ~= '' then
              local cands = {}
              for _, m in ipairs(tgtMonsters) do
                if m.hp > 0 and m.hp <= fHp and m.name:lower():find(fName, 1, true) ~= nil then
                  cands[#cands + 1] = m
                end
              end
              if #cands > 0 then
                finisherActive = true
                local finMode = (fin.mode and fin.mode:match('^[A-I]$')) and fin.mode or 'A'
                sortByTargetMode(cands, finMode)
                chosen = cands[1].creature
                break
              end
            end
          end
        end
      end

      if finisherActive and fin then
        local finChase = fin.chaseMode or 'Chase'
        if finChase == 'Chase' and g_game.getChaseMode() ~= ChaseOpponent then
          g_game.setChaseMode(ChaseOpponent)
        elseif finChase == 'Stand' and g_game.getChaseMode() ~= DontChase then
          g_game.setChaseMode(DontChase)
        end
      end

      -- A cada tick a regra de maior prioridade com candidatos decide o alvo (A-I), mesmo
      -- que o monstro atual esteja com 1% de vida. Troca imediata.
      local anyRule = false
      if not finisherActive then
        for _, rule in ipairs(tgtCfg.rules or {}) do
          if rule and rule.enabled ~= false then
            anyRule = true
            local cands = {}
            for _, m in ipairs(tgtMonsters) do
              if matchesTargetRule(m, rule) then
                cands[#cands + 1] = m
              end
            end
            if #cands > 0 then
              local effMode = (rule.mode and rule.mode:match('^[A-I]$')) and rule.mode or 'A'
              sortByTargetMode(cands, effMode)
              chosen = cands[1].creature
              break
            end
          end
        end
      end

      if not chosen then
        -- nenhuma regra casou: se voce clicou em outro bicho, fica nele ate surgir alvo valido
        local currentInList = false
        if anyRule and isValidMonsterCreature(currentTarget) then
          for _, m in ipairs(tgtMonsters) do
            if m.creature == currentTarget then currentInList = true break end
          end
        end
        if currentInList then
          chosen = currentTarget
        else
          sortByTargetMode(tgtMonsters, 'A')
          chosen = tgtMonsters[1].creature
        end
      end

      if chosen and isValidMonsterCreature(chosen) and chosen ~= currentTarget
         and (now - (ruleCooldowns.attackSent or 0)) >= 150 then
        currentTarget = chosen
        ruleCooldowns.attackSent = now
        g_game.attack(currentTarget)
      end
    end
  end

  return currentTarget
end
