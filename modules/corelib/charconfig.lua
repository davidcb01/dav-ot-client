CharConfig = {}

local cache = {}
local dirty = {}
local pendingSaveEvents = {}
local migratedNodes = {}

local function normKey(key)
  if type(key) ~= 'string' or #key == 0 then
    return 'Default'
  end
  return key
end

function CharConfig.encodeKey(key)
  local k = normKey(key)
  if k == '.' or k == '..' then
    return 'Default'
  end
  local encoded = k:gsub('([^A-Za-z0-9_%-])', function(c)
    return string.format('~%02X', string.byte(c))
  end)
  if #encoded == 0 then
    return 'Default'
  end
  return encoded
end

function CharConfig.decodeKey(filename)
  local base = filename:gsub('%.json$', '')
  return base:gsub('~(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

local function ensureNsDir(ns)
  if not g_resources.directoryExists('/settings') then
    pcall(function() g_resources.makeDir('/settings') end)
  end
  local dir = '/settings/' .. ns
  if not g_resources.directoryExists(dir) then
    pcall(function() g_resources.makeDir(dir) end)
  end
  return dir
end

local function getFilePath(ns, key)
  return '/settings/' .. ns .. '/' .. CharConfig.encodeKey(key) .. '.json'
end

local function isDenseArray(t)
  local count = 0
  local maxIdx = 0
  for k in pairs(t) do
    if type(k) ~= 'number' or k < 1 or k % 1 ~= 0 then
      return false, 0
    end
    if k > maxIdx then
      maxIdx = k
    end
    count = count + 1
  end
  return count == maxIdx, maxIdx
end

local function sanitizeForJson(val, seen)
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

  seen = seen or {}
  if seen[val] then
    return nil
  end
  seen[val] = true

  local dense, maxIdx = isDenseArray(val)
  local out = {}
  if dense then
    for i = 1, maxIdx do
      local sv = sanitizeForJson(val[i], seen)
      if sv ~= nil then
        out[i] = sv
      end
    end
  else
    local numKeys = {}
    for k, v in pairs(val) do
      local kt = type(k)
      if kt == 'string' or kt == 'number' then
        local sv = sanitizeForJson(v, seen)
        if sv ~= nil then
          local sk = kt == 'number' and tostring(k) or k
          out[sk] = sv
          if kt == 'number' then
            table.insert(numKeys, sk)
          end
        end
      end
    end
    if #numKeys > 0 then
      out.__numKeys = numKeys
    end
  end

  seen[val] = nil
  return out
end

local function restoreFromJson(val)
  if type(val) ~= 'table' then
    return val
  end
  local numKeys = val.__numKeys
  if type(numKeys) == 'table' then
    val.__numKeys = nil
    local restoredNum = {}
    for _, sk in ipairs(numKeys) do
      local nk = tonumber(sk)
      if nk ~= nil and val[sk] ~= nil then
        restoredNum[nk] = restoreFromJson(val[sk])
        val[sk] = nil
      end
    end
    for k, v in pairs(val) do
      val[k] = restoreFromJson(v)
    end
    for nk, nv in pairs(restoredNum) do
      val[nk] = nv
    end
    return val
  end
  for k, v in pairs(val) do
    val[k] = restoreFromJson(v)
  end
  return val
end

local function readJsonFile(path)
  if not g_resources.fileExists(path) then
    return nil
  end
  local ok, raw = pcall(function()
    return g_resources.readFileContents(path)
  end)
  if not ok or type(raw) ~= 'string' or #raw == 0 then
    return nil
  end
  local decOk, decoded = pcall(function()
    return json.decode(raw)
  end)
  if not decOk or type(decoded) ~= 'table' then
    return nil
  end
  if decoded.__charConfigV1 and type(decoded.data) == 'table' then
    return decoded.key, restoreFromJson(decoded.data)
  end
  return nil, restoreFromJson(decoded)
end

local function writeJsonFile(path, key, data)
  local payload = {
    __charConfigV1 = true,
    key = normKey(key),
    data = sanitizeForJson(type(data) == 'table' and data or {})
  }
  local ok, encoded = pcall(function()
    return json.encode(payload, 2)
  end)
  if not ok or type(encoded) ~= 'string' then
    g_logger.error('[CharConfig] Failed to encode ' .. tostring(path) .. ': ' .. tostring(encoded))
    return false
  end
  local wOk, wErr = pcall(function()
    g_resources.writeFileContents(path, encoded)
  end)
  if not wOk then
    g_logger.error('[CharConfig] Failed to write ' .. tostring(path) .. ': ' .. tostring(wErr))
    return false
  end
  return true
end

function CharConfig.migrateLegacyNode(ns, legacyRootNode)
  if not legacyRootNode or migratedNodes[ns .. ':' .. legacyRootNode] then
    return
  end
  migratedNodes[ns .. ':' .. legacyRootNode] = true
  local dir = ensureNsDir(ns)
  local marker = dir .. '/.migrated'
  if g_resources.fileExists(marker) then
    return
  end
  local legacy = g_settings.getNode(legacyRootNode)
  if type(legacy) == 'table' then
    for k, v in pairs(legacy) do
      if type(k) == 'string' and #k > 0 and type(v) == 'table' then
        local path = getFilePath(ns, k)
        if not g_resources.fileExists(path) then
          writeJsonFile(path, k, v)
        end
      end
    end
  end
  pcall(function() g_resources.writeFileContents(marker, '1') end)
end

function CharConfig.exists(ns, key, legacyRootNode)
  local k = normKey(key)
  local path = getFilePath(ns, k)
  if g_resources.fileExists(path) then
    return true
  end
  if legacyRootNode then
    local legacy = g_settings.getNode(legacyRootNode)
    if type(legacy) == 'table' and type(legacy[k]) == 'table' then
      return true
    end
  end
  return false
end

function CharConfig.load(ns, key, legacyRootNode, forceDisk)
  local k = normKey(key)
  local ck = k:lower()
  cache[ns] = cache[ns] or {}

  if not forceDisk and type(cache[ns][ck]) == 'table' then
    return cache[ns][ck]
  end

  local path = getFilePath(ns, k)
  local _, diskData = readJsonFile(path)
  if type(diskData) == 'table' then
    cache[ns][ck] = diskData
    return diskData
  end

  if legacyRootNode and not g_resources.fileExists('/settings/' .. ns .. '/.migrated') then
    CharConfig.migrateLegacyNode(ns, legacyRootNode)
    local _, migratedData = readJsonFile(path)
    if type(migratedData) == 'table' then
      cache[ns][ck] = migratedData
      return migratedData
    end
  end

  return nil
end

function CharConfig.getOrCreate(ns, key, legacyRootNode)
  local existing = CharConfig.load(ns, key, legacyRootNode, false)
  if type(existing) == 'table' then
    return existing
  end
  local k = normKey(key)
  local ck = k:lower()
  cache[ns] = cache[ns] or {}
  cache[ns][ck] = {}
  return cache[ns][ck]
end

function CharConfig.set(ns, key, data, saveNow)
  local k = normKey(key)
  local ck = k:lower()
  cache[ns] = cache[ns] or {}
  cache[ns][ck] = type(data) == 'table' and data or {}
  if saveNow then
    return CharConfig.save(ns, k)
  end
  return true
end

function CharConfig.save(ns, key)
  local k = normKey(key)
  local ck = k:lower()
  cache[ns] = cache[ns] or {}
  local data = cache[ns][ck]
  if type(data) ~= 'table' then
    return false
  end
  ensureNsDir(ns)
  local ok = writeJsonFile(getFilePath(ns, k), k, data)
  if ok and dirty[ns] then
    dirty[ns][ck] = nil
  end
  return ok
end

function CharConfig.scheduleSave(ns, key, delayMs)
  local k = normKey(key)
  local ck = k:lower()
  dirty[ns] = dirty[ns] or {}
  dirty[ns][ck] = k

  local timerId = ns .. '\0' .. ck
  if pendingSaveEvents[timerId] then
    removeEvent(pendingSaveEvents[timerId])
  end
  pendingSaveEvents[timerId] = scheduleEvent(function()
    pendingSaveEvents[timerId] = nil
    CharConfig.save(ns, k)
  end, delayMs or 250)
end

function CharConfig.flushNamespace(ns)
  for timerId, ev in pairs(pendingSaveEvents) do
    if timerId:sub(1, #ns + 1) == (ns .. '\0') then
      removeEvent(ev)
      pendingSaveEvents[timerId] = nil
    end
  end
  if dirty[ns] then
    local list = {}
    for _, k in pairs(dirty[ns]) do
      table.insert(list, k)
    end
    for _, k in ipairs(list) do
      CharConfig.save(ns, k)
    end
  end
end

function CharConfig.flushAll()
  local namespaces = {}
  for ns in pairs(dirty) do
    table.insert(namespaces, ns)
  end
  for _, ns in ipairs(namespaces) do
    CharConfig.flushNamespace(ns)
  end
end

function CharConfig.delete(ns, key)
  local k = normKey(key)
  local ck = k:lower()
  if cache[ns] then
    cache[ns][ck] = nil
  end
  if dirty[ns] then
    dirty[ns][ck] = nil
  end
  local path = getFilePath(ns, k)
  if g_resources.fileExists(path) then
    pcall(function() g_resources.deleteFile(path) end)
  end
end

function CharConfig.listKeys(ns, legacyRootNode)
  if legacyRootNode then
    CharConfig.migrateLegacyNode(ns, legacyRootNode)
  end
  local dir = ensureNsDir(ns)
  local seen = {}
  local keys = {}
  local files = g_resources.listDirectoryFiles(dir) or {}
  for _, fname in ipairs(files) do
    if fname:match('%.json$') then
      local storedKey = readJsonFile(dir .. '/' .. fname)
      local keyName = (type(storedKey) == 'string' and #storedKey > 0) and storedKey or CharConfig.decodeKey(fname)
      local norm = keyName:lower()
      if not seen[norm] then
        seen[norm] = true
        table.insert(keys, keyName)
      end
    end
  end
  return keys
end

connect(g_game, {
  onGameEnd = function() CharConfig.flushAll() end
})
connect(g_app, {
  onExit = function() CharConfig.flushAll() end
})
