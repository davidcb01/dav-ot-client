local EXPORTS_VDIR = '/exports'
local ctx = {
    options = nil,
    getPanels = nil,
    setOption = nil,
    flushSave = nil,
    onImportCharOptions = nil
}

local activeExportModal = nil
local activeImportModal = nil
local styleImported = false

local SKIP_SETTINGS_KEYS = {
    account = true,
    password = true,
    uuid = true,
    host = true,
    port = true,
    httpLogin = true,
    ['client-version'] = true,
    DAVHelperConfig = true,
    DAVHelperCharConfigs = true
}

local NODE_SETTINGS_KEYS = {
    'CharOptions',
    'CharMiniWindows',
    'containers',
    'ImbuementTracker',
    'control_buttons',
    'QuickSellBlacklist',
    'LastCombatControls',
    'Minimap',
    'VipList',
    'BattleList',
    'BattleListInstances',
    'IgnorePlayers',
    'WhitelistedPlayers',
    'lastChannelsOpen',
    'game_interface',
    'game_console',
    'skills-hide',
    'healthcircle_skilltypes',
    'controls-presets'
}

local VALUE_SETTINGS_KEYS = {
    'controls-preset-current',
    'listKeybindsPanel',
    'UseIgnoreList',
    'UseWhiteList',
    'IgnorePrivateMessages',
    'IgnoreYelling',
    'enableAudio',
    'enableScreenshots',
    'onlyCaptureGameWindow',
    'LevelUp',
    'SkillUp',
    'Achievement',
    'BestiaryEntryUnlocked',
    'BestiaryEntryCompleted',
    'TreasureFound',
    'ValuableLoot',
    'BossDefeated',
    'DeathPvE',
    'DeathPvP',
    'PlayerKill',
    'PlayerKillAssist',
    'PlayerAttacking',
    'HighestDamageDealt',
    'HighestHealingDone',
    'LowHealth',
    'GiftofLifeTriggered',
    'healthcircle_opacity',
    'healthcircle_hpcircle',
    'healthcircle_mpcircle',
    'healthcircle_expcircle',
    'healthcircle_skillcircle',
    'healthcircle_distfromcenter',
    'statsbar_dimension',
    'statsbar_placement',
    'mainpanel_shrink_options',
    'showHorizontalLeftPanel',
    'showHorizontalRightPanel',
    'showCustomisableStatusBars',
    'showStatusBars',
    'last-used-character',
    'last-used-world'
}

local function trim(s)
    if type(s) ~= 'string' then return '' end
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function ensureVDir(vdir)
    if type(vdir) ~= 'string' or #vdir == 0 then return end
    local clean = vdir:gsub('^/+', ''):gsub('/+$', '')
    local acc = ''
    for part in clean:gmatch('[^/]+') do
        acc = acc .. '/' .. part
        if not g_resources.directoryExists(acc) then
            pcall(function() g_resources.makeDir(acc) end)
        end
    end
end

local function ensureParentVDir(vpath)
    local dir = vpath:match('^(.+)/[^/]+$')
    if dir and #dir > 0 then
        ensureVDir(dir)
    end
end

local function getRealWriteDir()
    local wd = g_resources.getWriteDir() or ''
    wd = wd:gsub('\\', '/')
    if wd:sub(-1) ~= '/' then
        wd = wd .. '/'
    end
    return wd
end

local function getRealExportsDir()
    ensureVDir(EXPORTS_VDIR)
    return getRealWriteDir() .. 'exports'
end

local function sanitizeFileName(rawName, defaultPrefix)
    local name = trim(rawName)
    name = name:gsub('[\\/:*?"<>|]', '_')
    name = name:gsub('^%.+', '')
    if #name == 0 then
        name = defaultPrefix .. '_' .. os.date('%Y-%m-%d_%H-%M-%S')
    end
    if not name:lower():match('%.json$') then
        name = name .. '.json'
    end
    return name
end

local function collectVFilesRecursive(vdir, outMap, skipSubdirName)
    if not g_resources.directoryExists(vdir) then return end
    local ok, entries = pcall(function() return g_resources.listDirectoryFiles(vdir) end)
    if not ok or type(entries) ~= 'table' then return end
    for _, entry in ipairs(entries) do
        if entry ~= '.' and entry ~= '..' and entry ~= skipSubdirName then
            local child = vdir .. '/' .. entry
            if g_resources.directoryExists(child) then
                collectVFilesRecursive(child, outMap, nil)
            else
                local rOk, content = pcall(function() return g_resources.readFileContents(child) end)
                if rOk and type(content) == 'string' then
                    outMap[child] = content
                end
            end
        end
    end
end

local function sanitizeSettingsTable(val, seen)
    if CharConfig and CharConfig.sanitize then
        return CharConfig.sanitize(val, seen)
    end
    local vt = type(val)
    if vt == 'string' or vt == 'boolean' then
        return val
    elseif vt == 'number' then
        if val ~= val or val <= -math.huge or val >= math.huge then
            return nil
        end
        return val
    elseif vt ~= 'table' then
        return nil
    end
    return val
end

local function collectClientBundle(includeMinimap, fileName)
    if ctx.flushSave then pcall(ctx.flushSave) end
    if CharConfig and CharConfig.flushAll then pcall(CharConfig.flushAll) end
    if Keybind and Keybind.configs then
        for _, cfg in pairs(Keybind.configs.keybinds or {}) do
            pcall(function() cfg:save() end)
        end
        for _, cfg in pairs(Keybind.configs.hotkeys or {}) do
            pcall(function() cfg:save() end)
        end
    end

    local exportedOptions = {}
    if type(ctx.options) == 'table' then
        for k, obj in pairs(ctx.options) do
            if type(k) == 'string' and not SKIP_SETTINGS_KEYS[k] then
                local v = (type(obj) == 'table') and obj.value or obj
                local vt = type(v)
                if vt == 'boolean' or vt == 'number' or vt == 'string' then
                    exportedOptions[k] = v
                end
            end
        end
    end

    local settingsNodes = {}
    for _, key in ipairs(NODE_SETTINGS_KEYS) do
        if g_settings.exists(key) then
            if key == 'controls-presets' then
                local list = g_settings.getList(key)
                if type(list) == 'table' and #list > 0 then
                    settingsNodes[key] = sanitizeSettingsTable(list)
                end
            else
                local node = g_settings.getNode(key)
                if type(node) == 'table' then
                    settingsNodes[key] = sanitizeSettingsTable(node)
                end
            end
        end
    end

    for _, key in ipairs(VALUE_SETTINGS_KEYS) do
        if g_settings.exists(key) then
            local v = g_settings.get(key)
            if v ~= nil and v ~= '' then
                settingsNodes['__val:' .. key] = v
            end
        end
    end

    -- Collect per-character Bestiary/Bosstiary trackers from /config.otml
    local okOtml, otmlText = pcall(function() return g_resources.readFileContents('/config.otml') end)
    if okOtml and type(otmlText) == 'string' then
        for line in otmlText:gmatch('[^\r\n]+') do
            local key = line:match('^([A-Za-z0-9_%-]+):%s*$')
            if key and (key:match('^bestiaryTracker_') or key:match('^bosstiaryTracker_')) then
                local node = g_settings.getNode(key)
                if type(node) == 'table' then
                    settingsNodes[key] = sanitizeSettingsTable(node)
                end
            end
        end
    end

    local files = {}
    collectVFilesRecursive('/settings', files, 'davhelper')
    collectVFilesRecursive('/controls', files, nil)
    collectVFilesRecursive('/characterdata', files, nil)

    local minimapFile = nil
    local minimapCopied = false
    if includeMinimap then
        local srcMap = getRealWriteDir() .. 'minimap.otmm'
        local f = io.open(srcMap, 'rb')
        if f then
            f:close()
            local base = fileName:gsub('%.json$', '')
            local mapName = base .. '_minimap.otmm'
            local dstMap = getRealExportsDir() .. '/' .. mapName
            local okCopy = pcall(function() return g_platform.copyFile(srcMap, dstMap) end)
            if okCopy then
                local chk = io.open(dstMap, 'rb')
                if chk then
                    chk:close()
                    minimapFile = mapName
                    minimapCopied = true
                end
            end
        end
    end

    return {
        format = 'davot_client_bundle',
        version = 1,
        exportedAt = os.date('%Y-%m-%d %H:%M:%S'),
        options = exportedOptions,
        settingsNodes = settingsNodes,
        files = files,
        minimapFile = minimapFile
    }, minimapCopied
end

local function isSafeClientVPath(vpath)
    if type(vpath) ~= 'string' or vpath:find('%.%.') or vpath:find('\\') then
        return false
    end
    if vpath:match('^/settings/davhelper/') or vpath == '/settings/davhelper' then
        return false
    end
    return vpath:match('^/settings/') or vpath:match('^/controls/') or vpath:match('^/characterdata/')
end

local function applyClientBundle(bundle, sourceDirReal, importMinimap)
    if type(bundle) ~= 'table' or bundle.format ~= 'davot_client_bundle' then
        return false, 'This file is not a valid Client backup.'
    end

    if ctx.flushSave then pcall(ctx.flushSave) end
    if CharConfig and CharConfig.flushAll then pcall(CharConfig.flushAll) end
    if Keybind and Keybind.unloadAllConfigs then
        pcall(Keybind.unloadAllConfigs)
    end

    local restoredFiles = 0
    local restoredNamespaces = {}
    if type(bundle.files) == 'table' then
        for vpath, content in pairs(bundle.files) do
            if isSafeClientVPath(vpath) and type(content) == 'string' then
                ensureParentVDir(vpath)
                local wOk = pcall(function() g_resources.writeFileContents(vpath, content) end)
                if wOk then
                    restoredFiles = restoredFiles + 1
                    local ns = vpath:match('^/settings/([^/]+)/')
                    if ns and ns ~= 'davhelper' then
                        restoredNamespaces[ns] = true
                    end
                end
            end
        end
    end

    if CharConfig and CharConfig.clearCache then
        for ns in pairs(restoredNamespaces) do
            CharConfig.clearCache(ns)
        end
        CharConfig.clearCache('char_options')
        CharConfig.clearCache('char_miniwindows')
    end

    if type(bundle.settingsNodes) == 'table' then
        for key, val in pairs(bundle.settingsNodes) do
            if type(key) == 'string' then
                if key:sub(1, 6) == '__val:' then
                    local rawKey = key:sub(7)
                    if not SKIP_SETTINGS_KEYS[rawKey] then
                        pcall(function() g_settings.setValue(rawKey, tostring(val)) end)
                    end
                elseif key == 'controls-presets' and type(val) == 'table' then
                    local listCopy = {}
                    for i = 1, #val do
                        if type(val[i]) == 'string' then table.insert(listCopy, val[i]) end
                    end
                    if #listCopy > 0 then
                        pcall(function() g_settings.setList('controls-presets', listCopy) end)
                    end
                elseif not SKIP_SETTINGS_KEYS[key] and type(val) == 'table' then
                    local restored = (CharConfig and CharConfig.restore) and CharConfig.restore(val) or val
                    pcall(function() g_settings.setNode(key, restored) end)
                end
            end
        end
    end

    local appliedOptions = 0
    if type(bundle.options) == 'table' and type(ctx.options) == 'table' and ctx.setOption then
        -- Apply general options first, then resolve mouseControlMode last
        for k, v in pairs(bundle.options) do
            if not SKIP_SETTINGS_KEYS[k] and k ~= 'mouseControlMode' and ctx.options[k] ~= nil then
                local okSet = pcall(ctx.setOption, k, v, true)
                if okSet then
                    appliedOptions = appliedOptions + 1
                end
            end
        end
        if bundle.options.mouseControlMode ~= nil and ctx.options.mouseControlMode ~= nil then
            pcall(ctx.setOption, 'mouseControlMode', tonumber(bundle.options.mouseControlMode) or 0, true)
        end
    end

    if Keybind and Keybind.reloadFromDisk then
        pcall(Keybind.reloadFromDisk)
    end

    local panels = ctx.getPanels and ctx.getPanels() or nil
    if panels and panels.keybindsPanel and panels.keybindsPanel.presets and panels.keybindsPanel.presets.list and Keybind then
        local listWidget = panels.keybindsPanel.presets.list
        listWidget:clearOptions()
        for _, preset in ipairs(Keybind.presets or {}) do
            listWidget:addOption(preset, preset)
        end
        if Keybind.currentPreset then
            listWidget:setCurrentOption(Keybind.currentPreset, true)
        end
        if updateKeybinds then
            pcall(updateKeybinds)
        end
    end

    if modules.game_actionbar and modules.game_actionbar.selectHotkeySet and Keybind and Keybind.currentPreset then
        pcall(modules.game_actionbar.selectHotkeySet, Keybind.currentPreset)
    end

    if ctx.onImportCharOptions then
        pcall(ctx.onImportCharOptions)
    end

    local minimapImported = false
    if importMinimap and type(bundle.minimapFile) == 'string' and #bundle.minimapFile > 0 and not bundle.minimapFile:find('[\\/:]') then
        local candidates = {}
        if sourceDirReal and #sourceDirReal > 0 then
            table.insert(candidates, sourceDirReal .. '/' .. bundle.minimapFile)
        end
        table.insert(candidates, getRealExportsDir() .. '/' .. bundle.minimapFile)
        local dstMap = getRealWriteDir() .. 'minimap.otmm'
        for _, srcMap in ipairs(candidates) do
            local f = io.open(srcMap, 'rb')
            if f then
                f:close()
                pcall(function() g_platform.copyFile(srcMap, dstMap) end)
                minimapImported = true
                break
            end
        end
    end

    if ctx.flushSave then pcall(ctx.flushSave) end
    return true, {
        files = restoredFiles,
        options = appliedOptions,
        minimap = minimapImported
    }
end

local function readBundleFromInput(rawInput)
    local clean = trim(rawInput):gsub('^"(.-)"$', '%1')
    if #clean == 0 then
        return nil, nil, 'Select a file or enter a .json file path.'
    end

    local rawText = nil
    local sourceDirReal = getRealExportsDir()

    -- Check virtual /exports/ path first if bare filename or /exports/
    if not clean:find('\\') and not clean:find(':') then
        local vpath = clean:sub(1, 1) == '/' and clean or (EXPORTS_VDIR .. '/' .. clean)
        if g_resources.fileExists(vpath) then
            local okRead, content = pcall(function() return g_resources.readFileContents(vpath) end)
            if okRead and type(content) == 'string' then
                rawText = content
            end
        end
    end

    if not rawText then
        local normPath = clean:gsub('\\', '/')
        local f, err = io.open(normPath, 'rb')
        if f then
            rawText = f:read('*a')
            f:close()
            sourceDirReal = normPath:match('^(.+)/[^/]+$') or sourceDirReal
        else
            return nil, nil, 'File not found: ' .. clean
        end
    end

    if type(rawText) ~= 'string' or #rawText == 0 then
        return nil, nil, 'Empty or unreadable file.'
    end

    local okDec, decoded = pcall(json.decode, rawText)
    if not okDec or type(decoded) ~= 'table' then
        return nil, nil, 'Invalid or corrupted JSON file.'
    end
    return decoded, sourceDirReal, nil
end

local function destroyExportModal()
    if activeExportModal then
        activeExportModal:destroy()
        activeExportModal = nil
    end
end

local function destroyImportModal()
    if activeImportModal then
        activeImportModal:destroy()
        activeImportModal = nil
    end
end

local function openExportModal(mode)
    if not styleImported then
        g_ui.importStyle('styles/misc/transfer')
        styleImported = true
    end
    destroyExportModal()
    destroyImportModal()

    local modal = g_ui.createWidget('TransferExportModal', g_ui.getRootWidget())
    activeExportModal = modal

    local isHelper = (mode == 'helper')
    modal:setText(isHelper and 'Export Helper Settings' or 'Export Client Settings')

    local infoLbl = modal:getChildById('infoLabel')
    local nameEdit = modal:getChildById('fileNameEdit')
    local extraCheck = modal:getChildById('extraCheck')
    local statusLbl = modal:getChildById('statusLabel')
    local confirmBtn = modal:getChildById('buttonsRow'):getChildById('confirmBtn')
    local cancelBtn = modal:getChildById('buttonsRow'):getChildById('cancelBtn')

    local stamp = os.date('%Y-%m-%d_%H-%M-%S')
    if isHelper then
        infoLbl:setText('Saves all DAVCaster Helper profiles (Healing, Target, Shooter, Cavebot, Tools and Settings) into a .json file in exports/.')
        nameEdit:setText('davot_helper_' .. stamp .. '.json')
        extraCheck:hide()
    else
        infoLbl:setText('Saves client options, hotkeys, keybinds, presets, action bars and windows/containers into a .json file (no passwords).')
        nameEdit:setText('davot_client_' .. stamp .. '.json')
        extraCheck:show()
        extraCheck:setChecked(false)
    end

    cancelBtn.onClick = function() destroyExportModal() end
    modal.onEscape = function() destroyExportModal() end

    confirmBtn.onClick = function()
        local fname = sanitizeFileName(nameEdit:getText(), isHelper and 'davot_helper' or 'davot_client')
        ensureVDir(EXPORTS_VDIR)
        local vpath = EXPORTS_VDIR .. '/' .. fname
        local realPath = getRealExportsDir() .. '\\' .. fname

        if isHelper then
            if not modules.game_helper or type(modules.game_helper.exportAllConfigs) ~= 'function' then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Error: DAVCaster Helper is not loaded.')
                return
            end
            local okExp, bundle = pcall(modules.game_helper.exportAllConfigs)
            if not okExp or type(bundle) ~= 'table' then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Failed to collect Helper profiles.')
                return
            end
            local okEnc, encoded = pcall(json.encode, bundle, 2)
            if not okEnc or type(encoded) ~= 'string' then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Failed to encode Helper JSON.')
                return
            end
            local okWrite = pcall(function() g_resources.writeFileContents(vpath, encoded) end)
            if not okWrite then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Failed to write file into exports/.')
                return
            end
            destroyExportModal()
            displayInfoBox('Export Helper', string.format('Exported successfully (%d profile(s))!\nFile: %s\n\nUse "Open Exports Folder" under Options -> Misc. to copy the file.', bundle.count or 0, realPath))
        else
            local okCol, bundle, minimapCopied = pcall(collectClientBundle, extraCheck:isChecked(), fname)
            if not okCol or type(bundle) ~= 'table' then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Failed to collect client settings.')
                return
            end
            local okEnc, encoded = pcall(json.encode, bundle, 2)
            if not okEnc or type(encoded) ~= 'string' then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Failed to encode client JSON.')
                return
            end
            local okWrite = pcall(function() g_resources.writeFileContents(vpath, encoded) end)
            if not okWrite then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Failed to write file into exports/.')
                return
            end
            destroyExportModal()
            local extraNote = ''
            if extraCheck:isChecked() then
                extraNote = minimapCopied and '\nMinimap copied alongside (_minimap.otmm).' or '\nNote: minimap.otmm was not found in user folder.'
            end
            displayInfoBox('Export Client', string.format('Client settings exported successfully!%s\nFile: %s', extraNote, realPath))
        end
    end

    modal:show()
    modal:raise()
    modal:focus()
    nameEdit:focus()
end

local function populateImportList(modal, expectedFormat)
    local listWidget = modal:getChildById('filesList')
    local pathEdit = modal:getChildById('pathEdit')
    local statusLbl = modal:getChildById('statusLabel')
    listWidget:destroyChildren()
    ensureVDir(EXPORTS_VDIR)

    local okList, entries = pcall(function() return g_resources.listDirectoryFiles(EXPORTS_VDIR) end)
    local names = {}
    if okList and type(entries) == 'table' then
        for _, entry in ipairs(entries) do
            if type(entry) == 'string' and entry:lower():match('%.json$') then
                table.insert(names, entry)
            end
        end
    end
    table.sort(names, function(a, b) return a:lower() > b:lower() end)

    local matchedCount = 0
    for _, fname in ipairs(names) do
        local keep = true
        local okRead, raw = pcall(function() return g_resources.readFileContents(EXPORTS_VDIR .. '/' .. fname) end)
        if okRead and type(raw) == 'string' then
            local okDec, dec = pcall(json.decode, raw)
            if okDec and type(dec) == 'table' and type(dec.format) == 'string' and dec.format ~= expectedFormat then
                keep = false
            end
        end
        if keep then
            local row = g_ui.createWidget('TransferFileRow', listWidget)
            row:setText(fname)
            row.fileName = fname
            row.onMouseRelease = function(self, mousePos, mouseButton)
                if mouseButton == MouseLeftButton then
                    self:focus()
                    pathEdit:setText(self.fileName)
                    return true
                end
            end
            matchedCount = matchedCount + 1
        end
    end

    if matchedCount == 0 then
        statusLbl:setColor('#bbbbbb')
        statusLbl:setText('No backups of this type in exports/ (paste full path above).')
    else
        statusLbl:setText('')
    end
end

local function openImportModal(mode)
    if not styleImported then
        g_ui.importStyle('styles/misc/transfer')
        styleImported = true
    end
    destroyExportModal()
    destroyImportModal()

    local modal = g_ui.createWidget('TransferImportModal', g_ui.getRootWidget())
    activeImportModal = modal

    local isHelper = (mode == 'helper')
    local expectedFormat = isHelper and 'davot_helper_bundle' or 'davot_client_bundle'
    modal:setText(isHelper and 'Import Helper Settings' or 'Import Client Settings')

    local infoLbl = modal:getChildById('infoLabel')
    local pathEdit = modal:getChildById('pathEdit')
    local extraCheck = modal:getChildById('extraCheck')
    local statusLbl = modal:getChildById('statusLabel')
    local btns = modal:getChildById('buttonsRow')
    local openDirBtn = btns:getChildById('openDirBtn')
    local refreshBtn = btns:getChildById('refreshBtn')
    local confirmBtn = btns:getChildById('confirmBtn')
    local cancelBtn = btns:getChildById('cancelBtn')

    if isHelper then
        infoLbl:setText('Select a Helper backup file from exports/ or paste its full path:')
        extraCheck:setText('Apply to current character if profile name differs')
        extraCheck:setChecked(true)
    else
        infoLbl:setText('Select a Client backup file from exports/ or paste its full path:')
        extraCheck:setText('Restore minimap alongside if available (_minimap.otmm)')
        extraCheck:setChecked(true)
    end

    populateImportList(modal, expectedFormat)

    openDirBtn.onClick = function() openExportsDirectory() end
    refreshBtn.onClick = function() populateImportList(modal, expectedFormat) end
    cancelBtn.onClick = function() destroyImportModal() end
    modal.onEscape = function() destroyImportModal() end

    confirmBtn.onClick = function()
        local bundle, sourceDirReal, readErr = readBundleFromInput(pathEdit:getText())
        if not bundle then
            statusLbl:setColor('#ff6666')
            statusLbl:setText(readErr or 'Failed to read file.')
            return
        end
        if bundle.format ~= expectedFormat then
            statusLbl:setColor('#ff6666')
            if bundle.format == 'davot_helper_bundle' then
                statusLbl:setText('This is a Helper backup! Use "Import Helper".')
            elseif bundle.format == 'davot_client_bundle' then
                statusLbl:setText('This is a Client backup! Use "Import Client".')
            else
                statusLbl:setText('Invalid backup file format.')
            end
            return
        end

        if isHelper then
            if not modules.game_helper or type(modules.game_helper.importAllConfigs) ~= 'function' then
                statusLbl:setColor('#ff6666')
                statusLbl:setText('Error: DAVCaster Helper is not loaded.')
                return
            end
            local okCall, okImp, countOrErr, appliedActive = pcall(modules.game_helper.importAllConfigs, bundle, extraCheck:isChecked())
            if not okCall or not okImp then
                statusLbl:setColor('#ff6666')
                statusLbl:setText(tostring(okCall and countOrErr or okImp))
                return
            end
            destroyImportModal()
            local appliedTxt = appliedActive and 'and applied to the current character!' or 'into Helper -> Settings profiles.'
            displayInfoBox('Import Helper', string.format('Imported %d Helper profile(s) %s', tonumber(countOrErr) or 0, appliedTxt))
        else
            local okCall, okImp, resOrErr = pcall(applyClientBundle, bundle, sourceDirReal, extraCheck:isChecked())
            if not okCall or not okImp then
                statusLbl:setColor('#ff6666')
                statusLbl:setText(tostring(okCall and resOrErr or okImp))
                return
            end
            destroyImportModal()
            local minimapTxt = resOrErr.minimap and '\nMinimap restored! Restart the client to reload minimap.otmm and action bars.' or '\nRestart the client if you want to reload all action bars and windows cleanly.'
            displayInfoBox('Import Client', string.format('Client settings imported!\nOptions applied: %d | Files restored: %d%s', resOrErr.options or 0, resOrErr.files or 0, minimapTxt))
        end
    end

    modal:show()
    modal:raise()
    modal:focus()
end

function initTransfer(deps)
    ctx = deps or {}
    ensureVDir(EXPORTS_VDIR)
end

function terminateTransfer()
    destroyExportModal()
    destroyImportModal()
end

function openExportClientModal()
    openExportModal('client')
end

function openImportClientModal()
    openImportModal('client')
end

function openExportHelperModal()
    openExportModal('helper')
end

function openImportHelperModal()
    openImportModal('helper')
end

function openExportsDirectory()
    local realDir = getRealExportsDir()
    if g_platform and g_platform.openDir then
        pcall(function() g_platform.openDir(realDir) end)
    end
end
