-- Settings tab UI and profile management actions

function setSettingsStatus(msg, color)
  if not panels.settings then return end
  local box = panels.settings:getChildById('savedProfilesBox')
  local lbl = box and box:getChildById('settingsStatusLabel')
  if lbl then
    lbl:setText(msg)
    if color then lbl:setColor(color) end
  end
end

function syncLanguageCombos()
  refreshingLanguageCombos = true
  local lang = getHelperLanguage()
  if helperWindow then
    local bar = helperWindow:getChildById('bottomBar')
    local cb = bar and bar:getChildById('helperLangCombo')
    if cb and cb.setCurrentOptionByData then
      cb:setCurrentOptionByData(lang, true)
    end
  end
  if panels.settings then
    local curBox = panels.settings:getChildById('currentProfileBox')
    local cb = curBox and curBox:getChildById('settingsLangCombo')
    if cb and cb.setCurrentOptionByData then
      cb:setCurrentOptionByData(lang, true)
    end
  end
  refreshingLanguageCombos = false
end

function refreshSettingsTabUI()
  if not panels.settings then return end
  local curBox = panels.settings:getChildById('currentProfileBox')
  if curBox then
    local charLbl = curBox:getChildById('settingsCharValueLabel')
    local vocLbl = curBox:getChildById('settingsVocValueLabel')
    if charLbl then
      local n = (currentCharName and #currentCharName > 0) and currentCharName or ht('Offline')
      charLbl:setText(n)
    end
    if vocLbl then
      vocLbl:setText(currentVocName or ht('Unknown'))
    end
  end

  local tmplBox = panels.settings:getChildById('saveTemplateBox')
  local tmplEdit = tmplBox and tmplBox:getChildById('templateNameEdit')
  if tmplEdit then
    local pName = (currentCharName and #currentCharName > 0) and currentCharName or ''
    if pName ~= '' and tmplEdit:getText() == '' then
      tmplEdit:setText(pName)
    end
  end

  local box = panels.settings:getChildById('savedProfilesBox')
  local list = box and box:getChildById('profilesList')
  if not list then return end

  list:destroyChildren()
  local all = getAllHelperProfiles()
  local activeKey = getProfileStorageKey()
  local names = {}
  for name, cfg in pairs(all) do
    if type(cfg) == 'table' then
      table.insert(names, name)
    end
  end
  table.sort(names, function(a, b)
    if a == activeKey then return true end
    if b == activeKey then return false end
    return a:lower() < b:lower()
  end)

  if selectedProfileListKey and type(all[selectedProfileListKey]) ~= 'table' then
    selectedProfileListKey = nil
  end
  if not selectedProfileListKey and #names > 0 then
    selectedProfileListKey = names[1]
  end

  for _, name in ipairs(names) do
    local cfg = all[name]
    local row = g_ui.createWidget('ProfileListRow', list)
    local isActive = (name == activeKey)
    local nameLbl = row:getChildById('profileNameLabel')
    local metaLbl = row:getChildById('profileMetaLabel')
    if nameLbl then
      nameLbl:setText(isActive and (name .. ht(' [Current]')) or name)
      nameLbl:setColor(isActive and '#ffdd66' or '#efefef')
    end
    local vocCount = 0
    if type(cfg.vocProfiles) == 'table' then
      for _ in pairs(cfg.vocProfiles) do vocCount = vocCount + 1 end
    end
    local langTag = (cfg.language == 'pt') and 'PT-BR' or 'EN'
    if metaLbl then
      metaLbl:setText(langTag .. ' | ' .. htf('%d vocs', vocCount))
    end
    row.profileKey = name
    row.onClick = function(w)
      selectedProfileListKey = w.profileKey
      list:focusChild(w, MouseFocusReason)
    end
    row.onDoubleClick = function(w)
      selectedProfileListKey = w.profileKey
      onSettingsCopySelectedProfile()
    end
    if name == selectedProfileListKey then
      list:focusChild(row, MouseFocusReason)
    end
  end
end


function onSettingsSaveCurrent()
  saveCurrentProfile()
  refreshSettingsTabUI()
  local key = getProfileStorageKey()
  local msg = htf('Saved profile for "%s".', key)
  setSettingsStatus(msg, '#88ff88')
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] ' .. msg)
  end
end

function onSettingsReloadCurrent()
  local key = getProfileStorageKey()
  loadCharacterProfile(key)
  rebuildShortcutBindings()
  local msg = htf('Reloaded saved profile for "%s".', key)
  setSettingsStatus(msg, '#88ccff')
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] ' .. msg)
  end
end

function onSettingsResetDefault()
  local keepLang = (charConfig and charConfig.language) or 'en'
  charConfig = normalizeCharConfig(createDefaultCharConfig())
  charConfig.language = keepLang
  getVocProfile(currentVocName)
  saveCurrentProfile()
  loadProfileIntoUI()
  rebuildShortcutBindings()
  local msg = htf('Profile "%s" reset to defaults.', getProfileStorageKey())
  setSettingsStatus(msg, '#ffdd66')
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] ' .. msg)
  end
end

function onSettingsSaveTemplate()
  if not panels.settings then return end
  local box = panels.settings:getChildById('saveTemplateBox')
  local edit = box and box:getChildById('templateNameEdit')
  local raw = edit and edit:getText() or ''
  local clean = raw:gsub('^%s+', ''):gsub('%s+$', '')
  if clean == '' then
    setSettingsStatus(ht('Enter a template name first.'), '#ff7777')
    return
  end
  saveHelperStoredProfile(clean, normalizeCharConfig(deepCopy(charConfig)))
  if edit then
    local pName = (currentCharName and #currentCharName > 0) and currentCharName or ''
    edit:setText(pName)
  end
  selectedProfileListKey = clean
  refreshSettingsTabUI()
  local msg = htf('Saved template copy "%s".', clean)
  setSettingsStatus(msg, '#88ff88')
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] ' .. msg)
  end
end

function onSettingsCopySelectedProfile()
  if not selectedProfileListKey or selectedProfileListKey == '' then
    setSettingsStatus(ht('Select a saved profile from the list first.'), '#ff7777')
    return
  end
  local src = loadHelperStoredProfile(selectedProfileListKey)
  if type(src) ~= 'table' then
    setSettingsStatus(ht('Select a saved profile from the list first.'), '#ff7777')
    return
  end
  local prevPos = charConfig and charConfig.windowPos and deepCopy(charConfig.windowPos) or nil
  charConfig = normalizeCharConfig(deepCopy(src))
  if prevPos then
    charConfig.windowPos = prevPos
  end
  getVocProfile(currentVocName)
  saveCurrentProfile()
  loadProfileIntoUI()
  rebuildShortcutBindings()
  local msg = htf('Loaded profile "%s" into "%s".', selectedProfileListKey, getProfileStorageKey())
  setSettingsStatus(msg, '#88ff88')
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] ' .. msg)
  end
end

function onSettingsDeleteSelectedProfile()
  if not selectedProfileListKey or selectedProfileListKey == '' then
    setSettingsStatus(ht('Select a saved profile from the list first.'), '#ff7777')
    return
  end
  local activeKey = getProfileStorageKey()
  if selectedProfileListKey == activeKey then
    setSettingsStatus(ht('Cannot delete the active character profile (use Reset to Default).'), '#ffaa55')
    return
  end
  local deletedName = selectedProfileListKey
  deleteHelperStoredProfile(deletedName)
  selectedProfileListKey = nil
  refreshSettingsTabUI()
  setSettingsStatus(htf('Deleted profile "%s".', deletedName), '#ffdd66')
end

