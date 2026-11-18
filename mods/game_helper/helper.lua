-- DAVCaster - Native Helper & Automation for OTClient Redemption
-- Fixed schema normalization, vocation filtering, dynamic lists, minimap waypoints, and OTClient APIs.

helperWindow = nil
statsWindow = nil
helperButton = nil

spellSelectorModal = nil
itemSelectorModal = nil
renamePresetModal = nil
conditionSettingsModal = nil
keyCaptureModal = nil
cavebotSettingsModal = nil
cbControlMiniHud = nil
idsMenuModal = nil
huntListModal = nil

panels = {}
currentTab = 'healing'
currentHealingSubTab = 'self'
currentCharName = nil
currentVocName = 'Knight'
tickEvent = nil
selectedShooterRuleIdx = nil
selectedTargetRuleIdx = nil
selectedCavebotWpIdx = nil

cavebotDirOffset = 'C'
cavebotAutoRec = false
lastAutoRecPos = nil
local cavebotLureActive = false
local cbPauseState = false
local minimapTempFlags = {}
local markedWorldTiles = {}
local lastFollowTargetPos = nil
local followTrail = {}
local lastFollowTrailVec = { x = 0, y = 0 }
local lastFollowTargetDir = South
local lastFollowTargetMoveTime = 0
local followWasTargetOnScreen = false
local followWrongFloorReturn = false
local followWrongFloorTime = 0
local followPrevSafeZ = 0
local followLastMyZ = 0
local followVanishedAtEdge = false
local followLostChaseCount = 0
local followLevitateStep = 0
local followLastLevitateTime = 0
local followLastDoorUseTime = 0
local followLastGoToTime = 0
local followLastDest = nil
local ignoreNativeFollowEvent = false
local isLoadingUI = false
local antiAfkFirstDone = false

local function resetFollowRuntimeState()
  lastFollowTargetPos = nil
  followTrail = {}
  lastFollowTrailVec = { x = 0, y = 0 }
  lastFollowTargetMoveTime = 0
  followWasTargetOnScreen = false
  followWrongFloorReturn = false
  followWrongFloorTime = 0
  followPrevSafeZ = 0
  followLastMyZ = 0
  followVanishedAtEdge = false
  followLostChaseCount = 0
  followLevitateStep = 0
  followLastLevitateTime = 0
  followLastDest = nil
end

local function coerceArray(tbl)
  if type(tbl) ~= 'table' then return {} end
  local indexed = {}
  for k, v in pairs(tbl) do
    local idx = (type(k) == 'number') and k or tonumber(type(k) == 'string' and k:match('^%s*(%d+)%s*$') or nil)
    if idx and idx >= 1 and math.floor(idx) == idx then
      table.insert(indexed, { idx = idx, val = v })
    end
  end
  table.sort(indexed, function(a, b) return a.idx < b.idx end)
  local out = {}
  for i = 1, #indexed do
    out[i] = indexed[i].val
  end
  return out
end

local function coerceIntArray(tbl)
  local raw = coerceArray(tbl)
  local out = {}
  local seen = {}
  for _, v in ipairs(raw) do
    local n = tonumber(v)
    if n and n > 0 and not seen[n] then
      seen[n] = true
      table.insert(out, n)
    end
  end
  return out
end
local activeIdsTab = 'follow'
local activeFollowIdCat = 'stairs'
local selectedProfileListKey = nil
local refreshingLanguageCombos = false

local DEFAULT_FOLLOW_IDS = {
  stairs   = { 8657,8658,1954,469,1947,437,438,607,7544,7546,385,33005,1977,5257,5691,33007,1949,34111,33181,33155,33175,33276,8690,1956,22139,29139,29143,29141 },
  rope     = { 12935, 386 },
  use      = { 1948, 1672, 8618 },
  teleport = { 1949, 33005, 11553, 35498, 34111, 29979, 29980 },
  avoid    = { 8657,8658,1954,469,1947,437,438,607,7544,7546,385,33005,1977,5257,5691,33007,1949,34111,33181,33155,33175,33276,8690,1956,29979,29980,22139,29139,29143,29141 }
}

local activeSpellSlotCallback = nil
local activeSpellSlotSelected = nil
local activeSpellFilterGroup = nil

local activeItemSlotCallback = nil
local activeItemSlotSelected = nil
local activeItemCategoryFilter = nil

local activeKeyCaptureSlot = nil
local activeKeyCaptureBtn = nil

-- Timers & cooldown tracking
local lastCastTime = 0
local lastShooterCastTime = 0
local lastSupportShooterCastTime = 0
local shooterDraftRule = nil
local playerStopTracker = { pos = nil, since = 0 }
local DEFAULT_ADJACENT_SPELLS = {
  ['exori'] = true, ['exori gran'] = true, ['exori min'] = true, ['exori max'] = true,
  ['exeta res'] = true, ['exori mas'] = false, ['exori ico'] = false, ['exori hur'] = false,
  ['exeta amp res'] = false, ['utito tempo'] = false
}
local origGameLook = nil
local lastPotionTime = 0
local lastHasteTime = 0
local lastManaTrainTime = 0
local lastEatTime = -15000
local lastGoldTime = 0
local lastExerciseTime = 0
local lastBlessTime = -30000
local lastBlessVisualState = nil
local lastBlessDialogCoreOk = nil
local lastAfkTime = 0
local lastItemTimerTime = 0
local lastFollowTime = 0
local lastCavebotTime = 0
local lastCavebotStepTime = 0
local ruleCooldowns = {}
local spellCooldownUntil = {}
local confirmedSpellCastAt = {}
local groupCooldownUntil = {}
local shortcutActions = {}
local lastShortcutDesc = nil
local lastShortcutEventTime = 0
local refreshingShooterUI = false
local refreshingTargetUI = false
local targetStopTracker = { id = 0, pos = nil, since = 0 }
local antiStuckTracker = { wpIdx = 0, pos = nil, since = 0 }

function onHelperSpellCooldown(iconId, duration)
  local id = tonumber(iconId)
  if not id then return end
  local dur = tonumber(duration) or 0
  local now = g_clock.millis()
  spellCooldownUntil[id] = (dur > 0) and (now + dur) or 0
  if dur > 0 then
    confirmedSpellCastAt[id] = now
  end
end

function onHelperSpellGroupCooldown(groupId, duration)
  local gid = tonumber(groupId)
  if not gid then return end
  local dur = tonumber(duration) or 0
  groupCooldownUntil[gid] = (dur > 0) and (g_clock.millis() + dur) or 0
end

local function isSpellOnClientCooldown(words, now)
  if not words or words == '' then return false end
  local sp = findSpellByWords(words)
  if not sp then return false end
  if sp.id then
    if (spellCooldownUntil[sp.id] or 0) > now then
      return true
    end
  elseif sp.clientId and (spellCooldownUntil[sp.clientId] or 0) > now then
    return true
  end
  if type(sp.group) == 'table' then
    for gid, _ in pairs(sp.group) do
      local gNum = tonumber(gid) or gid
      if (groupCooldownUntil[gNum] or 0) > now then
        return true
      end
    end
  end
  return false
end

-- Scanned live Exercise Weapons in containers & Training Dummys on screen
local scannedExerciseWeapons = {}
local scannedScreenDummys = {}
local selectedWeaponScanIdx = 1
local selectedDummyScanIdx = 1

-- All 134 Canary Server Food IDs (canary/data/scripts/actions/items/foods.lua)
local CANARY_FOOD_IDS = {
  3606, 3250, 3577, 21145, 21144, 21143, 3578, 3579, 23535, 23545, 3580, 3581, 3582, 3583, 3584,
  3585, 3586, 3587, 3588, 3589, 3590, 3591, 3592, 904, 3593, 3594, 3595, 3596, 3597, 3598, 3599,
  3600, 3601, 3602, 3607, 3723, 3724, 3725, 3726, 3727, 3728, 3729, 3730, 3731, 3732, 5096, 20310,
  5678, 6125, 6277, 6278, 6392, 6393, 6500, 6541, 6542, 6543, 6544, 6545, 6569, 6574, 7158, 7159,
  229, 7373, 7374, 7375, 7376, 7377, 836, 841, 901, 169, 8010, 8011, 8012, 8013, 8014, 8015, 8016,
  8017, 8019, 8177, 8197, 9537, 10329, 10453, 10219, 11459, 11460, 11461, 11462, 11681, 11682,
  11683, 12310, 13992, 14084, 14085, 14681, 15795, 16103, 17457, 17820, 17821, 21146, 22187,
  22185, 24382, 24383, 24396, 24948, 25692, 30198, 30202, 31560, 32069, 37530, 37531, 37532,
  37533, 48116, 48251, 48252, 48253, 48254, 48255, 48256, 48273, 48508, 48509, 48511, 48544
}
local FOOD_ID_SET = {}
for _, fid in ipairs(CANARY_FOOD_IDS) do
  FOOD_ID_SET[fid] = true
end

-- All Canary Exercise Weapon IDs (standard / store / durable / lasting)
local EXERCISE_WEAPON_CATALOG = {
  [50292] = 'Exercise Wraps (Free)', [50293] = 'Exercise Wraps', [50294] = 'Durable Exercise Wraps', [50295] = 'Lasting Exercise Wraps',
  [28540] = 'Exercise Sword (Free)', [28552] = 'Exercise Sword', [35279] = 'Durable Exercise Sword', [35285] = 'Lasting Exercise Sword',
  [28541] = 'Exercise Axe (Free)',   [28553] = 'Exercise Axe',   [35280] = 'Durable Exercise Axe',   [35286] = 'Lasting Exercise Axe',
  [28542] = 'Exercise Club (Free)',  [28554] = 'Exercise Club',  [35281] = 'Durable Exercise Club',  [35287] = 'Lasting Exercise Club',
  [28543] = 'Exercise Bow (Free)',   [28555] = 'Exercise Bow',   [35282] = 'Durable Exercise Bow',   [35288] = 'Lasting Exercise Bow',
  [28544] = 'Exercise Rod (Free)',   [28556] = 'Exercise Rod',   [35283] = 'Durable Exercise Rod',   [35289] = 'Lasting Exercise Rod',
  [28545] = 'Exercise Wand (Free)',  [28557] = 'Exercise Wand',  [35284] = 'Durable Exercise Wand',  [35290] = 'Lasting Exercise Wand',
  [44064] = 'Exercise Shield (Free)',[44065] = 'Exercise Shield',[44066] = 'Durable Exercise Shield',[44067] = 'Lasting Exercise Shield'
}

-- All Canary Exercise Dummy IDs
local EXERCISE_DUMMY_CATALOG = {
  [28558] = 'Exercise Dummy',
  [28559] = 'Ferumbras Exercise Dummy',
  [28560] = 'Ferumbras Exercise Dummy',
  [28561] = 'Demon Exercise Dummy',
  [28562] = 'Demon Exercise Dummy',
  [28563] = 'Monk Exercise Dummy',
  [28564] = 'Monk Exercise Dummy',
  [28565] = 'Exercise Dummy'
}

local function getExerciseWeaponName(id)
  local custom = charConfig and charConfig.customIds and charConfig.customIds.weapons
  if custom and custom[tostring(id)] then return custom[tostring(id)] end
  return EXERCISE_WEAPON_CATALOG[id]
end

local function getExerciseDummyName(id)
  local custom = charConfig and charConfig.customIds and charConfig.customIds.dummys
  if custom and custom[tostring(id)] then return custom[tostring(id)] end
  return EXERCISE_DUMMY_CATALOG[id]
end

local function getFollowIdSet(cat)
  local set = {}
  local list = (charConfig and charConfig.customIds and charConfig.customIds.follow and charConfig.customIds.follow[cat]) or DEFAULT_FOLLOW_IDS[cat] or {}
  for _, v in ipairs(list) do
    local n = tonumber(v)
    if n then set[n] = true end
  end
  return set
end

local ITEM_CATALOG = {
  -- Potions
  { id = 23375, name = 'Supreme Health Potion', desc = 'Restores massive HP (EK 200+)', cat = 'potion', ptype = 'hp' },
  { id = 7643,  name = 'Ultimate Health Potion', desc = 'Restores large HP (EK 130+)', cat = 'potion', ptype = 'hp' },
  { id = 239,   name = 'Great Health Potion', desc = 'Restores medium-high HP', cat = 'potion', ptype = 'hp' },
  { id = 236,   name = 'Strong Health Potion', desc = 'Restores medium HP', cat = 'potion', ptype = 'hp' },
  { id = 266,   name = 'Health Potion', desc = 'Restores basic HP', cat = 'potion', ptype = 'hp' },
  { id = 23373, name = 'Ultimate Mana Potion', desc = 'Restores massive Mana (Mage/RP)', cat = 'potion', ptype = 'mp' },
  { id = 238,   name = 'Great Mana Potion', desc = 'Restores large Mana', cat = 'potion', ptype = 'mp' },
  { id = 237,   name = 'Strong Mana Potion', desc = 'Restores medium Mana', cat = 'potion', ptype = 'mp' },
  { id = 268,   name = 'Mana Potion', desc = 'Restores basic Mana', cat = 'potion', ptype = 'mp' },
  { id = 23374, name = 'Ultimate Spirit Potion', desc = 'Restores HP & Mana (RP 200+)', cat = 'potion', ptype = 'spirit' },
  { id = 7642,  name = 'Great Spirit Potion', desc = 'Restores HP & Mana (RP 80+)', cat = 'potion', ptype = 'spirit' },
  { id = 35563, name = 'Magic Shield Potion', desc = 'Grants Magic Shield (Mage)', cat = 'potion', ptype = 'mp' },
  { id = 49271, name = 'Transcendence Potion', desc = 'Temporary Transcendence boost', cat = 'potion', ptype = 'mp' },

  -- Runes
  { id = 3155,  name = 'Sudden Death Rune', desc = 'Single-target high Death damage', cat = 'rune', target = true },
  { id = 3161,  name = 'Avalanche Rune', desc = 'Area Ice damage (4 sqm radius)', cat = 'rune', target = true },
  { id = 3191,  name = 'Great Fireball Rune', desc = 'Area Fire damage (4 sqm radius)', cat = 'rune', target = true },
  { id = 3202,  name = 'Thunderstorm Rune', desc = 'Area Energy damage', cat = 'rune', target = true },
  { id = 3175,  name = 'Stone Shower Rune', desc = 'Area Earth damage', cat = 'rune', target = true },
  { id = 3158,  name = 'Icicle Rune', desc = 'Single-target Ice damage', cat = 'rune', target = true },
  { id = 3189,  name = 'Fireball Rune', desc = 'Single-target Fire damage', cat = 'rune', target = true },
  { id = 3198,  name = 'Heavy Magic Missile Rune', desc = 'Single-target Energy damage', cat = 'rune', target = true },
  { id = 3179,  name = 'Stalagmite Rune', desc = 'Single-target Earth damage', cat = 'rune', target = true },
  { id = 3200,  name = 'Explosion Rune', desc = 'Small Area Physical damage', cat = 'rune', target = true },
  { id = 3182,  name = 'Holy Missile Rune', desc = 'Single-target Holy damage (Paladin)', cat = 'rune', target = true },
  { id = 3195,  name = 'Soulfire Rune', desc = 'Applies burning condition on target', cat = 'rune', target = true },
  { id = 3192,  name = 'Fire Bomb Rune', desc = 'Area Fire field', cat = 'rune', target = true },
  { id = 3149,  name = 'Energy Bomb Rune', desc = 'Area Energy field', cat = 'rune', target = true },
  { id = 3173,  name = 'Poison Bomb Rune', desc = 'Area Earth field', cat = 'rune', target = true },
  { id = 3180,  name = 'Magic Wall Rune', desc = 'Creates a Magic Wall barrier', cat = 'rune', target = true },
  { id = 3156,  name = 'Wild Growth Rune', desc = 'Creates a Wild Growth barrier (Druid)', cat = 'rune', target = true },
  { id = 3165,  name = 'Paralyze Rune', desc = 'Paralyzes target (Druid)', cat = 'rune', target = true },
  { id = 3160,  name = 'Ultimate Healing Rune', desc = 'Heals target with UH', cat = 'rune', target = false },

  -- Common Timer / Hunt Items
  { id = 3725,  name = 'Brown Mushroom', desc = 'Standard hunt food', cat = 'food' },
  { id = 3048,  name = 'Might Ring', desc = 'Reduces incoming damage by 20%', cat = 'timer' },
  { id = 3081,  name = 'Stone Skin Amulet', desc = 'Reduces Physical & Death by 80%', cat = 'timer' },
  { id = 3051,  name = 'Energy Ring', desc = 'Mana Shield ring', cat = 'timer' },
  { id = 3053,  name = 'Time Ring', desc = '+30 Speed ring', cat = 'timer' },
  { id = 3098,  name = 'Ring of Healing', desc = 'HP & Mana regen ring', cat = 'timer' },
  { id = 6529,  name = 'Pair of Soft Boots', desc = 'High HP/MP regen boots', cat = 'timer' },

  -- Cavebot Tools
  { id = 3003,  name = 'Rope', desc = 'Standard rope for rope spots', cat = 'tool' },
  { id = 646,   name = 'Elvenhair Rope', desc = 'Lightweight rope', cat = 'tool' },
  { id = 3457,  name = 'Shovel', desc = 'Standard shovel for holes', cat = 'tool' },
  { id = 5710,  name = 'Light Shovel', desc = 'Lightweight shovel', cat = 'tool' },
  { id = 9598,  name = 'Whacking Driller of Fate', desc = 'Multi-purpose tool', cat = 'tool' },
  { id = 9596,  name = 'Squeezing Gear of Girlpower', desc = 'Multi-purpose tool', cat = 'tool' },
  { id = 9594,  name = 'Sneaky Stabber of Eliteness', desc = 'Multi-purpose tool', cat = 'tool' }
}

-- Workaround for spells whose clientId in Spells.lua is 0 (e.g. exura vita) or newer 13.x/14.x spells
local SPELL_CLIENTID_OVERRIDES = {
  ['exura vita'] = 3,
  ['exeta res'] = 96,
  ['exeta amp res'] = 111
}

local EXTRA_SPELLS = {
  { id = 239, name = 'Fair Wound Cleansing', words = 'exura med ico', clientId = 4, level = 300, mana = 90, group = { [2] = 1000 }, vocations = { 4, 8 } },
  { name = 'Executioner Throw', words = 'exori amp kor', clientId = 152, level = 300, mana = 225, group = { [1] = 2000 }, vocations = { 4, 8 } },
  { id = 237, name = 'Chivalrous Challenge', words = 'exeta amp res', clientId = 111, level = 150, mana = 80, group = { [3] = 2000 }, vocations = { 4, 8 } },
  { id = 93, name = 'Challenge', words = 'exeta res', clientId = 96, level = 20, mana = 30, group = { [3] = 2000 }, vocations = { 4, 8 } },
  { name = 'Shield Bash', words = 'exori ico scu', clientId = 20, level = 18, mana = 30, group = { [1] = 2000 }, vocations = { 4, 8 } },
  { id = 240, name = 'Great Fire Wave', words = 'exevo gran flam hur', clientId = 102, level = 38, mana = 120, group = { [1] = 2000 }, vocations = { 1, 5 } },
  { id = 241, name = 'Restoration', words = 'exura max vita', clientId = 107, level = 300, mana = 260, group = { [2] = 1000 }, vocations = { 1, 2, 5, 6 } },
  { id = 242, name = 'Nature\'s Embrace', words = 'exura gran sio', clientId = 106, level = 300, mana = 400, group = { [2] = 1000 }, vocations = { 2, 6 } },
  { id = 238, name = 'Divine Dazzle', words = 'exana amp res', clientId = 108, level = 250, mana = 80, group = { [3] = 2000 }, vocations = { 3, 7 } },
  { name = 'Divine Grenade', words = 'exevo tempo mas san', clientId = 155, level = 300, mana = 220, group = { [1] = 2000 }, vocations = { 3, 7 } },
  { name = 'Avatar of Steel', words = 'uteta res eq', clientId = 148, level = 300, mana = 800, group = { [3] = 2000 }, vocations = { 4, 8 } },
  { name = 'Avatar of Light', words = 'uteta res sac', clientId = 149, level = 300, mana = 800, group = { [3] = 2000 }, vocations = { 3, 7 } },
  { name = 'Avatar of Storm', words = 'uteta res ven', clientId = 150, level = 300, mana = 800, group = { [3] = 2000 }, vocations = { 1, 5 } },
  { name = 'Avatar of Nature', words = 'uteta res dru', clientId = 151, level = 300, mana = 800, group = { [3] = 2000 }, vocations = { 2, 6 } },
  -- Monk Spells
  { name = 'Spirit Mend', words = 'exura gran tio', clientId = 184, level = 40, mana = 210, group = { [2] = 1000 }, vocations = { 9, 10 } },
  { name = 'Restore Balance', words = 'exura tio sio', clientId = 184, level = 18, mana = 120, group = { [2] = 1000 }, vocations = { 9, 10 } },
  { name = 'Mass Spirit Mend', words = 'exura mas nia', clientId = 184, level = 150, mana = 250, group = { [2] = 1000 }, vocations = { 9, 10 } },
  { name = 'Virtue of Harmony', words = 'utamo nia', clientId = 162, level = 20, mana = 200, group = { [3] = 2000 }, vocations = { 9, 10 } },
  { name = 'Virtue of Justice', words = 'utito nia', clientId = 163, level = 30, mana = 210, group = { [3] = 2000 }, vocations = { 9, 10 } },
  { name = 'Virtue of Sustain', words = 'utura nia', clientId = 164, level = 60, mana = 210, group = { [3] = 2000 }, vocations = { 9, 10 } },
  { name = 'Focus Harmony', words = 'utevo nia', clientId = 167, level = 275, mana = 500, group = { [3] = 2000 }, vocations = { 9, 10 } },
  { name = 'Focus Serenity', words = 'utamo tempo nia', clientId = 167, level = 150, mana = 450, group = { [3] = 2000 }, vocations = { 9, 10 } },
  { name = 'Balanced Brawl', words = 'exeta pug', clientId = 179, level = 70, mana = 80, group = { [3] = 2000 }, vocations = { 9, 10 } },
  { name = 'Swift Jab', words = 'exori infir pug', clientId = 179, level = 1, mana = 5, group = { [1] = 2000 }, vocations = { 9, 10 } },
  { name = 'Double Jab', words = 'exori pug', clientId = 180, level = 14, mana = 30, group = { [1] = 2000 }, vocations = { 9, 10 } },
  { name = 'Flurry of Blows', words = 'exori gran pug', clientId = 181, level = 35, mana = 110, group = { [1] = 2000 }, vocations = { 9, 10 } },
  { name = 'Sweeping Takedown', words = 'exori mas nia', clientId = 182, level = 60, mana = 195, group = { [1] = 2000 }, vocations = { 9, 10 } },
  { name = 'Devastating Knockout', words = 'exori gran nia', clientId = 181, level = 125, mana = 210, group = { [1] = 2000 }, vocations = { 9, 10 } },
  { name = 'Spiritual Outburst', words = 'exori gran mas nia', clientId = 183, level = 300, mana = 425, group = { [1] = 2000 }, vocations = { 9, 10 } }
}

local function deepCopy(orig)
  if type(orig) ~= 'table' then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = deepCopy(v)
  end
  return copy
end

function getSpellClip(clientId)
  local cid = math.max(1, tonumber(clientId) or 1)
  if Spells and Spells.getImageClip then
    return Spells.getImageClip(cid, 'Default')
  end
  return (((cid - 1) % 12) * 32) .. ' ' .. (math.floor((cid - 1) / 12) * 32) .. ' 32 32'
end

function findSpellByWords(words)
  if not words or words == '' then return nil end
  local w = words:lower():gsub('%s*".*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
  local cidOverride = SPELL_CLIENTID_OVERRIDES[w]
  if SpellInfo and SpellInfo['Default'] then
    for _, sp in pairs(SpellInfo['Default']) do
      if sp.words and sp.words:lower() == w then
        local out = deepCopy(sp)
        if cidOverride and (not out.clientId or out.clientId <= 0) then
          out.clientId = cidOverride
        elseif (not out.clientId or out.clientId <= 0) then
          out.clientId = math.max(1, tonumber(out.id) or 1)
        end
        return out
      end
    end
  end
  for _, ex in ipairs(EXTRA_SPELLS) do
    if ex.words:lower() == w then
      return deepCopy(ex)
    end
  end
  return nil
end

do
  local rawFind = findSpellByWords
  local cache = {}
  function findSpellByWords(words)
    if not words or words == '' then return nil end
    local hit = cache[words]
    if hit == nil then
      hit = rawFind(words) or false
      cache[words] = hit
    end
    return hit or nil
  end
end

function findItemInCatalog(itemId)
  local id = tonumber(itemId) or 0
  if id <= 0 then return nil end
  for _, item in ipairs(ITEM_CATALOG) do
    if item.id == id then return item end
  end
  if EXERCISE_WEAPON_CATALOG[id] then
    return { id = id, name = EXERCISE_WEAPON_CATALOG[id], desc = 'Exercise Weapon', cat = 'exercise' }
  end
  if EXERCISE_DUMMY_CATALOG[id] then
    return { id = id, name = EXERCISE_DUMMY_CATALOG[id], desc = 'Exercise Dummy', cat = 'dummy' }
  end
  return { id = id, name = 'Item #' .. id, desc = 'Custom Item ID ' .. id, cat = 'custom' }
end

function detectPlayerVocation()
  local player = g_game.getLocalPlayer()
  if not player then return currentVocName or 'Knight' end
  if player.isMonk and player:isMonk() then return 'Monk' end
  if player.isDruid and player:isDruid() then return 'Druid' end
  if player.isSorcerer and player:isSorcerer() then return 'Sorcerer' end
  if player.isPaladin and player:isPaladin() then return 'Paladin' end
  if player.isKnight and player:isKnight() then return 'Knight' end
  local voc = player.getVocation and player:getVocation() or 0
  if voc == 5 or voc == 15 or voc == 9 or voc == 10 then return 'Monk'
  elseif voc == 4 or voc == 14 then return 'Druid'
  elseif voc == 3 or voc == 13 then return 'Sorcerer'
  elseif voc == 2 or voc == 12 then return 'Paladin'
  elseif voc == 1 or voc == 11 then return 'Knight'
  end
  return currentVocName or 'Knight'
end

local function getVocMatchTable(vocName)
  if vocName == 'Knight' then return { [4] = true, [8] = true }
  elseif vocName == 'Paladin' then return { [3] = true, [7] = true }
  elseif vocName == 'Sorcerer' then return { [1] = true, [5] = true }
  elseif vocName == 'Druid' then return { [2] = true, [6] = true }
  elseif vocName == 'Monk' then return { [9] = true, [10] = true }
  end
  return { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }
end

-- ============================================================================
-- DEFAULTS & SCHEMA NORMALIZATION (Prevents nil crashes from legacy configs)
-- ============================================================================

local function createDefaultSioSection(isActive, defaultWords)
  return {
    sio = {
      enabled = isActive,
      words = defaultWords or 'exura sio',
      selfHp = 70,
      selfMp = 15,
      vocs = {
        Knight   = { enabled = true,  hp = 85, prio = 1 },
        Paladin  = { enabled = true,  hp = 80, prio = 2 },
        Monk     = { enabled = true,  hp = 80, prio = 2 },
        Sorcerer = { enabled = true,  hp = 75, prio = 3 },
        Druid    = { enabled = true,  hp = 75, prio = 3 }
      }
    },
    granSio = {
      enabled = isActive and (defaultWords ~= 'exura tio sio'),
      words = 'exura gran sio',
      selfHp = 65,
      selfMp = 20,
      vocs = {
        Knight   = { enabled = true,  hp = 60, prio = 1 },
        Paladin  = { enabled = true,  hp = 55, prio = 2 },
        Monk     = { enabled = true,  hp = 55, prio = 2 },
        Sorcerer = { enabled = false, hp = 50, prio = 3 },
        Druid    = { enabled = false, hp = 50, prio = 3 }
      }
    },
    sioFilters = {
      party = true,
      guild = true,
      allScreen = false,
      extraFriends = ''
    },
    masRes = {
      enabled = false,
      words = (defaultWords == 'exura tio sio') and 'exura mas nia' or 'exura gran mas res',
      minPlayers = 2,
      hp = 85,
      selfMp = 20,
      checkParty = true,
      checkGuild = true,
      includeSelf = true
    }
  }
end

local function createDefaultVocProfile(voc)
  local base
  if voc == 'Knight' then
    base = {
      healing = {
        enabled = true,
        spells = {
          { words = 'exura med ico', name = 'Fair Wound Cleansing', clientId = 4, pct = 70, minMp = 0, mode = 'hp', enabled = true },
          { words = 'exura ico', name = 'Wound Cleansing', clientId = 123, pct = 90, minMp = 0, mode = 'hp', enabled = true }
        },
        potions = {
          { id = 23375, pct = 45, ptype = 'hp', enabled = true },
          { id = 238,   pct = 60, ptype = 'mp', enabled = true }
        },
        curePara = { enabled = false, words = 'utani hur', name = 'Haste', clientId = 100 },
        manaShield = { enabled = false, words = '', name = '', clientId = 0 },
        partyHeal = { enabled = false, words = '', name = '', clientId = 0, pct = 75 },
        recovery = { enabled = false, words = 'utura gran', name = 'Intense Recovery', clientId = 135, pct = 95 }
      },
      shooter = {
        enabled = false,
        autoTarget = false,
        targetMode = 'Nearest',
        disablePz = true,
        ignoreList = '',
        currentPreset = 'Hunt',
        presets = {
          ['Hunt'] = {
            { type = 'S', words = 'utito tempo', name = 'Blood Rage', clientId = 133, countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 15, delay = 10000, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = {} },
            { type = 'S', words = 'exori gran', name = 'Fierce Berserk', clientId = 105, countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = { adjacent = true, momentum = true } },
            { type = 'S', words = 'exori min', name = 'Front Sweep', clientId = 59, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = { adjacent = true, faceTarget = true } },
            { type = 'S', words = 'exori mas', name = 'Groundshaker', clientId = 106, countVal = 3, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = { adjacent = false } },
            { type = 'S', words = 'exori', name = 'Berserk', clientId = 80, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 5, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = { adjacent = true } },
            { type = 'S', words = 'exori ico', name = 'Brutal Strike', clientId = 61, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 5, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = {} }
          }
        }
      }
    }
  elseif voc == 'Paladin' then
    base = {
      healing = {
        enabled = true,
        spells = {
          { words = 'exura gran san', name = 'Salvation', clientId = 59, pct = 75, minMp = 0, mode = 'hp', enabled = true },
          { words = 'exura san', name = 'Divine Healing', clientId = 125, pct = 90, minMp = 0, mode = 'hp', enabled = true }
        },
        potions = {
          { id = 23373, pct = 65, ptype = 'mp', enabled = true },
          { id = 23374, pct = 50, ptype = 'spirit', enabled = true }
        },
        curePara = { enabled = false, words = 'utani hur', name = 'Haste', clientId = 100 },
        manaShield = { enabled = false, words = '', name = '', clientId = 0 },
        partyHeal = { enabled = false, words = '', name = '', clientId = 0, pct = 75 },
        recovery = { enabled = false, words = 'utura gran', name = 'Intense Recovery', clientId = 135, pct = 95 }
      },
      shooter = {
        enabled = false,
        autoTarget = false,
        targetMode = 'Nearest',
        disablePz = true,
        ignoreList = '',
        currentPreset = 'Hunt',
        presets = {
          ['Hunt'] = {
            { type = 'S', words = 'exevo mas san', name = 'Divine Caldera', clientId = 124, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = { momentum = true } },
            { type = 'R', itemId = 3161, words = 'Avalanche Rune', name = 'Avalanche Rune', countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 0, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = {} },
            { type = 'S', words = 'exori san', name = 'Divine Missile', clientId = 122, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 5, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = {} }
          }
        }
      }
    }
  elseif voc == 'Monk' then
    base = {
      healing = {
        enabled = true,
        spells = {
          { words = 'exura gran tio', name = 'Spirit Mend', clientId = 161, pct = 80, minMp = 0, mode = 'hp', enabled = true },
          { words = 'exura gran', name = 'Intense Healing', clientId = 6, pct = 92, minMp = 0, mode = 'hp', enabled = true }
        },
        potions = {
          { id = 238, pct = 65, ptype = 'mp', enabled = true },
          { id = 23374, pct = 55, ptype = 'hp', enabled = true }
        },
        curePara = { enabled = false, words = 'utani gran hur', name = 'Strong Haste', clientId = 39 },
        manaShield = { enabled = false, words = 'utamo tio', name = 'Focus Serenity', clientId = 169 },
        partyHeal = { enabled = false, words = 'exura tio sio', name = 'Restore Balance', clientId = 185, pct = 80 },
        recovery = { enabled = false, words = 'utura tio', name = 'Virtue of Sustain', clientId = 164, pct = 95 }
      },
      shooter = {
        enabled = false,
        autoTarget = false,
        targetMode = 'Nearest',
        disablePz = true,
        ignoreList = '',
        currentPreset = 'Hunt',
        presets = {
          ['Hunt'] = {
            { type = 'S', words = 'exori mas nia', name = 'Sweeping Takedown', clientId = 182, countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = {} },
            { type = 'S', words = 'exori gran nia', name = 'Devastating Knockout', clientId = 181, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = {} },
            { type = 'S', words = 'exori pug', name = 'Double Jab', clientId = 180, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 5, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = {} }
          }
        }
      }
    }
  else
    local isDruid = (voc == 'Druid')
    base = {
      healing = {
        enabled = true,
        spells = {
          { words = 'exura max vita', name = 'Restoration', clientId = 107, pct = 60, minMp = 0, mode = 'hp', enabled = true },
          { words = 'exura vita', name = 'Ultimate Healing', clientId = 3, pct = 78, minMp = 0, mode = 'hp', enabled = true },
          { words = 'exura gran', name = 'Intense Healing', clientId = 6, pct = 92, minMp = 0, mode = 'hp', enabled = true }
        },
        potions = {
          { id = 23373, pct = 70, ptype = 'mp', enabled = true }
        },
        curePara = { enabled = false, words = 'utani gran hur', name = 'Strong Haste', clientId = 39 },
        manaShield = { enabled = false, words = 'utamo vita', name = 'Magic Shield', clientId = 123 },
        partyHeal = { enabled = false, words = isDruid and 'exura sio' or '', name = isDruid and 'Heal Friend' or '', clientId = isDruid and 7 or 0, pct = 75 },
        recovery = { enabled = false, words = '', name = '', clientId = 0, pct = 95 }
      },
      shooter = {
        enabled = false,
        autoTarget = false,
        targetMode = 'Nearest',
        disablePz = true,
        ignoreList = '',
        currentPreset = 'Hunt',
        presets = {
          ['Hunt'] = {
            { type = 'S', words = isDruid and 'exevo gran mas frigo' or 'exevo gran mas flam', name = isDruid and 'Eternal Winter' or 'Hell\'s Core', clientId = isDruid and 118 or 24, countVal = 4, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 20, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = {} },
            { type = 'S', words = isDruid and 'exevo frigo hur' or 'exevo gran flam hur', name = isDruid and 'Ice Wave' or 'Great Fire Wave', clientId = isDruid and 121 or 102, countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = { faceTarget = true } },
            { type = 'R', itemId = isDruid and 3161 or 3191, words = isDruid and 'Avalanche Rune' or 'Great Fireball Rune', name = isDruid and 'Avalanche Rune' or 'Great Fireball Rune', countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 0, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = {} }
          }
        }
      }
    }
  end

  local sioSection = createDefaultSioSection(voc == 'Druid', voc == 'Monk' and 'exura tio sio' or 'exura sio')
  for k, v in pairs(sioSection) do
    base.healing[k] = v
  end
  return base
end

local function normalizeShooterRule(r)
  if type(r) ~= 'table' then
    r = {}
  end
  r.type = r.type or 'S'
  r._lastCastAt = nil
  r.words = r.words or ''
  r.name = r.name or r.words
  r.clientId = tonumber(r.clientId) or 1
  r.itemId = tonumber(r.itemId) or 0
  r.hpMin = tonumber(r.hpMin) or 0
  r.hpMax = tonumber(r.hpMax) or 100
  r.mpPct = tonumber(r.mpPct) or 0
  r.delay = tonumber(r.delay) or 0
  r.priority = r.priority or 'All Monsters'
  r.targetName = r.targetName or ''
  if r.requiresTarget == nil then r.requiresTarget = true end
  if r.enabled == nil then r.enabled = true end
  r.cond = type(r.cond) == 'table' and r.cond or {}
  r.cond.stoppedMs = tonumber(r.cond.stoppedMs) or 1000
  r.cond.trappedCount = math.max(1, math.min(8, tonumber(r.cond.trappedCount) or 8))

  -- Convert legacy string counts ('2+', '3-', '1') to structured countVal + countOp
  if not r.countVal then
    local legacy = tostring(r.count or '1')
    local num = tonumber(legacy:match('(%d+)')) or 1
    r.countVal = num
    if r.cond.lowerThan or legacy:find('%-$') then
      r.countOp = '<'
    elseif legacy:find('%+$') then
      r.countOp = '>='
    else
      r.countOp = '='
    end
  else
    r.countVal = math.max(0, tonumber(r.countVal) or 1)
    if r.countOp ~= '>=' and r.countOp ~= '=' and r.countOp ~= '<' then
      r.countOp = '>='
    end
  end
  return r
end

local function normalizeVocProfile(vp, voc)
  local def = createDefaultVocProfile(voc)
  if type(vp) ~= 'table' then return def end

  vp.healing = type(vp.healing) == 'table' and vp.healing or def.healing
  local h = vp.healing
  if h.enabled == nil then h.enabled = def.healing.enabled end
  if type(h.spells) ~= 'table' then
    h.spells = deepCopy(def.healing.spells)
  else
    h.spells = coerceArray(h.spells)
  end
  local normSpells = {}
  for _, sp in ipairs(h.spells) do
    if type(sp) == 'table' then
      sp.words = sp.words or ''
      sp.name = sp.name or sp.words
      sp.clientId = tonumber(sp.clientId) or 1
      sp.pct = tonumber(sp.pct) or 80
      sp.minMp = tonumber(sp.minMp) or 0
      sp.mode = sp.mode or 'hp'
      if sp.enabled == nil then sp.enabled = true end
      table.insert(normSpells, sp)
    end
  end
  h.spells = normSpells

  if type(h.potions) ~= 'table' then
    h.potions = deepCopy(def.healing.potions)
  else
    h.potions = coerceArray(h.potions)
  end
  local normPotions = {}
  for _, pt in ipairs(h.potions) do
    if type(pt) == 'table' then
      pt.id = tonumber(pt.id) or 0
      pt.pct = tonumber(pt.pct) or 50
      local cat = findItemInCatalog(pt.id)
      if cat and (cat.ptype == 'hp' or cat.ptype == 'mp') then
        pt.ptype = cat.ptype
      elseif pt.ptype == 'spirit' or (pt.ptype ~= 'hp' and pt.ptype ~= 'mp') then
        pt.ptype = 'hp'
      end
      if pt.enabled == nil then pt.enabled = true end
      table.insert(normPotions, pt)
    end
  end
  h.potions = normPotions

  h.curePara = type(h.curePara) == 'table' and h.curePara or deepCopy(def.healing.curePara)
  h.curePara.words = h.curePara.words or ''
  h.curePara.enabled = (h.curePara.enabled == true)
  h.manaShield = type(h.manaShield) == 'table' and h.manaShield or deepCopy(def.healing.manaShield)
  h.manaShield.words = h.manaShield.words or ''
  h.manaShield.enabled = (h.manaShield.enabled == true)
  h.partyHeal = type(h.partyHeal) == 'table' and h.partyHeal or deepCopy(def.healing.partyHeal)
  h.partyHeal.words = h.partyHeal.words or ''
  h.partyHeal.pct = tonumber(h.partyHeal.pct) or 75
  h.partyHeal.enabled = (h.partyHeal.enabled == true)
  h.recovery = type(h.recovery) == 'table' and h.recovery or deepCopy(def.healing.recovery)
  h.recovery.words = h.recovery.words or ''
  h.recovery.pct = tonumber(h.recovery.pct) or 95
  h.recovery.enabled = (h.recovery.enabled == true)

  h.sio = type(h.sio) == 'table' and h.sio or deepCopy(def.healing.sio)
  h.sio.selfHp = tonumber(h.sio.selfHp) or 70
  h.sio.selfMp = tonumber(h.sio.selfMp) or 15
  h.sio.vocs = type(h.sio.vocs) == 'table' and h.sio.vocs or deepCopy(def.healing.sio.vocs)
  for vName, vDef in pairs(def.healing.sio.vocs) do
    if type(h.sio.vocs[vName]) ~= 'table' then h.sio.vocs[vName] = deepCopy(vDef) end
  end
  h.granSio = type(h.granSio) == 'table' and h.granSio or deepCopy(def.healing.granSio)
  h.granSio.vocs = type(h.granSio.vocs) == 'table' and h.granSio.vocs or deepCopy(def.healing.granSio.vocs)
  h.sioFilters = type(h.sioFilters) == 'table' and h.sioFilters or deepCopy(def.healing.sioFilters)
  h.masRes = type(h.masRes) == 'table' and h.masRes or deepCopy(def.healing.masRes)
  h.masRes.minPlayers = tonumber(h.masRes.minPlayers) or 2
  h.masRes.hp = tonumber(h.masRes.hp) or 85
  h.masRes.selfMp = tonumber(h.masRes.selfMp) or 20

  -- Shooter
  vp.shooter = type(vp.shooter) == 'table' and vp.shooter or deepCopy(def.shooter)
  local s = vp.shooter
  s.enabled = (s.enabled == true)
  s.autoTarget = false
  if s.disablePz == nil then s.disablePz = true end
  s.targetMode = s.targetMode or 'Nearest'
  s.ignoreList = s.ignoreList or ''
  if type(s.presets) ~= 'table' then s.presets = deepCopy(def.shooter.presets) end
  local firstPreset = nil
  for pName, rules in pairs(s.presets) do
    if not firstPreset then firstPreset = pName end
    if type(rules) ~= 'table' then
      s.presets[pName] = {}
    else
      local arr = coerceArray(rules)
      for i = 1, #arr do
        arr[i] = normalizeShooterRule(arr[i])
      end
      s.presets[pName] = arr
    end
  end
  if not firstPreset then
    s.presets = deepCopy(def.shooter.presets)
    s.currentPreset = 'Hunt'
  elseif not s.currentPreset or not s.presets[s.currentPreset] then
    s.currentPreset = firstPreset
  end

  -- Target (separate from Shooter)
  vp.target = type(vp.target) == 'table' and vp.target or {}
  local tg = vp.target
  tg.enabled = (tg.enabled == true)
  if tg.disablePz == nil then tg.disablePz = true end
  tg.mode = 'Default' or 'A'
  if not tg.mode:match('^[A-I]$') then tg.mode = 'A' end
  tg.maxRange = math.max(1, math.min(11, tonumber(tg.maxRange) or 7))
  tg.chase = (tg.chase == true)
  tg.chaseMode = tg.chase and 'Chase' or 'Stand'
  if tg.keepTarget == nil then tg.keepTarget = true end
  if tg.ignoreList == nil then tg.ignoreList = s.ignoreList or '' end
  tg.priorityList = nil
  tg.lowHpRules = nil
  local coercedTgtRules = coerceArray(tg.rules)
  if #coercedTgtRules == 0 then
    tg.rules = { { name = '', allMonsters = true, mode = tg.mode, hpMin = 0, hpMax = 100, interrupt = false, enabled = true } }
  else
    for _, tr in ipairs(coercedTgtRules) do
      if type(tr) == 'table' then
        tr.name = tr.name or ''
        if tr.allMonsters == nil then
          tr.allMonsters = (tr.name == '')
        end
        if tr.mode ~= 'Default' and not (tr.mode and tr.mode:match('^[A-I]$')) then
          tr.mode = 'A'
        end
        if tr.mode == 'A' and tg.mode ~= 'A' then tr.mode = 'Default' end
        tr.hpMin = tonumber(tr.hpMin) or 0
        tr.hpMax = tonumber(tr.hpMax) or 100
        tr.interrupt = (tr.interrupt == true)
        if tr.enabled == nil then tr.enabled = true end
      end
    end
    tg.rules = coercedTgtRules
  end
  return vp
end

local function createDefaultCharConfig()
  return {
    masterEnabled = false,
    language = 'en',
    windowPos = nil,
    keysClearedV2 = true,
    keys = {
      masterKey = '',
      healingKey = '',
      shooterKey = '',
      targetKey = '',
      targetShooterKey = '',
      presetKey = '',
      followKey = '',
      cavebotKey = ''
    },
    tools = {
      manaTrain = { words = 'exura ico', name = 'Wound Cleansing', clientId = 123, enabled = false, pct = 85, pzCast = true },
      haste = { words = 'utani hur', name = 'Haste', clientId = 100, enabled = false, pzCast = true },
      exercise = { enabled = false, weaponId = 0, dummyId = 0 },
      changeGold = false,
      autoEat = false,
      autoBless = false,
      antiAfk = false,
      follow = { enabled = false, name = '', mode = 'Default', dist = 1, turn = false },
      itemTimer = { enabled = false, itemId = 3725, sec = 610 }
    },
    cavebot = {
      enabled = false,
      ropeId = 3003,
      shovelId = 5710,
      startNearest = true,
      showWaypoints = true,
      autoRecDist = 3,
      huntName = '',
      settings = {
        stopMonsters = 3,
        walkMonsters = 1,
        dynamicLure = true,
        walkSpeedPct = 100,
        lureSpeeds = { [0] = 100, [1] = 100, [2] = 75, [3] = 55, [4] = 35, [5] = 20 }
      },
      waypoints = {},
      currentWpIndex = 1
    },
    customIds = {
      follow = deepCopy(DEFAULT_FOLLOW_IDS),
      dummys = {},
      weapons = {}
    },
    vocProfiles = {}
  }
end

local function normalizeCharConfig(cfg)
  local def = createDefaultCharConfig()
  if type(cfg) ~= 'table' then return def end

  if cfg.masterEnabled == nil then cfg.masterEnabled = def.masterEnabled end
  cfg.language = (cfg.language == 'pt') and 'pt' or 'en'
  if not cfg.keysClearedV2 then
    cfg.keys = deepCopy(def.keys)
    cfg.keysClearedV2 = true
  else
    cfg.keys = type(cfg.keys) == 'table' and cfg.keys or {}
    for k, v in pairs(def.keys) do
      if cfg.keys[k] == nil then cfg.keys[k] = v end
    end
  end

  -- Tools normalization (safely converts legacy array manaTrain[1..3] -> single object)
  cfg.tools = type(cfg.tools) == 'table' and cfg.tools or {}
  local t = cfg.tools
  if type(t.manaTrain) == 'table' and t.manaTrain[1] then
    local legacy = t.manaTrain[1]
    t.manaTrain = {
      words = legacy.words or 'exura ico',
      name = legacy.name or 'Wound Cleansing',
      clientId = tonumber(legacy.clientId) or 123,
      enabled = (legacy.enabled == true),
      pct = tonumber(legacy.pct) or 85,
      pzCast = (legacy.pzCast ~= false)
    }
  elseif type(t.manaTrain) ~= 'table' or t.manaTrain.words == nil then
    t.manaTrain = deepCopy(def.tools.manaTrain)
  else
    t.manaTrain.pct = tonumber(t.manaTrain.pct) or 85
    if t.manaTrain.pzCast == nil then t.manaTrain.pzCast = true end
    t.manaTrain.enabled = (t.manaTrain.enabled == true)
  end

  t.haste = type(t.haste) == 'table' and t.haste or deepCopy(def.tools.haste)
  t.haste.enabled = (t.haste.enabled == true)
  if t.haste.pzCast == nil then t.haste.pzCast = true end
  t.exercise = type(t.exercise) == 'table' and t.exercise or deepCopy(def.tools.exercise)
  t.exercise.enabled = (t.exercise.enabled == true)
  t.follow = type(t.follow) == 'table' and t.follow or deepCopy(def.tools.follow)
  t.follow.enabled = (t.follow.enabled == true)
  t.follow.name = t.follow.name or ''
  if t.follow.mode == 'Normal' or t.follow.mode == 'Keep Dist' then t.follow.mode = 'Default' end
  if t.follow.mode == 'Lure' then t.follow.mode = 'Front' end
  t.follow.mode = t.follow.mode or 'Default'
  t.follow.dist = math.max(1, math.min(4, tonumber(t.follow.dist) or 1))
  t.follow.turn = (t.follow.turn == true)
  t.itemTimer = type(t.itemTimer) == 'table' and t.itemTimer or deepCopy(def.tools.itemTimer)
  t.itemTimer.enabled = (t.itemTimer.enabled == true)
  t.itemTimer.itemId = tonumber(t.itemTimer.itemId) or 0
  t.itemTimer.sec = math.max(1, tonumber(t.itemTimer.sec) or 610)
  t.changeGold = (t.changeGold == true)
  t.autoEat = (t.autoEat == true)
  t.autoBless = (t.autoBless == true)
  t.antiAfk = (t.antiAfk == true)

  -- Cavebot normalization
  cfg.cavebot = type(cfg.cavebot) == 'table' and cfg.cavebot or deepCopy(def.cavebot)
  local cb = cfg.cavebot
  cb.enabled = (cb.enabled == true)
  cb.ropeId = tonumber(cb.ropeId) or 3003
  cb.shovelId = tonumber(cb.shovelId) or 5710
  if cb.startNearest == nil then cb.startNearest = true end
  if cb.showWaypoints == nil then cb.showWaypoints = true end
  if cb.showWaypointsFloor == nil then cb.showWaypointsFloor = true end
  if cb.wpMode ~= 'Add' and cb.wpMode ~= 'Insert' and cb.wpMode ~= 'Replace' then cb.wpMode = 'Add' end
  cb.autoRecDist = math.max(1, math.min(15, tonumber(cb.autoRecDist) or 3))
  cb.huntName = cb.huntName or ''
  cb.settings = type(cb.settings) == 'table' and cb.settings or {}
  if cb.settings.stopMonsters == nil then cb.settings.stopMonsters = 3 end
  if cb.settings.walkMonsters == nil then cb.settings.walkMonsters = 1 end
  if cb.settings.dynamicLure == nil then cb.settings.dynamicLure = true end
  if cb.settings.lureMode ~= 'box' and cb.settings.lureMode ~= 'global' then
    cb.settings.lureMode = 'box'
  end
  cb.settings.stopMonsters = tonumber(cb.settings.stopMonsters) or 3
  cb.settings.walkMonsters = tonumber(cb.settings.walkMonsters) or 1
  if cb.settings.walkSpeedPct == nil then
    cb.settings.walkSpeedPct = 100
  else
    cb.settings.walkSpeedPct = math.max(0, math.min(100, math.floor(tonumber(cb.settings.walkSpeedPct) or 100)))
  end
  if type(cb.settings.lureSpeeds) ~= 'table' then
    cb.settings.lureSpeeds = deepCopy(def.cavebot.settings.lureSpeeds)
  else
    local ls = {}
    for i = 0, 5 do
      local rawV = cb.settings.lureSpeeds[i]
      if rawV == nil then rawV = cb.settings.lureSpeeds[tostring(i)] end
      local v = tonumber(rawV)
      if not v then v = def.cavebot.settings.lureSpeeds[i] end
      ls[i] = math.max(0, math.min(100, math.floor(v)))
    end
    cb.settings.lureSpeeds = ls
  end
  cb.waypoints = coerceArray(cb.waypoints)
  cb.currentWpIndex = tonumber(cb.currentWpIndex) or 1

  cfg.customIds = type(cfg.customIds) == 'table' and cfg.customIds or deepCopy(def.customIds)
  cfg.customIds.follow = type(cfg.customIds.follow) == 'table' and cfg.customIds.follow or deepCopy(DEFAULT_FOLLOW_IDS)
  for cat, list in pairs(DEFAULT_FOLLOW_IDS) do
    if type(cfg.customIds.follow[cat]) ~= 'table' then
      cfg.customIds.follow[cat] = deepCopy(list)
    else
      cfg.customIds.follow[cat] = coerceIntArray(cfg.customIds.follow[cat])
    end
  end
  cfg.customIds.dummys = type(cfg.customIds.dummys) == 'table' and cfg.customIds.dummys or {}
  cfg.customIds.weapons = type(cfg.customIds.weapons) == 'table' and cfg.customIds.weapons or {}

  cfg.vocProfiles = type(cfg.vocProfiles) == 'table' and cfg.vocProfiles or {}
  return cfg
end

charConfig = normalizeCharConfig(createDefaultCharConfig())

local function getVocProfile(voc)
  voc = voc or currentVocName or detectPlayerVocation()
  if not charConfig.vocProfiles[voc] then
    charConfig.vocProfiles[voc] = normalizeVocProfile(createDefaultVocProfile(voc), voc)
  else
    charConfig.vocProfiles[voc] = normalizeVocProfile(charConfig.vocProfiles[voc], voc)
  end
  return charConfig.vocProfiles[voc]
end

-- ============================================================================
-- PERSISTENCE & LIVE SYNC
-- ============================================================================

local function getProfileStorageKey()
  if currentCharName and #currentCharName > 0 then
    return currentCharName
  end
  local p = g_game.getLocalPlayer()
  if p and p:getName() and #p:getName() > 0 then
    return p:getName()
  end
  return 'Default'
end

local function parseNum(editWidget, defaultVal, minV, maxV)
  if not editWidget then return defaultVal end
  local v = tonumber(editWidget:getText())
  if not v then return defaultVal end
  if minV and v < minV then v = minV end
  if maxV and v > maxV then v = maxV end
  return math.floor(v)
end

local DAVHELPER_NS = 'davhelper'
local DAVHELPER_LEGACY_NODE = 'DAVHelperCharConfigs'

local function loadHelperStoredProfile(key)
  if CharConfig then
    return CharConfig.load(DAVHELPER_NS, key, DAVHELPER_LEGACY_NODE, true)
  end
  local all = g_settings.getNode(DAVHELPER_LEGACY_NODE) or {}
  return all[key]
end

local function saveHelperStoredProfile(key, cfg)
  if CharConfig then
    return CharConfig.set(DAVHELPER_NS, key, cfg, true)
  end
  local all = g_settings.getNode(DAVHELPER_LEGACY_NODE) or {}
  all[key] = cfg
  g_settings.setNode(DAVHELPER_LEGACY_NODE, all)
  g_settings.save()
  return true
end

local function deleteHelperStoredProfile(key)
  if CharConfig then
    CharConfig.migrateLegacyNode(DAVHELPER_NS, DAVHELPER_LEGACY_NODE)
    CharConfig.delete(DAVHELPER_NS, key)
    return
  end
  local all = g_settings.getNode(DAVHELPER_LEGACY_NODE) or {}
  all[key] = nil
  g_settings.setNode(DAVHELPER_LEGACY_NODE, all)
  g_settings.save()
end

local function getAllHelperProfiles()
  if CharConfig then
    local out = {}
    local keys = CharConfig.listKeys(DAVHELPER_NS, DAVHELPER_LEGACY_NODE)
    for _, name in ipairs(keys) do
      local cfg = CharConfig.load(DAVHELPER_NS, name, DAVHELPER_LEGACY_NODE, true)
      if type(cfg) == 'table' then
        out[name] = cfg
      end
    end
    return out
  end
  return g_settings.getNode(DAVHELPER_LEGACY_NODE) or {}
end

function saveCurrentProfile()
  if isLoadingUI or not charConfig then return end
  local ok, err = pcall(function()
    saveHelperStoredProfile(getProfileStorageKey(), charConfig)
  end)
  if not ok then
    perror('[DAVCaster] Save error: ' .. tostring(err))
  end
end

function loadCharacterProfile(charName)
  local key = (charName and #charName > 0) and charName or 'Default'
  local stored = loadHelperStoredProfile(key)
  if type(stored) == 'table' then
    charConfig = normalizeCharConfig(deepCopy(stored))
  else
    charConfig = normalizeCharConfig(createDefaultCharConfig())
  end
  getVocProfile(currentVocName)
  loadProfileIntoUI()
  if rebuildShortcutBindings and g_game and g_game.isOnline() then
    rebuildShortcutBindings()
  end
end

-- ============================================================================
-- KEYBOARD, DELETE GUARD & HOTKEY SYSTEM
-- ============================================================================

local KEY_NAMES = {
  [KeyF1] = 'F1', [KeyF2] = 'F2', [KeyF3] = 'F3', [KeyF4] = 'F4',
  [KeyF5] = 'F5', [KeyF6] = 'F6', [KeyF7] = 'F7', [KeyF8] = 'F8',
  [KeyF9] = 'F9', [KeyF10] = 'F10', [KeyF11] = 'F11', [KeyF12] = 'F12',
  [KeyInsert] = 'Insert', [KeyDelete] = 'Delete', [KeyHome] = 'Home',
  [KeyEnd] = 'End', [KeyPageUp] = 'PageUp', [KeyPageDown] = 'PageDown',
  [KeyPause] = 'Pause', [KeySpace] = 'Space', [KeyTab] = 'Tab'
}

local boundHelperShortcuts = {}
local hookedKeyWidgets = {}

local function unbindShortcutKeys()
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

local function isChatCurrentlyEnabled()
  if modules and modules.game_console and modules.game_console.isChatEnabled then
    local ok, res = pcall(modules.game_console.isChatEnabled)
    if ok then return res == true end
  end
  return false
end

local function isNonTextShortcutKey(keyStr, keyCode, mods)
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

local function getDeepFocusedWidget()
  local cur = g_ui.getRootWidget()
  while cur and cur.getFocusedChild do
    local nxt = cur:getFocusedChild()
    if not nxt or nxt == cur then break end
    cur = nxt
  end
  return cur
end

local function shouldBlockShortcutForFocusedEdit(keyStr, keyCode, mods)
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

local function isTypingInTextEdit()
  return shouldBlockShortcutForFocusedEdit(nil, nil, 0)
end

local function normalizeShortcutKey(keyStr)
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

local STANDALONE_MODIFIER_DESCS = {
  Ctrl = true, Control = true, Alt = true, Option = true, Shift = true, Meta = true, Win = true, Cmd = true, Super = true
}

local function isStandaloneModifierKeyCode(keyCode)
  return keyCode == KeyEscape or keyCode == KeyShift or keyCode == KeyCtrl or keyCode == KeyControl
     or keyCode == KeyCtrlCmd or keyCode == KeyAlt or keyCode == KeyAltOpt or keyCode == KeyMeta
end

local function resolvePressedKeyString(keyCode, keyboardModifiers)
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

local function executeShortcutAction(desc, fn)
  local now = g_clock.millis()
  if desc == lastShortcutDesc and (now - lastShortcutEventTime) < 60 then
    return true
  end
  lastShortcutDesc = desc
  lastShortcutEventTime = now
  fn()
  return true
end

local function tryDispatchHelperShortcut(keyCode, keyboardModifiers)
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

local function installDeleteNoCloseGuard(win)
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

local function updateHelperButtonIcon(isOpen)
  if not helperButton then return end
  local iconPath = isOpen and '/mods/game_helper/images/custom/helper_open' or '/mods/game_helper/images/custom/helper_closed'
  if helperButton.setImageSource then
    pcall(function() helperButton:setImageSource(iconPath) end)
  elseif helperButton.setIcon then
    pcall(function() helperButton:setIcon(iconPath) end)
  end
end

local function setupTabIcons()
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

local function renderSpellSlot(slotWidget, spellEntry)
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

local function setVirtualUIItem(itemW, itemId)
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

local function renderItemSlot(slotWidget, itemId)
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

local function renderPotionTypeBar(barWidget, ptype)
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

local function bindSlotClicks(slotWidget, onLeftClick, onRightClear)
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

local function attachItemDropHandler(slotWidget, onItemIdDropped)
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

local COMBAT_SUPPORT_WORDS = {
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

local function isClickInsideAnyChild(parent, childNames, mousePos)
  if not mousePos then return false end
  for _, cid in ipairs(childNames) do
    local c = parent:getChildById(cid)
    if c and c:isVisible() and c:containsPoint(mousePos) then
      return true
    end
  end
  return false
end

local function bindDeleteButton(btn, fn)
  if not btn then return end
  if btn.setFocusable then btn:setFocusable(false) end
  if btn.setPhantom then btn:setPhantom(false) end
  btn.onClick = function(w)
    fn(w)
  end
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
      if idx > 1 then
        spells[idx], spells[idx - 1] = spells[idx - 1], spells[idx]
        refreshHealingSpellsListUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      if idx < #spells then
        spells[idx], spells[idx + 1] = spells[idx + 1], spells[idx]
        refreshHealingSpellsListUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      table.remove(spells, idx)
      refreshHealingSpellsListUI()
      saveCurrentProfile()
    end)
  end
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
      if idx > 1 then
        potions[idx], potions[idx - 1] = potions[idx - 1], potions[idx]
        refreshHealingPotionsListUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      if idx < #potions then
        potions[idx], potions[idx + 1] = potions[idx + 1], potions[idx]
        refreshHealingPotionsListUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      table.remove(potions, idx)
      refreshHealingPotionsListUI()
      saveCurrentProfile()
    end)
  end
end

function addHealingPotionRule()
  local vp = getVocProfile()
  table.insert(vp.healing.potions, { id = 0, pct = 50, ptype = 'mp', enabled = true })
  refreshHealingPotionsListUI()
  saveCurrentProfile()
end

-- ============================================================================
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

local function applyFollowTargetSelection(targetName, autoEnable)
  if not charConfig or not charConfig.tools then return end
  charConfig.tools.follow.name = targetName or ''
  if autoEnable ~= nil then
    charConfig.tools.follow.enabled = (autoEnable == true)
  end
  resetFollowRuntimeState()
  if panels.tools then
    local fBox = panels.tools:getChildById('rightToolsCol'):getChildById('followBox')
    if fBox then
      local prevLoad = isLoadingUI
      isLoadingUI = true
      local nameEdit = fBox:getChildById('followNameEdit')
      if nameEdit then nameEdit:setText(charConfig.tools.follow.name) end
      local enChk = fBox:getChildById('followEnableCheck')
      if enChk and autoEnable ~= nil then enChk:setChecked(charConfig.tools.follow.enabled == true) end
      isLoadingUI = prevLoad
    end
  end
  updateStatsUI()
  saveCurrentProfile()
end

function pickFollowTargetName()
  local target = g_game.getFollowingCreature() or g_game.getAttackingCreature()
  if target then
    applyFollowTargetSelection(target:getName(), true)
  end
end

function clearFollowTargetName()
  applyFollowTargetSelection('', false)
end

local function onHelperFollowCreatureChange(creature)
  if ignoreNativeFollowEvent or not charConfig or not charConfig.tools then return end
  if creature then
    applyFollowTargetSelection(creature:getName(), true)
    if charConfig.masterEnabled and g_game.follow then
      ignoreNativeFollowEvent = true
      pcall(g_game.follow, nil)
      ignoreNativeFollowEvent = false
    end
  end
end

-- ============================================================================
-- SHOOTER ENGINE UI, CREATURE COUNT COMPARATOR & PRESET RENAME MODAL
-- ============================================================================

local function formatRuleConditionSummary(rule)
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

local function loadSelectedShooterRuleIntoEditor()
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
end

local function updateSelectedShooterRowLabels()
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
      rule.enabled = checked
      saveCurrentProfile()
    end
    row:getChildById('upBtn').onClick = function()
      if idx > 1 then
        rules[idx], rules[idx - 1] = rules[idx - 1], rules[idx]
        selectedShooterRuleIdx = idx - 1
        refreshShooterRulesUI()
        saveCurrentProfile()
      end
    end
    row:getChildById('downBtn').onClick = function()
      if idx < #rules then
        rules[idx], rules[idx + 1] = rules[idx + 1], rules[idx]
        selectedShooterRuleIdx = idx + 1
        refreshShooterRulesUI()
        saveCurrentProfile()
      end
    end
    bindDeleteButton(row:getChildById('delBtn'), function()
      table.remove(rules, idx)
      selectedShooterRuleIdx = math.min(#rules, idx)
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
  local vp = getVocProfile()
  local rules = vp.shooter.presets[vp.shooter.currentPreset] or {}
    local r = (selectedShooterRuleIdx and rules[selectedShooterRuleIdx]) or shooterDraftRule
  if not r then return end
  local c = r.cond or {}

  conditionSettingsModal:getChildById('condTrapped'):setChecked(c.trapped == true)
  local trEdit = conditionSettingsModal:getChildById('condTrappedCount')
  if trEdit then trEdit:setText(tostring(c.trappedCount or 8)) end
  conditionSettingsModal:getChildById('condStopped'):setChecked(c.stopped == true)
  conditionSettingsModal:getChildById('condStoppedMs'):setText(tostring(c.stoppedMs or 1000))
  conditionSettingsModal:getChildById('condAdjacent'):setChecked(c.adjacent == true)
  conditionSettingsModal:getChildById('condFaceTarget'):setChecked(c.faceTarget == true)
  conditionSettingsModal:getChildById('condMomentum'):setChecked(c.momentum == true)

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
-- CAVEBOT: MINIMAP WAYPOINTS, GAME OVERLAY, START NEAREST, LURE
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Marcadores de waypoint NO CHAO (quadrado preto translucido + "N Tipo")
-- ---------------------------------------------------------------------------
local floorFillUnsupported = false
local lastFloorMarkAt = 0

local function clearFloorMarkers()
  for _, pos in ipairs(markedWorldTiles) do
    pcall(function()
      local tile = g_map.getTile(pos)
      if tile then
        if tile.setText then tile:setText('') end
        if tile.setFill and not floorFillUnsupported then tile:setFill('#00000000') end
      end
    end)
  end
  markedWorldTiles = {}
end

local function floorMarkerColor(typeLower)
  if typeLower:find('^stand') then return '#ffcc33' end
  if typeLower:find('^start lure') then return '#5ce65c' end
  if typeLower:find('^end lure') then return '#ff9944' end
  if typeLower:find('^rope') or typeLower:find('^shovel') or typeLower:find('^hole')
     or typeLower:find('^ladder') or typeLower:find('^use') then return '#66ccff' end
  return '#ffffff'
end

function refreshFloorMarkers()
  clearFloorMarkers()
  local cbc = charConfig and charConfig.cavebot
  if not cbc or cbc.showWaypointsFloor == false then return end
  local player = g_game.getLocalPlayer()
  local pPos = player and player:getPosition()
  if not pPos then return end
  local groups, order = {}, {}
  for idx, wpStr in ipairs(cbc.waypoints or {}) do
    local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and z == pPos.z and math.abs(x - pPos.x) <= 9 and math.abs(y - pPos.y) <= 7 then
      local key = x .. ',' .. y
      local wpType = wpStr:match('^([^:]+):') or 'WP'
      local g = groups[key]
      if not g then
        g = { pos = { x = x, y = y, z = z }, labels = {}, color = floorMarkerColor(wpType:lower()) }
        groups[key] = g
        order[#order + 1] = key
      end
      g.labels[#g.labels + 1] = idx .. ' ' .. wpType
    end
  end
  for _, key in ipairs(order) do
    local g = groups[key]
    local tile = g_map.getTile(g.pos)
    if tile then
      if tile.setFill and not floorFillUnsupported then
        local okF = pcall(function() tile:setFill('#00000099') end)
        if not okF then floorFillUnsupported = true end
      end
      if tile.setText then
        local text = table.concat(g.labels, ' / ')
        local okT = pcall(function() tile:setText(text, g.color) end)
        if not okT then pcall(function() tile:setText(text) end) end
      end
      markedWorldTiles[#markedWorldTiles + 1] = g.pos
    end
  end
end

function tickFloorMarkers(now)
  if (now - lastFloorMarkAt) < 600 then return end
  lastFloorMarkAt = now
  local cbc = charConfig and charConfig.cavebot
  if cbc and cbc.showWaypointsFloor ~= false and #(cbc.waypoints or {}) > 0 then
    refreshFloorMarkers()
  elseif #markedWorldTiles > 0 then
    clearFloorMarkers()
  end
end

local function clearTemporaryWaypointMarkers()
  for _, entry in ipairs(minimapTempFlags) do
    if entry.map and entry.pos then
      pcall(function() entry.map:removeFlag(entry.pos, entry.icon, entry.desc) end)
    end
  end
  minimapTempFlags = {}
  clearFloorMarkers()
end

function renderCavebotWaypointsOnMaps()
  clearTemporaryWaypointMarkers()
  refreshFloorMarkers()
  local show = charConfig and charConfig.cavebot and (charConfig.cavebot.showWaypoints ~= false)
  if not show then return end

  local player = g_game.getLocalPlayer()
  local pPos = player and player:getPosition()
  local curZ = pPos and pPos.z or nil

  local cbMap = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  local wps = charConfig.cavebot.waypoints or {}

  for idx, wpStr in ipairs(wps) do
    local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
    if x and y and z then
      local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
      if not curZ or pos.z == curZ then
        local wpLower = wpStr:lower()
        local iconIdx = wpLower:find('lure') and 11 or (wpLower:find('rope') or wpLower:find('hole') or wpLower:find('ladder')) and 12 or 1
        local desc = string.format('#%d %s', idx, wpStr)
        if cbMap then
          pcall(function()
            cbMap:addFlag(pos, iconIdx, desc, true)
            table.insert(minimapTempFlags, { map = cbMap, pos = pos, icon = iconIdx, desc = desc })
          end)
        end
      end
    end
  end
end

function onToggleShowWaypointsFloor(checked)
  if not charConfig or not charConfig.cavebot then return end
  charConfig.cavebot.showWaypointsFloor = checked and true or false
  refreshFloorMarkers()
  saveCurrentProfile()
end

local syncingWpMode = false
function syncCavebotWpModeUI()
  local box = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  if not box then return end
  local mode = (charConfig and charConfig.cavebot and charConfig.cavebot.wpMode) or 'Add'
  syncingWpMode = true
  for _, name in ipairs({ 'Add', 'Insert', 'Replace' }) do
    local w = box:getChildById('wpMode' .. name)
    if w then w:setChecked(name == mode) end
  end
  syncingWpMode = false
end

function setCavebotWpMode(mode, checked)
  if syncingWpMode then return end
  if not charConfig or not charConfig.cavebot then return end
  if not checked then
    -- funciona como radio: nao deixa desmarcar o modo atual
    if (charConfig.cavebot.wpMode or 'Add') == mode then syncCavebotWpModeUI() end
    return
  end
  charConfig.cavebot.wpMode = mode
  syncCavebotWpModeUI()
  saveCurrentProfile()
end

function onToggleShowWaypoints(checked)
  charConfig.cavebot.showWaypoints = checked
  renderCavebotWaypointsOnMaps()
  saveCurrentProfile()
end

function centerCavebotMinimap()
  local player = g_game.getLocalPlayer()
  local cbMap = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  if cbMap and player and player:getPosition() then
    cbMap:setCameraPosition(player:getPosition())
    cbMap:setCrossPosition(player:getPosition())
  end
end

function zoomCavebotMinimap(delta)
  local cbMap = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  if cbMap then
    if delta > 0 then cbMap:zoomIn() else cbMap:zoomOut() end
  end
end

function isCavebotAutoRecActive()
  return cavebotAutoRec
end

function setCavebotDirOffset(dir)
  cavebotDirOffset = dir or 'C'
  local dirs = { 'NW', 'N', 'NE', 'W', 'C', 'E', 'SW', 'S', 'SE' }
  local cbBox = panels.cavebot:getChildById('bodyPanel'):getChildById('cbMiddleRow'):getChildById('cbActionToolsBox'):getChildById('dirGridPanel')
  local hudGrid = cbControlMiniHud and cbControlMiniHud:getChildById('hudGridRow')
  for _, d in ipairs(dirs) do
    local isSel = (d == cavebotDirOffset)
    local b1 = cbBox and cbBox:getChildById('dir' .. d)
    if b1 then
      b1:setOn(isSel)
      b1:setColor(isSel and '#ffffff' or '#dfdfdf')
    end
    local b2 = hudGrid and hudGrid:getChildById('h' .. d)
    if b2 then b2:setColor(isSel and '#5ce65c' or '#dfdfdf') end
  end
end

local function getWaypointPos(wpStr)
  if not wpStr then return nil end
  local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
  if x and y and z then
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
  end
  return nil
end

function onToggleCavebotAutoRec(checked)
  cavebotAutoRec = checked and true or false
  if cavebotAutoRec then
    if charConfig and charConfig.cavebot and charConfig.cavebot.enabled then
      charConfig.cavebot.enabled = false
      local player = g_game.getLocalPlayer()
      if player and player.stopAutoWalk and player:isAutoWalking() then
        player:stopAutoWalk()
      end
      local topBox0 = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox')
      local cbEnChk = topBox0 and topBox0:getChildById('enableCavebotCheck')
      if cbEnChk and cbEnChk:isChecked() then
        cbEnChk:setChecked(false)
      end
      updateStatsUI()
      refreshCavebotUI()
      saveCurrentProfile()
    end
    local wps = charConfig and charConfig.cavebot and charConfig.cavebot.waypoints or {}
    local lastPos = (#wps > 0) and getWaypointPos(wps[#wps]) or nil
    local pPos = g_game.getLocalPlayer() and g_game.getLocalPlayer():getPosition() or nil
    if lastPos and pPos and lastPos.z == pPos.z then
      lastAutoRecPos = lastPos
    else
      lastAutoRecPos = nil
    end
  else
    lastAutoRecPos = nil
  end
  local topBox = panels.cavebot and panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox')
  local chk = topBox and topBox:getChildById('autoRecCheck')
  if chk and chk:isChecked() ~= cavebotAutoRec then
    chk:setChecked(cavebotAutoRec)
  end
  if cbControlMiniHud then
    local hBtn = cbControlMiniHud:getChildById('hudAutoRecBtn')
    if hBtn then
      hBtn:setText(ht('Auto Rec: ') .. (cavebotAutoRec and 'ON' or 'OFF'))
      hBtn:setColor(cavebotAutoRec and '#22ee22' or '#ff6666')
    end
  end
end

function toggleCbControlHud(forceState)
  if not cbControlMiniHud then return end
  local target = (forceState ~= nil) and forceState or (not cbControlMiniHud:isVisible())
  if target then
    cbControlMiniHud:show()
    cbControlMiniHud:raise()
  else
    cbControlMiniHud:hide()
  end
end

local DIR_OFFSETS = {
  NW = { -1, -1 }, N = { 0, -1 }, NE = { 1, -1 },
  W  = { -1,  0 }, C = { 0,  0 }, E  = { 1,  0 },
  SW = { -1,  1 }, S = { 0,  1 }, SE = { 1,  1 }
}

function refreshCavebotUI(scrollToBottom)
  syncCavebotWpModeUI()
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local cbRow = cBody:getChildById('cbListRow')
  local list = cbRow:getChildById('cavebotWpList')
  local wpScroll = cbRow:getChildById('wpScrollBar')
  local wasAtBottom = true
  if wpScroll and wpScroll.getValue and wpScroll.getMaximum then
    local maxV = wpScroll:getMaximum()
    if maxV > 0 and wpScroll:getValue() < (maxV - 25) then
      wasAtBottom = false
    end
  end
  local actionBox = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  local statusLbl = actionBox:getChildById('cavebotStatusLabel')
  list:destroyChildren()

  local wps = charConfig.cavebot.waypoints or {}
  local curIdx = charConfig.cavebot.currentWpIndex or 1
  if #wps == 0 then
    selectedCavebotWpIdx = nil
  elseif not selectedCavebotWpIdx or selectedCavebotWpIdx > #wps then
    selectedCavebotWpIdx = math.min(curIdx, #wps)
  end

  for idx, wpStr in ipairs(wps) do
    local row = g_ui.createWidget('CavebotWpRow', list)
    local wpType, wpBody = wpStr:match('^([^:]+):%s*(.+)$')
    if not wpType then
      wpType = 'Action'
      wpBody = wpStr
    end
    row:getChildById('wpIndexLabel'):setText(tostring(idx))
    row:getChildById('wpTypeLabel'):setText(wpType)
    row:getChildById('wpPosLabel'):setText(wpBody)
    if idx == curIdx and charConfig.cavebot.enabled then
      row:setBackgroundColor('#2e4a2e')
    end
    row.wpIdx = idx
    row.onClick = function(w)
      selectedCavebotWpIdx = w.wpIdx
      list:focusChild(w, MouseFocusReason)
      if charConfig.cavebot.enabled then
        local dest = getWaypointPos(wps[w.wpIdx])
        local player = g_game.getLocalPlayer()
        local pPos = player and player:getPosition() or nil
        if dest and pPos and dest.z == pPos.z and getDistanceBetween(pPos, dest) <= 25 then
          charConfig.cavebot.currentWpIndex = w.wpIdx
          if player.stopAutoWalk and player:isAutoWalking() then
            player:stopAutoWalk()
          end
          player:autoWalk(dest)
          refreshCavebotUI()
        end
      end
    end
    row.onDoubleClick = function(w)
      selectedCavebotWpIdx = w.wpIdx
      charConfig.cavebot.currentWpIndex = w.wpIdx
      refreshCavebotUI()
    end
    if idx == selectedCavebotWpIdx then
      list:focusChild(row, KeyboardFocusReason)
    end
  end

  local stText = charConfig.cavebot.enabled and htf('Running WP #%d/%d', curIdx, #wps) or htf('Idle (%d WPs)', #wps)
  if cbPauseState then stText = stText .. ht(' [Luring/Paused]') end
  statusLbl:setText(ht('Status: ') .. stText)
  if (scrollToBottom or wasAtBottom) and wpScroll and wpScroll.setValue and wpScroll.getMaximum then
    addEvent(function()
      if wpScroll and wpScroll.getMaximum then
        wpScroll:setValue(wpScroll:getMaximum())
      end
    end)
  end
  renderCavebotWaypointsOnMaps()
end

function cavebotAdvanceUI()
  local cb = charConfig.cavebot
  local player = g_game.getLocalPlayer()
  local pPos = player and player:getPosition()
  if pPos and helperLastRenderZ ~= pPos.z then
    helperLastRenderZ = pPos.z
    renderCavebotWaypointsOnMaps()  -- minimapa só redesenha quando muda de andar
  end
  if not (helperWindow and helperWindow:isVisible() and panels.cavebot and panels.cavebot:isVisible()) then return end
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local list = cBody:getChildById('cbListRow'):getChildById('cavebotWpList')
  local curIdx = cb.currentWpIndex or 1
  for _, row in ipairs(list:getChildren()) do
    row:setBackgroundColor((row.wpIdx == curIdx and cb.enabled) and '#2e4a2e' or '#363636')
  end
  local statusLbl = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox'):getChildById('cavebotStatusLabel')
  local wps = cb.waypoints or {}
  local stText = cb.enabled and htf('Running WP #%d/%d', curIdx, #wps) or htf('Idle (%d WPs)', #wps)
  if cbPauseState then stText = stText .. ht(' [Luring/Paused]') end
  statusLbl:setText(ht('Status: ') .. stText)
end

function selectNearestCavebotWaypoint()
  local player = g_game.getLocalPlayer()
  local wps = charConfig.cavebot.waypoints or {}
  if not player or #wps == 0 then return end
  local pPos = player:getPosition()
  local bestIdx = 1
  local bestDist = 99999
  for idx, wpStr in ipairs(wps) do
    local pos = getWaypointPos(wpStr)
    local lowWp = wpStr:lower()
    if pos and pos.z == pPos.z and not lowWp:find('^start lure') and not lowWp:find('^end lure') then
      local d = math.max(math.abs(pPos.x - pos.x), math.abs(pPos.y - pos.y))
      if d < bestDist then
        bestDist = d
        bestIdx = idx
      end
    end
  end
  charConfig.cavebot.currentWpIndex = bestIdx
  selectedCavebotWpIdx = bestIdx
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] Start nearest -> WP #' .. bestIdx)
  end
  refreshCavebotUI()
end

function addCavebotWaypoint(wpType)
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pPos = player:getPosition()
  local off = DIR_OFFSETS[cavebotDirOffset] or { 0, 0 }
  local x, y, z = pPos.x + off[1], pPos.y + off[2], pPos.z
  local entry = string.format('%s: %d, %d, %d', wpType, x, y, z)
  local wps = charConfig.cavebot.waypoints
  local mode = charConfig.cavebot.wpMode or 'Add'
  local sel = selectedCavebotWpIdx
  local scroll = true
  if mode == 'Insert' and sel and wps[sel] then
    -- entra ANTES do selecionado; a selecao continua no waypoint original (inserts seguidos ficam em ordem)
    table.insert(wps, sel, entry)
    local cur = charConfig.cavebot.currentWpIndex or 1
    if cur >= sel then charConfig.cavebot.currentWpIndex = cur + 1 end
    selectedCavebotWpIdx = sel + 1
    scroll = false
  elseif mode == 'Replace' and sel and wps[sel] then
    wps[sel] = entry
    scroll = false
  else
    table.insert(wps, entry)
    selectedCavebotWpIdx = #wps
  end
  setCavebotDirOffset('C')
  refreshCavebotUI(scroll)
  saveCurrentProfile()
end

function undoCavebotWaypoint()
  local wps = charConfig.cavebot.waypoints
  if #wps > 0 then
    table.remove(wps)
    selectedCavebotWpIdx = (#wps > 0) and #wps or nil
    if (charConfig.cavebot.currentWpIndex or 1) > #wps then
      charConfig.cavebot.currentWpIndex = math.max(1, #wps)
    end
    lastAutoRecPos = (#wps > 0) and getWaypointPos(wps[#wps]) or nil
    refreshCavebotUI()
    saveCurrentProfile()
  end
end

function moveCavebotWaypoint(delta)
  local wps = charConfig.cavebot.waypoints
  local idx = selectedCavebotWpIdx
  if not idx or not wps[idx] then return end
  local tgt = idx + delta
  if tgt >= 1 and tgt <= #wps then
    wps[idx], wps[tgt] = wps[tgt], wps[idx]
    selectedCavebotWpIdx = tgt
    refreshCavebotUI()
    saveCurrentProfile()
  end
end

function deleteSelectedCavebotWaypoint()
  local wps = charConfig.cavebot.waypoints
  local idx = selectedCavebotWpIdx
  if (not idx or not wps[idx]) and #wps > 0 then
    idx = #wps
  end
  if not idx or not wps[idx] then return end
  table.remove(wps, idx)
  if #wps == 0 then
    selectedCavebotWpIdx = nil
    charConfig.cavebot.currentWpIndex = 1
    lastAutoRecPos = nil
  else
    selectedCavebotWpIdx = math.min(idx, #wps)
    charConfig.cavebot.currentWpIndex = math.min(charConfig.cavebot.currentWpIndex or 1, #wps)
    lastAutoRecPos = getWaypointPos(wps[#wps])
  end
  refreshCavebotUI()
  saveCurrentProfile()
end

function clearCavebotWaypoints()
  charConfig.cavebot.waypoints = {}
  charConfig.cavebot.currentWpIndex = 1
  selectedCavebotWpIdx = nil
  refreshCavebotUI()
  saveCurrentProfile()
end

local function getCavebotDiskDir()
  local base = g_resources.getWorkDir and g_resources.getWorkDir() or ''
  if base ~= '' then
    return base .. 'mods/game_helper/cavebots'
  end
  return 'mods/game_helper/cavebots'
end

function saveCavebotWaypoints()
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local huntEdit = cBody:getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit')
  local rawName = huntEdit and huntEdit:getText() or ''
  local cleanName = rawName:gsub('[^%w%-%_%s]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', '_')
  if cleanName == '' then
    cleanName = 'hunt_' .. os.date('%H%M%S')
  end
  charConfig.cavebot.huntName = cleanName
  if huntEdit then huntEdit:setText(cleanName) end
  saveCurrentProfile()

  local savedFile = false
  local diskDir = getCavebotDiskDir()
  if io and io.open then
    local f = io.open(diskDir .. '/' .. cleanName .. '.txt', 'w')
    if f then
      for _, wp in ipairs(charConfig.cavebot.waypoints or {}) do
        f:write(wp .. '\n')
      end
      f:close()
      savedFile = true
    end
  end
  if modules.game_textmessage then
    if savedFile then
      modules.game_textmessage.displayStatusMessage(string.format('[DAVCaster] Saved hunt "%s.txt" (%d WPs).', cleanName, #charConfig.cavebot.waypoints))
    else
      modules.game_textmessage.displayStatusMessage(string.format('[DAVCaster] Saved %d WPs to profile "%s".', #charConfig.cavebot.waypoints, cleanName))
    end
  end
end

local selectedHuntFile = nil

function openHuntList()
  if not huntListModal then return end
  local list = huntListModal:getChildById('huntsList')
  list:destroyChildren()
  selectedHuntFile = nil
  local dir = '/mods/game_helper/cavebots'
  if g_resources.directoryExists(dir) then
    local files = g_resources.listDirectoryFiles(dir) or {}
    table.sort(files)
    for _, fname in ipairs(files) do
      if fname:match('%.txt$') or fname:match('%.json$') or fname:match('%.cb$') then
        local row = g_ui.createWidget('HuntListRow', list)
        row:getChildById('huntNameLabel'):setText(fname)
        row.fname = fname
        row.onClick = function(w)
          selectedHuntFile = w.fname
          list:focusChild(w, MouseFocusReason)
        end
        row.onDoubleClick = function(w)
          selectedHuntFile = w.fname
          confirmLoadHunt()
        end
      end
    end
  end
  huntListModal:show()
  huntListModal:raise()
  huntListModal:focus()
end

function confirmLoadHunt()
  if not selectedHuntFile then return end
  local dir = '/mods/game_helper/cavebots'
  local raw = g_resources.readFileContents(dir .. '/' .. selectedHuntFile)
  if raw and #raw > 0 then
    local loaded = {}
    for line in raw:gmatch('[^\r\n]+') do
      line = line:gsub('^%s+', ''):gsub('%s+$', '')
      if line ~= '' and line:match('%d+,%s*%d+,%s*%d+') then
        table.insert(loaded, line)
      end
    end
    if #loaded > 0 then
      charConfig.cavebot.waypoints = loaded
      charConfig.cavebot.currentWpIndex = 1
      charConfig.cavebot.huntName = selectedHuntFile:gsub('%.[^%.]+$', '')
      local huntEdit = panels.cavebot:getChildById('bodyPanel'):getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit')
      if huntEdit then huntEdit:setText(charConfig.cavebot.huntName) end
      refreshCavebotUI()
      saveCurrentProfile()
      if modules.game_textmessage then
        modules.game_textmessage.displayStatusMessage('[DAVCaster] Loaded ' .. #loaded .. ' WPs from ' .. selectedHuntFile)
      end
      huntListModal:hide()
      return
    end
  end
  if modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('[DAVCaster] Could not find coordinates in ' .. selectedHuntFile)
  end
end

function loadCavebotWaypoints()
  openHuntList()
end

function openCavebotSettingsModal()
  local s = charConfig.cavebot.settings
  local ls = s.lureSpeeds or {}
  local isGlobal = (s.lureMode == 'global')
  local boxChk = cavebotSettingsModal:getChildById('cbLureBoxModeCheck')
  local glbChk = cavebotSettingsModal:getChildById('cbLureGlobalModeCheck')
  if boxChk and glbChk then
    boxChk.onCheckChange = nil
    glbChk.onCheckChange = nil
    boxChk:setChecked(not isGlobal)
    glbChk:setChecked(isGlobal)
    boxChk.onCheckChange = function(w, ch)
      if ch and glbChk:isChecked() then glbChk:setChecked(false)
      elseif not ch and not glbChk:isChecked() then boxChk:setChecked(true) end
      s.lureMode = glbChk:isChecked() and 'global' or 'box'
      saveCurrentProfile()
    end
    glbChk.onCheckChange = function(w, ch)
      if ch and boxChk:isChecked() then boxChk:setChecked(false)
      elseif not ch and not boxChk:isChecked() then glbChk:setChecked(true) end
      s.lureMode = glbChk:isChecked() and 'global' or 'box'
      saveCurrentProfile()
    end
  end
  local stopEd = cavebotSettingsModal:getChildById('cbStopMonstersEdit')
  local walkEd = cavebotSettingsModal:getChildById('cbWalkMonstersEdit')
  local dynChk = cavebotSettingsModal:getChildById('cbDynamicLureCheck')
  stopEd.onTextChange = nil
  walkEd.onTextChange = nil
  dynChk.onCheckChange = nil
  stopEd:setText(tostring(s.stopMonsters or 3))
  walkEd:setText(tostring(s.walkMonsters or 1))
  dynChk:setChecked(s.dynamicLure ~= false)
  dynChk.onCheckChange = function(w, ch)
    s.dynamicLure = ch and true or false
    saveCurrentProfile()
  end
  local grid = cavebotSettingsModal:getChildById('cbLureGrid')
  if grid then
    for i = 0, 5 do
      local e = grid:getChildById('cbLure' .. i)
      if e then
        e.onTextChange = nil
        e:setText(tostring(ls[i] ~= nil and ls[i] or 100))
        e.onTextChange = function(w, txt)
          local n = tonumber(txt)
          if n then
            s.lureSpeeds = s.lureSpeeds or {}
            s.lureSpeeds[i] = math.max(0, math.min(100, math.floor(n)))
            saveCurrentProfile()
          end
        end
      end
    end
  end
  stopEd.onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then s.stopMonsters = math.max(1, math.min(20, math.floor(n))) saveCurrentProfile() end
  end
  walkEd.onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then s.walkMonsters = math.max(0, math.min(20, math.floor(n))) saveCurrentProfile() end
  end
  cavebotSettingsModal:show()
  cavebotSettingsModal:raise()
  cavebotSettingsModal:focus()
end

function saveCavebotSettingsModal()
  local s = charConfig.cavebot.settings
  s.stopMonsters = parseNum(cavebotSettingsModal:getChildById('cbStopMonstersEdit'), 3, 1, 20)
  s.walkMonsters = parseNum(cavebotSettingsModal:getChildById('cbWalkMonstersEdit'), 1, 0, 20)
  local glbChk = cavebotSettingsModal:getChildById('cbLureGlobalModeCheck')
  s.lureMode = (glbChk and glbChk:isChecked()) and 'global' or 'box'
  s.dynamicLure = cavebotSettingsModal:getChildById('cbDynamicLureCheck'):isChecked()
  local lureGrid = cavebotSettingsModal:getChildById('cbLureGrid')
  if lureGrid then
    s.lureSpeeds = s.lureSpeeds or {}
    for i = 0, 5 do
      local e = lureGrid:getChildById('cbLure' .. i)
      if e then s.lureSpeeds[i] = parseNum(e, s.lureSpeeds[i] or 100, 0, 100) end
    end
  end
  if not s.dynamicLure and panels.cavebot then
    local ed = panels.cavebot:getChildById('bodyPanel'):getChildById('cbTopControlsBox'):getChildById('cbWalkSpeedEdit')
    if ed then
      helperSpeedUiLock = true
      ed:setText(tostring(s.walkSpeedPct or 100), true)
      helperSpeedUiLock = false
    end
  end
  cavebotSettingsModal:hide()
  saveCurrentProfile()
end

-- ============================================================================
-- TARGET TAB & CUSTOM IDS MANAGER
-- ============================================================================

local function loadSelectedTargetRuleIntoEditor()
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
  if mc and mc.setCurrentOptionByData then mc:setCurrentOptionByData(r.mode or 'Default', true) end
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
    row:getChildById('ruleModeLabel'):setText(ht('Mode ') .. (r.mode or 'Default'))
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
end

local function updateSelectedTargetRowLabels()
  if not panels.target or not selectedTargetRuleIdx then return end
  local vp = getVocProfile()
  local r = (vp.target.rules or {})[selectedTargetRuleIdx]
  if not r then return end
  local list = panels.target:getChildById('targetRulesList')
  if not list then return end
  for _, row in ipairs(list:getChildren()) do
    if row.ruleIdx == selectedTargetRuleIdx then
      row:getChildById('ruleNameLabel'):setText((r.allMonsters == false or (r.name and r.name ~= '')) and ((r.name and r.name ~= '') and r.name or ht('Target Name...')) or ht('All Monsters'))
      row:getChildById('ruleModeLabel'):setText(ht('Mode ') .. (r.mode or 'Default'))
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
      table.insert(rules, { name = '', allMonsters = true, mode = 'Default' or 'A', hpMin = 0, hpMax = 100, interrupt = false, enabled = true })
    end
    selectedTargetRuleIdx = math.min(#rules, selectedTargetRuleIdx)
    refreshTargetRulesUI()
    saveCurrentProfile()
  end
end

function newTargetRule()
  local vp = getVocProfile()
  table.insert(vp.target.rules, { name = '', allMonsters = true, mode = 'Default', hpMin = 0, hpMax = 100, interrupt = false, enabled = true })
  selectedTargetRuleIdx = #vp.target.rules
  refreshTargetRulesUI()
  saveCurrentProfile()
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
    if activeFollowIdCat == 'stairs' then
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

local function getComboOptionData(cb, fallback)
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
      tgtModeCb:addOption(ht('Default'), 'Default')
      for _, opt in ipairs({ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I' }) do
        tgtModeCb:addOption(opt, opt)
      end
      tgtModeCb:setCurrentOptionByData((tr and tr.mode) or 'A', true)
    end
  end

  refreshingShooterUI = prevShooter
  refreshingTargetUI = prevTarget
end

local function setSettingsStatus(msg, color)
  if not panels.settings then return end
  local box = panels.settings:getChildById('savedProfilesBox')
  local lbl = box and box:getChildById('settingsStatusLabel')
  if lbl then
    lbl:setText(msg)
    if color then lbl:setColor(color) end
  end
end

local function syncLanguageCombos()
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
    huntListModal
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

function exportAllConfigs()
  if g_game and g_game.isOnline() and charConfig then
    saveCurrentProfile()
  end
  local all = getAllHelperProfiles()
  local outProfiles = {}
  local count = 0
  for key, cfg in pairs(all) do
    if type(key) == 'string' and type(cfg) == 'table' then
      local copy = deepCopy(cfg)
      if CharConfig and CharConfig.sanitize then
        copy = CharConfig.sanitize(copy)
      end
      outProfiles[key] = copy
      count = count + 1
    end
  end
  return {
    format = 'davot_helper_bundle',
    version = 1,
    exportedAt = os.date('%Y-%m-%d %H:%M:%S'),
    activeProfileKey = (g_game and g_game.isOnline() and getProfileStorageKey() or nil),
    activeVoc = currentVocName,
    count = count,
    profiles = outProfiles
  }
end

function importAllConfigs(bundle, applyToCurrentIfMissing)
  if type(bundle) ~= 'table' or bundle.format ~= 'davot_helper_bundle' or type(bundle.profiles) ~= 'table' then
    return false, 'This file is not a valid DAVCaster Helper backup.'
  end

  local importedCount = 0
  local firstKey, firstNonDefaultKey = nil, nil
  for key, cfg in pairs(bundle.profiles) do
    if type(key) == 'string' and #key > 0 and type(cfg) == 'table' then
      local copy = deepCopy(cfg)
      if CharConfig and CharConfig.restore then
        copy = CharConfig.restore(copy)
      end
      local norm = normalizeCharConfig(copy)
      saveHelperStoredProfile(key, norm)
      importedCount = importedCount + 1
      if not firstKey then firstKey = key end
      if key ~= 'Default' and not firstNonDefaultKey then firstNonDefaultKey = key end
    end
  end

  if importedCount == 0 then
    return false, 'No profiles found in this Helper backup file.'
  end

  if CharConfig then
    CharConfig.flushNamespace(DAVHELPER_NS)
  end

  local appliedActive = false
  if g_game and g_game.isOnline() and charConfig then
    local activeKey = getProfileStorageKey()
    local matched = bundle.profiles[activeKey]
    if type(matched) ~= 'table' and applyToCurrentIfMissing then
      if type(bundle.activeProfileKey) == 'string' and type(bundle.profiles[bundle.activeProfileKey]) == 'table' then
        matched = bundle.profiles[bundle.activeProfileKey]
      elseif firstNonDefaultKey then
        matched = bundle.profiles[firstNonDefaultKey]
      elseif firstKey then
        matched = bundle.profiles[firstKey]
      end
    end
    if type(matched) == 'table' then
      local prevPos = charConfig.windowPos and deepCopy(charConfig.windowPos) or nil
      local mCopy = deepCopy(matched)
      if CharConfig and CharConfig.restore then
        mCopy = CharConfig.restore(mCopy)
      end
      charConfig = normalizeCharConfig(mCopy)
      if prevPos then
        charConfig.windowPos = prevPos
      end
      getVocProfile(currentVocName)
      saveCurrentProfile()
      loadProfileIntoUI()
      rebuildShortcutBindings()
      appliedActive = true
    end
  end

  if panels and panels.settings then
    refreshSettingsTabUI()
  end

  return true, importedCount, appliedActive
end

function loadProfileIntoUI()
  isLoadingUI = true
  refreshingShooterUI = true
  refreshingTargetUI = true
  setHelperLanguageState((charConfig and charConfig.language) or 'en')
  applyHelperLanguage(true)
  local vp = getVocProfile()
  updateMasterBarUI()
  updateStatsUI()
  updateKeyButtonsUI()
  applyVocationVisibility()

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
  local tl = charConfig.tools
  local tLeft = panels.tools:getChildById('leftToolsCol')
  local mtBox = tLeft:getChildById('manaTrainBox')
  renderSpellSlot(mtBox:getChildById('manaTrainSlot'), tl.manaTrain)
  mtBox:getChildById('manaTrainPctEdit'):setText(tostring(tl.manaTrain.pct or 85))
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
  fBox:getChildById('followEnableCheck'):setChecked(tl.follow.enabled == true)

  local uBox = tRight:getChildById('utilsBox')
  uBox:getChildById('changeGoldCheck'):setChecked(tl.changeGold == true)
  uBox:getChildById('autoEatCheck'):setChecked(tl.autoEat == true)
  uBox:getChildById('autoBlessCheck'):setChecked(tl.autoBless == true)
  uBox:getChildById('antiAfkCheck'):setChecked(tl.antiAfk == true)

  -- 3. Shooter UI
  local sGlob = panels.shooter:getChildById('bodyPanel'):getChildById('shooterGlobalBox')
  sGlob:getChildById('enableShooterCheck'):setChecked(vp.shooter.enabled == true, true)
  sGlob:getChildById('disablePzCheck'):setChecked(vp.shooter.disablePz ~= false)
  refreshShooterRulesUI()

  -- 4. Target UI
  if panels.target then
    local tgTop = panels.target:getChildById('targetTopBox')
    tgTop:getChildById('targetEnableCheck'):setChecked(vp.target.enabled == true, true)
    tgTop:getChildById('targetDisablePzCheck'):setChecked(vp.target.disablePz ~= false)
    local mc = tgTop:getChildById('targetModeCombo')
    if mc and mc.setCurrentOption then mc:setCurrentOption(vp.target.mode or 'A', true) end
    tgTop:getChildById('targetRangeEdit'):setText(tostring(vp.target.maxRange or 7))
    tgTop:getChildById('targetChaseCombo'):setCurrentOptionByData(vp.target.chase and 'Chase' or 'Stand', true)
    tgTop:getChildById('targetKeepCheck'):setChecked(vp.target.keepTarget ~= false)
    local tgLists = panels.target:getChildById('targetListsBox')
    tgLists:getChildById('targetIgnoreEdit'):setText(vp.target.ignoreList or '')
    refreshTargetRulesUI()
  end

  -- 5. Cavebot UI
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local cbTop = cBody:getChildById('cbTopControlsBox')
  cbTop:getChildById('enableCavebotCheck'):setChecked(charConfig.cavebot.enabled == true)
  cbTop:getChildById('autoRecDistEdit'):setText(tostring(charConfig.cavebot.autoRecDist or 3))
  cbTop:getChildById('cbWalkSpeedEdit'):setText(tostring((charConfig.cavebot.settings and charConfig.cavebot.settings.walkSpeedPct) ~= nil and charConfig.cavebot.settings.walkSpeedPct or 100))
  cbTop:getChildById('startNearestCheck'):setChecked(charConfig.cavebot.startNearest ~= false)
  cbTop:getChildById('showWaypointsCheck'):setChecked(charConfig.cavebot.showWaypoints ~= false)
  local floorChk = cbTop:getChildById('showFloorWpCheck')
  if floorChk then floorChk:setChecked(charConfig.cavebot.showWaypointsFloor ~= false) end
  local huntEdit = cBody:getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit')
  if huntEdit then huntEdit:setText(charConfig.cavebot.huntName or '') end
  local cbAct = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  renderItemSlot(cbAct:getChildById('ropeSlot'), charConfig.cavebot.ropeId)
  renderItemSlot(cbAct:getChildById('shovelSlot'), charConfig.cavebot.shovelId)
  setCavebotDirOffset('C')
  refreshCavebotUI()
  refreshSettingsTabUI()
  syncLanguageCombos()
  refreshingShooterUI = false
  refreshingTargetUI = false
  isLoadingUI = false
end

-- ============================================================================
-- WIDGET CALLBACKS WIRING
-- ============================================================================

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
  for _, win in ipairs({ helperWindow, statsWindow, spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, keyCaptureModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal }) do
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
  conditionSettingsModal:getChildById('updateCondBtn').onClick = function()
    local vp = getVocProfile()
    local target = (selectedShooterRuleIdx and rules[selectedShooterRuleIdx]) or shooterDraftRule
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
  end

  -- Key Capture Modal
  keyCaptureModal:getChildById('clearKeyBtn').onClick = function()
    if activeKeyCaptureSlot then
      charConfig.keys[activeKeyCaptureSlot] = ''
      updateKeyButtonsUI()
      saveCurrentProfile()
      rebuildShortcutBindings()
    end
    closeKeyCapture()
  end
  keyCaptureModal:getChildById('cancelKeyBtn').onClick = function() closeKeyCapture() end
  keyCaptureModal.onEscape = function() closeKeyCapture() return true end
  keyCaptureModal.onKeyDown = function(widget, keyCode, keyboardModifiers)
    if keyCode == KeyEscape then closeKeyCapture() return true end
    if not activeKeyCaptureSlot then return false end
    local keyStr = resolvePressedKeyString(keyCode, keyboardModifiers)
    if keyStr and keyStr ~= '' then
      charConfig.keys[activeKeyCaptureSlot] = keyStr
      closeKeyCapture()
      updateKeyButtonsUI()
      saveCurrentProfile()
      rebuildShortcutBindings()
      return true
    end
    return true
  end

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
  local tTop = panels.target:getChildById('targetTopBox')
  local tModeCb = tTop:getChildById('targetModeCombo')
  for _, opt in ipairs({ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I' }) do
    tModeCb:addOption(opt)
  end
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
  tModeCb.onOptionChange = function(w, text)
    if refreshingTargetUI then return end
    local tg = getVocProfile().target
    local old = tg.mode
    for _, r in ipairs(tg.rules or {}) do
      if r.mode == old then r.mode = 'Default' end
    end
    tg.mode = text
    refreshTargetRulesUI()
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

  local tEd = panels.target:getChildById('targetEditorBox')
  local tgtFilterCb = tEd:getChildById('tgtFilterCombo')
  for _, opt in ipairs({ 'All Monsters', 'Target Name' }) do tgtFilterCb:addOption(ht(opt), opt) end
  local tgtModeCb = tEd:getChildById('tgtModeCombo')
  tgtModeCb:addOption(ht('Default'), 'Default')
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
  local cBody = panels.cavebot:getChildById('bodyPanel')
  local cbTop = cBody:getChildById('cbTopControlsBox')
  cbTop:getChildById('enableCavebotCheck').onCheckChange = function(w, ch)
    charConfig.cavebot.enabled = ch
    if ch then
      if cavebotAutoRec then
        cavebotAutoRec = false
        cbTop:getChildById('autoRecCheck'):setChecked(false)
      end
      if charConfig.cavebot.startNearest then
        selectNearestCavebotWaypoint()
      end
    end
    updateStatsUI()
    refreshCavebotUI()
    saveCurrentProfile()
  end
  local distEdit = cbTop:getChildById('autoRecDistEdit')
  distEdit.onTextChange = function(w, txt)
    local n = tonumber(txt)
    if n then charConfig.cavebot.autoRecDist = math.max(1, math.min(15, math.floor(n))) saveCurrentProfile() end
  end
  local function releaseDistFocus()
    local rootPanel = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
    if rootPanel then rootPanel:focus() end
  end
  local moveKeys = {}
  for _, kn in ipairs({ 'KeyW', 'KeyA', 'KeyS', 'KeyD', 'KeyUp', 'KeyDown', 'KeyLeft', 'KeyRight', 'KeyQ', 'KeyE', 'KeyZ', 'KeyC' }) do
    local kc = rawget(_G, kn)
    if kc then moveKeys[kc] = true end
  end
  distEdit.onKeyDown = function(w, keyCode, mods)
    if moveKeys[keyCode] then releaseDistFocus() end
    return false
  end
  panels.cavebot.onMousePress = function(w, mousePos, button)
    if distEdit:isFocused() and not distEdit:containsPoint(mousePos) then releaseDistFocus() end
    return false
  end
  distEdit.onFocusChange = nil
  cbTop:getChildById('cbWalkSpeedEdit').onTextChange = function(w, txt)
    if helperSpeedUiLock then return end
    local n = tonumber(txt)
    if n and charConfig.cavebot and charConfig.cavebot.settings then
      charConfig.cavebot.settings.walkSpeedPct = math.max(0, math.min(100, math.floor(n)))
      saveCurrentProfile()
    end
  end
  cbTop:getChildById('startNearestCheck').onCheckChange = function(w, ch)
    charConfig.cavebot.startNearest = ch
    saveCurrentProfile()
  end
  cBody:getChildById('cbListRow'):getChildById('wpManageRow'):getChildById('huntNameEdit').onTextChange = function(w, txt)
    charConfig.cavebot.huntName = txt
  end

  local cbAct = cBody:getChildById('cbMiddleRow'):getChildById('cbActionToolsBox')
  local rSlot = cbAct:getChildById('ropeSlot')
  bindSlotClicks(rSlot, function()
    openItemSelector('Select Rope Item', 'tool', charConfig.cavebot.ropeId, function(it)
      charConfig.cavebot.ropeId = it.id
      renderItemSlot(rSlot, it.id)
    end)
  end, function()
    charConfig.cavebot.ropeId = 3003
    renderItemSlot(rSlot, 3003)
  end)
  attachItemDropHandler(rSlot, function(id) charConfig.cavebot.ropeId = id renderItemSlot(rSlot, id) end)

  local shSlot = cbAct:getChildById('shovelSlot')
  bindSlotClicks(shSlot, function()
    openItemSelector('Select Shovel Item', 'tool', charConfig.cavebot.shovelId, function(it)
      charConfig.cavebot.shovelId = it.id
      renderItemSlot(shSlot, it.id)
    end)
  end, function()
    charConfig.cavebot.shovelId = 5710
    renderItemSlot(shSlot, 5710)
  end)
  attachItemDropHandler(shSlot, function(id) charConfig.cavebot.shovelId = id renderItemSlot(shSlot, id) end)

  -- Hide built-in mini buttons inside cavebotMinimap cleanly
  local cbMap = cBody:getChildById('cbMiddleRow'):getChildById('cavebotMapBorder'):getChildById('cavebotMinimap')
  if cbMap then
    for _, cid in ipairs({'floorUpButton', 'floorDownButton', 'zoomInButton', 'zoomOutButton', 'resetButton'}) do
      local c = cbMap:getChildById(cid)
      if c then c:hide() end
    end
  end

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
end

-- ============================================================================
-- RUNTIME AUTOMATION TICK ENGINE
-- ============================================================================

local function getDistanceBetween(p1, p2)
  if not p1 or not p2 then return 999 end
  if p1.z ~= p2.z then return 999 end
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function getDirectionFromPos(fromPos, toPos)
  if not fromPos or not toPos then return nil end
  local dx, dy = toPos.x - fromPos.x, toPos.y - fromPos.y
  if dx == 0 and dy == 0 then return nil end
  if dx > 0 and dy < 0 then return NorthEast
  elseif dx > 0 and dy > 0 then return SouthEast
  elseif dx < 0 and dy > 0 then return SouthWest
  elseif dx < 0 and dy < 0 then return NorthWest
  elseif dy < 0 then return North
  elseif dx > 0 then return East
  elseif dy > 0 then return South
  else return West end
end

local function resolveFloorChangeStandPos(oldPos, newPos)
  if not oldPos or not newPos then return oldPos end
  if oldPos.x == newPos.x and oldPos.y == newPos.y then
    return oldPos
  end
  local tOld = g_map.getTile(oldPos)
  if tOld and tOld.hasFloorChange and tOld:hasFloorChange() then
    return oldPos
  end
  local sameXY = { x = newPos.x, y = newPos.y, z = oldPos.z }
  local tSame = g_map.getTile(sameXY)
  if tSame and tSame.hasFloorChange and tSame:hasFloorChange() then
    return sameXY
  end
  local bestPos, bestDist = nil, 999
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local cand = { x = oldPos.x + dx, y = oldPos.y + dy, z = oldPos.z }
        local t = g_map.getTile(cand)
        if t and t.hasFloorChange and t:hasFloorChange() then
          local d = math.abs(cand.x - newPos.x) + math.abs(cand.y - newPos.y)
          if d < bestDist then
            bestDist, bestPos = d, cand
          end
        end
      end
    end
  end
  return bestPos or oldPos
end

local function parseCommaSet(str)
  if not str or str == '' then return {} end
  helperCommaSetCache = helperCommaSetCache or {}
  local cached = helperCommaSetCache[str]
  if cached then return cached end
  local set = {}
  for token in str:gmatch('[^,]+') do
    local clean = token:lower():gsub('^%s+', ''):gsub('%s+$', '')
    if clean ~= '' then set[clean] = true end
  end
  helperCommaSetCache[str] = set
  return set
end

local function isValidMonsterCreature(cr)
  if not cr or (cr.isDead and cr:isDead()) then return false end
  if not (cr.isMonster and cr:isMonster()) then return false end
  if cr.isNpc and cr:isNpc() then return false end
  if cr.isPlayer and cr:isPlayer() then return false end
  return true
end

local function getNearbyMonsters(playerPos, range, ignoreListStr)
  local ignoreSet = parseCommaSet(ignoreListStr)
  local monsters, players = {}, {}
  local specs = g_map.getSpectators(playerPos, false) or {}
  for _, cr in ipairs(specs) do
    local cPos = cr:getPosition()
    if cPos and cPos.z == playerPos.z then
      local dist = getDistanceBetween(playerPos, cPos)
      if dist <= range then
        if isValidMonsterCreature(cr) then
          if not ignoreSet[cr:getName():lower()] then
            table.insert(monsters, { creature = cr, dist = dist, hp = cr:getHealthPercent(), name = cr:getName() })
          end
        elseif cr:isPlayer() and cr ~= g_game.getLocalPlayer() and not (cr.isNpc and cr:isNpc()) then
          table.insert(players, cr)
        end
      end
    end
  end
  return monsters, players
end

local function checkCountCondition(actualCount, op, expected)
  local exp = tonumber(expected) or 1
  if op == '<' then return actualCount < exp
  elseif op == '=' then return actualCount == exp
  else return actualCount >= exp end
end

local function faceCreatureDirection(player, target)
  if not player or not target then return end
  local pPos, tPos = player:getPosition(), target:getPosition()
  local dx, dy = tPos.x - pPos.x, tPos.y - pPos.y
  local dir = nil
  if math.abs(dx) >= math.abs(dy) then
    dir = (dx > 0) and East or West
  else
    dir = (dy > 0) and South or North
  end
  if dir and player:getDirection() ~= dir then
    g_game.turn(dir)
  end
end

local function isFriendAllowed(creature, filters)
  if not creature or not filters then return false end
  if filters.allScreen then return true end
  if filters.party then
    local inParty = (creature.isPartyMember and creature:isPartyMember())
      or (creature.getShield and creature:getShield() >= 3 and creature:getShield() <= 10)
    if inParty then return true end
  end
  if filters.guild and creature.getEmblem and creature:getEmblem() == 1 then return true end
  local extra = parseCommaSet(filters.extraFriends)
  return extra[creature:getName():lower()] == true
end

local function getCreatureVocName(cr)
  if cr then
    if cr.isMonk and cr:isMonk() then return 'Monk' end
    if cr.isDruid and cr:isDruid() then return 'Druid' end
    if cr.isSorcerer and cr:isSorcerer() then return 'Sorcerer' end
    if cr.isPaladin and cr:isPaladin() then return 'Paladin' end
    if cr.isKnight and cr:isKnight() then return 'Knight' end
    local voc = cr.getVocation and cr:getVocation() or 0
    if voc == 5 or voc == 15 then return 'Monk'
    elseif voc == 4 or voc == 14 then return 'Druid'
    elseif voc == 3 or voc == 13 then return 'Sorcerer'
    elseif voc == 2 or voc == 12 then return 'Paladin'
    elseif voc == 1 or voc == 11 then return 'Knight'
    end
    local name = cr.getName and cr:getName():lower() or ''
    if name:find('monk') then return 'Monk'
    elseif name:find('druid') then return 'Druid'
    elseif name:find('sorcerer') then return 'Sorcerer'
    elseif name:find('paladin') then return 'Paladin'
    elseif name:find('knight') then return 'Knight'
    end
  end
  return nil
end

local function hasCoreBlessings(player)
  if not player then return true end
  if lastBlessDialogCoreOk ~= nil then
    return lastBlessDialogCoreOk
  end
  if lastBlessVisualState ~= nil then
    return lastBlessVisualState >= 2
  end
  if not player.getBlessings or not Blessings then return true end
  local b = tonumber(player:getBlessings()) or 0
  if b <= 1 then return false end
  if Bit and Bit.hasBit then
    for _, flag in ipairs({
      Blessings.WisdomOfSolitude,
      Blessings.SparkOfPhoenix,
      Blessings.FireOfSuns,
      Blessings.SpiritualShielding,
      Blessings.EmbraceOfTibia
    }) do
      if flag and not Bit.hasBit(b, flag) then
        return false
      end
    end
  end
  return true
end

local function findVisibleDummyThing(pPos, dummyId)
  local firstFound = nil
  for dx = -7, 7 do
    for dy = -5, 5 do
      local tile = g_map.getTile({ x = pPos.x + dx, y = pPos.y + dy, z = pPos.z })
      if tile then
        for _, thing in ipairs(tile:getThings()) do
          if thing:isItem() and EXERCISE_DUMMY_CATALOG[thing:getId()] then
            if thing:getId() == dummyId then return thing end
            if not firstFound then firstFound = thing end
          end
        end
      end
    end
  end
  return firstFound
end

local function findContainerItemById(targetId)
  for _, cont in pairs(g_game.getContainers()) do
    for _, item in ipairs(cont:getItems()) do
      if item:getId() == targetId then return item end
    end
  end
  return nil
end

local function getTileHasAnyId(tile, idSet)
  if not tile or not idSet then return nil end
  for _, item in ipairs(tile:getItems() or {}) do
    if idSet[item:getId()] then return item end
  end
  local g = tile:getGround()
  if g and idSet[g:getId()] then return g end
  return nil
end

local function isAvoidTile(pos, avoidSet)
  local tile = g_map.getTile(pos)
  return getTileHasAnyId(tile, avoidSet) ~= nil
end

local function isFollowTerrainWalkable(pos)
  local tile = g_map.getTile(pos)
  if not tile then return false end
  if not tile:isWalkable(false) then return false end
  return true
end

local function hasBlockingMonsterAt(pos, pPos)
  if pos.x == pPos.x and pos.y == pPos.y and pos.z == pPos.z then return false end
  local tile = g_map.getTile(pos)
  if not tile then return false end
  for _, cr in ipairs(tile:getCreatures() or {}) do
    if cr and cr:isMonster() and not cr:isDead() then
      return true
    end
  end
  return false
end

local function isFollowTileWalkableSafe(pos, pPos, avoidSet)
  if not isFollowTerrainWalkable(pos) then return false end
  if isAvoidTile(pos, avoidSet) then return false end
  if hasBlockingMonsterAt(pos, pPos) then return false end
  return true
end

local function findFollowNearestSafeTile(dest, pPos, avoidSet, skipPos)
  for r = 1, 2 do
    local bestPos, bestScore = nil, 99999
    for dx = -r, r do
      for dy = -r, r do
        if dx ~= 0 or dy ~= 0 then
          local cand = { x = dest.x + dx, y = dest.y + dy, z = dest.z }
          if not (skipPos and cand.x == skipPos.x and cand.y == skipPos.y) and isFollowTileWalkableSafe(cand, pPos, avoidSet) then
            local distDest = math.abs(cand.x - dest.x) + math.abs(cand.y - dest.y)
            local distMe = math.max(math.abs(cand.x - pPos.x), math.abs(cand.y - pPos.y))
            local score = (distDest * 10) + distMe
            if score < bestScore then
              bestScore = score
              bestPos = cand
            end
          end
        end
      end
    end
    if bestPos then return bestPos end
  end
  return nil
end

local function getFollowBestLevitateDir(pPos, preferredDir)
  local dirs = {
    [North] = { 0, -1 },
    [East]  = { 1, 0 },
    [South] = { 0, 1 },
    [West]  = { -1, 0 }
  }
  local p = dirs[preferredDir]
  if p and not isFollowTerrainWalkable({ x = pPos.x + p[1], y = pPos.y + p[2], z = pPos.z }) then
    return preferredDir
  end
  for _, d in ipairs({ North, East, South, West }) do
    local v = dirs[d]
    if not isFollowTerrainWalkable({ x = pPos.x + v[1], y = pPos.y + v[2], z = pPos.z }) then
      return d
    end
  end
  return preferredDir
end

local function hasFollowLocalBypass(blockPos, prevPos, nextPos, pPos, avoidSet)
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local bp = { x = blockPos.x + dx, y = blockPos.y + dy, z = blockPos.z }
        if isFollowTileWalkableSafe(bp, pPos, avoidSet) then
          local dPrev = math.max(math.abs(bp.x - prevPos.x), math.abs(bp.y - prevPos.y))
          local dNext = math.max(math.abs(bp.x - nextPos.x), math.abs(bp.y - nextPos.y))
          if dPrev <= 1 and dNext <= 1 then
            return true
          end
        end
      end
    end
  end
  return false
end

local function getFollowTrailSafeDest(dest, pPos, avoidSet)
  local startIdx, minDist = nil, 999
  for i = #followTrail, 1, -1 do
    local p = followTrail[i]
    if p.z == dest.z then
      local d = math.max(math.abs(p.x - pPos.x), math.abs(p.y - pPos.y))
      if d <= 3 and d < minDist then
        minDist = d
        startIdx = i
      end
    end
  end

  if startIdx then
    local lastFree = { x = pPos.x, y = pPos.y, z = pPos.z }
    for i = startIdx, 1, -1 do
      local p = followTrail[i]
      if p.z == dest.z then
        local nextP = followTrail[i - 1] or dest
        if not isFollowTileWalkableSafe(p, pPos, avoidSet) then
          if not hasFollowLocalBypass(p, lastFree, nextP, pPos, avoidSet) then
            return lastFree, true
          end
        else
          lastFree = { x = p.x, y = p.y, z = p.z }
        end
      end
    end
  end

  local curDist = math.max(math.abs(pPos.x - dest.x), math.abs(pPos.y - dest.y))
  if curDist >= 1 then
    local terrainOpts, freeOpts = 0, 0
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local cand = { x = pPos.x + dx, y = pPos.y + dy, z = dest.z }
          local newDist = math.max(math.abs(cand.x - dest.x), math.abs(cand.y - dest.y))
          if newDist < curDist and isFollowTerrainWalkable(cand) and not isAvoidTile(cand, avoidSet) then
            terrainOpts = terrainOpts + 1
            if isFollowTileWalkableSafe(cand, pPos, avoidSet) then
              freeOpts = freeOpts + 1
            end
          end
        end
      end
    end
    if terrainOpts > 0 and freeOpts == 0 then
      return { x = pPos.x, y = pPos.y, z = pPos.z }, true
    end
  end
  return dest, false
end

local DIR_DELTAS = {
  [North]     = { 0, -1 },
  [NorthEast] = { 1, -1 },
  [East]      = { 1, 0 },
  [SouthEast] = { 1, 1 },
  [South]     = { 0, 1 },
  [SouthWest] = { -1, 1 },
  [West]      = { -1, 0 },
  [NorthWest] = { -1, -1 }
}

local function findSafeFollowStepAvoiding(pPos, dest, avoidSet, allowGoalPos)
  if pPos.x == dest.x and pPos.y == dest.y then return nil end
  local goalKey = dest.x .. ',' .. dest.y
  local startKey = pPos.x .. ',' .. pPos.y
  local queue = { { x = pPos.x, y = pPos.y, firstDir = nil } }
  local visited = { [startKey] = true }
  local head = 1
  local dirsOrder = { North, South, East, West, NorthEast, NorthWest, SouthEast, SouthWest }
  local bestFallbackDir, bestFallbackDist = nil, 9999

  while head <= #queue and head <= 350 do
    local cur = queue[head]
    head = head + 1
    for _, dir in ipairs(dirsOrder) do
      local dv = DIR_DELTAS[dir]
      local nx, ny = cur.x + dv[1], cur.y + dv[2]
      if math.abs(nx - pPos.x) <= 10 and math.abs(ny - pPos.y) <= 10 then
        local k = nx .. ',' .. ny
        if not visited[k] then
          visited[k] = true
          local np = { x = nx, y = ny, z = pPos.z }
          local isGoal = (k == goalKey)
          local canStep = (isGoal and allowGoalPos) and isFollowTerrainWalkable(np) or isFollowTileWalkableSafe(np, pPos, avoidSet)
          if canStep then
            local fDir = cur.firstDir or dir
            if isGoal then
              return fDir
            end
            local dg = math.max(math.abs(nx - dest.x), math.abs(ny - dest.y))
            if dg < bestFallbackDist then
              bestFallbackDist = dg
              bestFallbackDir = fDir
            end
            table.insert(queue, { x = nx, y = ny, firstDir = fDir })
          end
        end
      end
    end
  end
  return bestFallbackDir
end

local function walkSafeTo(player, pPos, dest, avoidSet, allowGoalPos)
  local path = g_map.findPath(pPos, dest, 5000, 0)
  if path and #path > 0 then
    local cx, cy = pPos.x, pPos.y
    local pathHasAvoid = false
    for idx, stepDir in ipairs(path) do
      local dv = DIR_DELTAS[stepDir]
      if dv then
        cx = cx + dv[1]
        cy = cy + dv[2]
        local isGoal = (idx == #path and cx == dest.x and cy == dest.y)
        if not (isGoal and allowGoalPos) and isAvoidTile({ x = cx, y = cy, z = pPos.z }, avoidSet) then
          pathHasAvoid = true
          break
        end
      end
    end
    if not pathHasAvoid then
      if player:autoWalk(dest) then return true end
      g_game.walk(path[1])
      return true
    end
  end
  local safeDir = findSafeFollowStepAvoiding(pPos, dest, avoidSet, allowGoalPos)
  if safeDir then
    g_game.walk(safeDir)
    return true
  end
  if allowGoalPos then
    return player:autoWalk(dest)
  end
  return false
end

local function runFollowEngine(player, pPos, now)
  local tl = charConfig.tools
  if not tl.follow.enabled then return end
  local fCfg = tl.follow
  local desiredName = (fCfg.name or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  local target = nil

  if desiredName ~= '' then
    for _, cr in ipairs(g_map.getSpectators(pPos, false) or {}) do
      if cr ~= player and cr:getName():lower() == desiredName then
        target = cr
        break
      end
    end
  else
    target = g_game.getFollowingCreature() or g_game.getAttackingCreature()
  end

  local avoidSet = getFollowIdSet('avoid')
  local stairsSet = getFollowIdSet('stairs')
  local tpSet = getFollowIdSet('teleport')
  local useSet = getFollowIdSet('use')
  local ropeSet = getFollowIdSet('rope')
  local wantDist = math.max(1, math.min(4, tonumber(fCfg.dist) or 1))
  local mode = fCfg.mode or 'Default'
  local targetIsOnScreen = (target ~= nil and target:getPosition() ~= nil and target:getPosition().z == pPos.z)

  if followLastMyZ == 0 then followLastMyZ = pPos.z end
  if pPos.z ~= followLastMyZ then
    if followWasTargetOnScreen and not targetIsOnScreen and not followWrongFloorReturn then
      followWrongFloorReturn = true
      followWrongFloorTime = now
      followPrevSafeZ = followLastMyZ
    else
      followWrongFloorReturn = false
      if not targetIsOnScreen then
        lastFollowTargetPos = nil
      end
    end
    followLastMyZ = pPos.z
    followLastDest = nil
    followTrail = {}
    followLevitateStep = 0
  elseif targetIsOnScreen then
    followWrongFloorReturn = false
  end
  followWasTargetOnScreen = targetIsOnScreen

  if followWrongFloorReturn and not targetIsOnScreen then
    if (now - followWrongFloorTime) > 3000 then
      followWrongFloorReturn = false
      return
    end
    local retPos, retKind, retThing = nil, nil, nil
    for r = 0, 1 do
      for ox = -r, r do
        for oy = -r, r do
          if math.max(math.abs(ox), math.abs(oy)) == r then
            local cp = { x = pPos.x + ox, y = pPos.y + oy, z = pPos.z }
            local tile = g_map.getTile(cp)
            if tile then
              local it = getTileHasAnyId(tile, useSet)
              if it then retPos, retKind, retThing = cp, 'use', it break end
              it = getTileHasAnyId(tile, ropeSet)
              if it then retPos, retKind, retThing = cp, 'rope', it break end
              if r == 1 then
                it = getTileHasAnyId(tile, stairsSet) or getTileHasAnyId(tile, tpSet) or getTileHasAnyId(tile, avoidSet)
                if it then retPos, retKind, retThing = cp, 'step', it break end
              end
            end
          end
        end
        if retKind then break end
      end
      if retKind then break end
    end
    if (now - followLastGoToTime) >= 220 then
      if retKind == 'use' and retThing then
        g_game.use(retThing)
      elseif retKind == 'rope' and retThing then
        g_game.useInventoryItemWith(charConfig.cavebot.ropeId or 3003, retThing)
      elseif retKind == 'step' and retPos then
        player:autoWalk(retPos)
      else
        local spell = (pPos.z < followPrevSafeZ) and 'exani hur "down"' or 'exani hur "up"'
        g_game.talk(spell)
      end
      followLastGoToTime = now
    end
    return
  end

  if (now - lastFollowTime) < 120 then return end

  if targetIsOnScreen then
    local tPos = target:getPosition()
    local tDir = target:getDirection()

    if not lastFollowTargetPos or lastFollowTargetPos.x ~= tPos.x or lastFollowTargetPos.y ~= tPos.y or lastFollowTargetPos.z ~= tPos.z then
      if lastFollowTargetPos and lastFollowTargetPos.z == tPos.z then
        local vx, vy = tPos.x - lastFollowTargetPos.x, tPos.y - lastFollowTargetPos.y
        if vx ~= 0 or vy ~= 0 then
          lastFollowTrailVec = {
            x = (vx > 0 and 1) or (vx < 0 and -1) or 0,
            y = (vy > 0 and 1) or (vy < 0 and -1) or 0
          }
        end
      else
        followTrail = {}
        lastFollowTrailVec = { x = 0, y = 0 }
      end
      table.insert(followTrail, 1, { x = tPos.x, y = tPos.y, z = tPos.z })
      if #followTrail > 10 then table.remove(followTrail) end
      lastFollowTargetMoveTime = now
      lastFollowTargetPos = { x = tPos.x, y = tPos.y, z = tPos.z }
    end
    lastFollowTargetDir = tDir
    followLevitateStep = 0
    followLostChaseCount = 0
    followVanishedAtEdge = (math.abs(tPos.x - pPos.x) >= 6 or math.abs(tPos.y - pPos.y) >= 5)

    if g_game.getFollowingCreature and g_game.getFollowingCreature() ~= nil and g_game.follow then
      ignoreNativeFollowEvent = true
      pcall(g_game.follow, nil)
      ignoreNativeFollowEvent = false
    end

    local dist = getDistanceBetween(pPos, tPos)
    local isTargetMoving = (now - lastFollowTargetMoveTime) < 450

    local dirVec = { [North] = {0, -1}, [South] = {0, 1}, [East] = {1, 0}, [West] = {-1, 0} }
    local leftDir = { [North] = West, [West] = South, [South] = East, [East] = North }
    local rightDir = { [North] = East, [East] = South, [South] = West, [West] = North }
    local backDir = { [North] = South, [South] = North, [East] = West, [West] = East }

    local dest = { x = pPos.x, y = pPos.y, z = pPos.z }
    if mode == 'Front' then
      local v = dirVec[tDir] or {0, 1}
      dest = { x = tPos.x + v[1] * wantDist, y = tPos.y + v[2] * wantDist, z = pPos.z }
    elseif mode == 'Back' then
      local v = dirVec[backDir[tDir] or South] or {0, -1}
      dest = { x = tPos.x + v[1] * wantDist, y = tPos.y + v[2] * wantDist, z = pPos.z }
    elseif mode == 'Left' then
      local v = dirVec[leftDir[tDir] or West] or {-1, 0}
      dest = { x = tPos.x + v[1] * wantDist, y = tPos.y + v[2] * wantDist, z = pPos.z }
    elseif mode == 'Right' then
      local v = dirVec[rightDir[tDir] or East] or {1, 0}
      dest = { x = tPos.x + v[1] * wantDist, y = tPos.y + v[2] * wantDist, z = pPos.z }
    else
      if dist <= wantDist and not isAvoidTile(pPos, avoidSet) then
        dest = { x = pPos.x, y = pPos.y, z = pPos.z }
      else
        local dx, dy = pPos.x - tPos.x, pPos.y - tPos.y
        local destX = (dx > wantDist and (tPos.x + wantDist)) or (dx < -wantDist and (tPos.x - wantDist)) or pPos.x
        local destY = (dy > wantDist and (tPos.y + wantDist)) or (dy < -wantDist and (tPos.y - wantDist)) or pPos.y
        dest = { x = destX, y = destY, z = pPos.z }
      end
    end

    if not isFollowTileWalkableSafe(dest, pPos, avoidSet) then
      local safe = findFollowNearestSafeTile(dest, pPos, avoidSet, tPos)
      if safe then dest = safe end
    end

    for ox = -1, 1 do
      for oy = -1, 1 do
        if ox ~= 0 or oy ~= 0 then
          local cp = { x = pPos.x + ox, y = pPos.y + oy, z = pPos.z }
          local tile = g_map.getTile(cp)
          if tile then
            local doorIt = getTileHasAnyId(tile, useSet)
            if doorIt and doorIt:getId() ~= 1948 and not isAvoidTile(cp, avoidSet) then
              local distBefore = getDistanceBetween(pPos, dest)
              local distAfter = getDistanceBetween(cp, dest)
              if distAfter < distBefore and (now - followLastDoorUseTime) > 400 then
                g_game.use(doorIt)
                followLastDoorUseTime = now
                lastFollowTime = now
                return
              end
            end
          end
        end
      end
    end

    dest = getFollowTrailSafeDest(dest, pPos, avoidSet)

    if dest.x ~= pPos.x or dest.y ~= pPos.y then
      local retryDelay = isTargetMoving and 180 or 280
      local destChanged = (not followLastDest) or followLastDest.x ~= dest.x or followLastDest.y ~= dest.y
      if destChanged or (now - followLastGoToTime) >= retryDelay then
        walkSafeTo(player, pPos, dest, avoidSet, false)
        followLastDest = { x = dest.x, y = dest.y }
        followLastGoToTime = now
      end
      lastFollowTime = now
    else
      followLastDest = { x = pPos.x, y = pPos.y }
      if fCfg.turn and dist <= (wantDist + 1) and player:getDirection() ~= tDir then
        g_game.turn(tDir)
        lastFollowTime = now
      end
    end
  elseif lastFollowTargetPos and lastFollowTargetPos.z == pPos.z then
    local ropeId = charConfig.cavebot.ropeId or 3003
    local actionPos, actionKind, actionThing = nil, nil, nil
    for r = 0, 2 do
      for ox = -r, r do
        for oy = -r, r do
          if math.max(math.abs(ox), math.abs(oy)) == r then
            local cp = { x = lastFollowTargetPos.x + ox, y = lastFollowTargetPos.y + oy, z = pPos.z }
            local tile = g_map.getTile(cp)
            if tile then
              local it = getTileHasAnyId(tile, stairsSet) or getTileHasAnyId(tile, tpSet)
              if it then actionPos, actionKind, actionThing = cp, 'step', it break end
              it = getTileHasAnyId(tile, useSet)
              if it then actionPos, actionKind, actionThing = cp, 'use', it break end
              it = getTileHasAnyId(tile, ropeSet)
              if it then actionPos, actionKind, actionThing = cp, 'rope', it break end
            end
          end
        end
        if actionPos then break end
      end
      if actionPos then break end
    end

    local dest = actionPos or lastFollowTargetPos
    local distToDest = getDistanceBetween(pPos, dest)
    local canInteract = ((actionKind == 'use' or actionKind == 'rope') and distToDest <= 1) or (distToDest == 0)

    if not actionKind and followVanishedAtEdge and distToDest <= 1 and followLostChaseCount < 5 then
      local dirV = DIR_DELTAS[lastFollowTargetDir] or { 0, 0 }
      local stepX = (lastFollowTrailVec.x ~= 0 or lastFollowTrailVec.y ~= 0) and lastFollowTrailVec.x or dirV[1]
      local stepY = (lastFollowTrailVec.x ~= 0 or lastFollowTrailVec.y ~= 0) and lastFollowTrailVec.y or dirV[2]
      local np = { x = lastFollowTargetPos.x + stepX, y = lastFollowTargetPos.y + stepY, z = pPos.z }
      if (stepX ~= 0 or stepY ~= 0) and isFollowTileWalkableSafe(np, pPos, avoidSet) then
        local adv = np
        for s = 2, 3 do
          local tp = { x = lastFollowTargetPos.x + (stepX * s), y = lastFollowTargetPos.y + (stepY * s), z = pPos.z }
          if isFollowTileWalkableSafe(tp, pPos, avoidSet) then adv = tp else break end
        end
        lastFollowTargetPos = adv
        dest = adv
        distToDest = getDistanceBetween(pPos, dest)
        canInteract = false
        followLostChaseCount = followLostChaseCount + 1
      end
    end

    if not canInteract then
      local safeDest = getFollowTrailSafeDest(dest, pPos, avoidSet)
      if safeDest.x ~= pPos.x or safeDest.y ~= pPos.y then
        local destChanged = (not followLastDest) or followLastDest.x ~= safeDest.x or followLastDest.y ~= safeDest.y
        if destChanged or (now - followLastGoToTime) >= 220 then
          local allowGoal = (actionKind == 'step' and safeDest.x == dest.x and safeDest.y == dest.y)
          walkSafeTo(player, pPos, safeDest, avoidSet, allowGoal)
          followLastDest = { x = safeDest.x, y = safeDest.y }
          followLastGoToTime = now
        end
      end
    elseif (now - followLastGoToTime) >= 150 then
      if actionKind == 'step' then
        walkSafeTo(player, pPos, dest, avoidSet, true)
      elseif actionKind == 'use' and actionThing then
        g_game.use(actionThing)
        lastFollowTargetPos = nil
      elseif actionKind == 'rope' and actionThing then
        g_game.useInventoryItemWith(ropeId, actionThing)
        lastFollowTargetPos = nil
      elseif not actionKind then
        local levDir = getFollowBestLevitateDir(pPos, lastFollowTargetDir)
        if player:getDirection() ~= levDir then
          g_game.turn(levDir)
        end
        if followLevitateStep == 0 then
          g_game.talk('exani hur "up"')
          followLevitateStep = 1
          followLastLevitateTime = now
        elseif followLevitateStep == 1 and (now - followLastLevitateTime) >= 350 then
          g_game.talk('exani hur "down"')
          followLevitateStep = 2
          followLastLevitateTime = now
        elseif followLevitateStep == 2 and (now - followLastLevitateTime) >= 700 then
          lastFollowTargetPos = nil
          followLevitateStep = 0
        end
      end
      followLastGoToTime = now
    end
    lastFollowTime = now
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

function helperTickError(section, err)
  helperTickErrAt = helperTickErrAt or {}
  local t = g_clock.millis()
  if t - (helperTickErrAt[section] or -10000) > 5000 then
    helperTickErrAt[section] = t
    perror('[Helper] erro em ' .. section .. ': ' .. tostring(err))
  end
end

function saveCurrentProfileThrottled()
  local t = g_clock.millis()
  if t - (helperLastSaveAt or -10000) >= 5000 then
    helperLastSaveAt = t
    helperSavePending = false
    saveCurrentProfile()
  else
    helperSavePending = true
  end
end

SHOOTER_COUNT_RANGE = {
  -- Knight
  ['exori'] = 1, ['exori gran'] = 1, ['exori min'] = 1,
  ['exori ico'] = 1, ['exori gran ico'] = 1, ['exeta res'] = 1,
  ['exori mas'] = 3,
  -- Sorcerer / Druid (círculo grande ao redor do player)
  ['exevo gran mas flam'] = 5, ['exevo gran mas vis'] = 5,
  ['exevo gran mas tera'] = 5, ['exevo gran mas frigo'] = 5,
  -- Paladin
  ['exevo mas san'] = 3,
}
function getRuleCountRange(rule, words)
  if (rule.countOp or '>=') ~= '>=' then return 7 end
  local byWords = SHOOTER_COUNT_RANGE[(words or ''):lower()]
  if byWords then return byWords end
  if rule.cond and rule.cond.adjacent then return 1 end
  return 7
end

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
  if helperWindow and helperWindow:isVisible() and panels and panels.cavebot and panels.cavebot:isVisible() then
    centerCavebotMinimap()
  end
  if cavebotAutoRec and pPos then
    local recDist = math.max(1, tonumber(charConfig.cavebot.autoRecDist) or 3)
    local wps = charConfig.cavebot.waypoints
    local lastWpPos = (#wps > 0) and getWaypointPos(wps[#wps]) or nil
    if lastAutoRecPos and (lastAutoRecPos.z ~= pPos.z or getDistanceBetween(lastAutoRecPos, pPos) >= 8) then
      local standPos = (lastAutoRecPos.z ~= pPos.z) and resolveFloorChangeStandPos(lastAutoRecPos, pPos) or lastAutoRecPos
      if not lastWpPos or lastWpPos.x ~= standPos.x or lastWpPos.y ~= standPos.y or lastWpPos.z ~= standPos.z then
        table.insert(wps, string.format('Stand: %d, %d, %d', standPos.x, standPos.y, standPos.z))
      end
      table.insert(wps, string.format('Node: %d, %d, %d', pPos.x, pPos.y, pPos.z))
      lastAutoRecPos = { x = pPos.x, y = pPos.y, z = pPos.z }
      selectedCavebotWpIdx = #wps
      refreshCavebotUI(true)
      saveCurrentProfileThrottled()
    elseif not lastAutoRecPos or getDistanceBetween(lastAutoRecPos, pPos) >= recDist then
      if not lastWpPos or lastWpPos.x ~= pPos.x or lastWpPos.y ~= pPos.y or lastWpPos.z ~= pPos.z then
        table.insert(wps, string.format('Node: %d, %d, %d', pPos.x, pPos.y, pPos.z))
        selectedCavebotWpIdx = #wps
        refreshCavebotUI(true)
        saveCurrentProfileThrottled()
      end
      lastAutoRecPos = { x = pPos.x, y = pPos.y, z = pPos.z }
    end
  end

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
  local okHeal, errHeal = pcall(function()
    if vp.healing.enabled then
      if vp.healing.manaShield.enabled and (currentVocName == 'Sorcerer' or currentVocName == 'Druid' or currentVocName == 'Monk')
        and vp.healing.manaShield.words ~= '' and not hasUtamo and not inPz and (now - lastCastTime) >= 1000 then
        g_game.talk(vp.healing.manaShield.words)
        lastCastTime = now
      end

      if vp.healing.curePara.enabled and vp.healing.curePara.words ~= '' and isParalyzed and (now - lastCastTime) >= 900 then
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

      -- A cada tick a regra de maior prioridade com candidatos decide o alvo (A-I), mesmo
      -- que o monstro atual esteja com 1% de vida. Troca imediata.
      local chosen = nil
      local anyRule = false
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
            local effMode = (rule.mode and rule.mode ~= 'Default') and rule.mode or (tgtCfg.mode or 'A')
            sortByTargetMode(cands, effMode)
            chosen = cands[1].creature
            break
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
          sortByTargetMode(tgtMonsters, tgtCfg.mode or 'A')
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
            local matchingCount = 0
            for _, m in ipairs(nearbyMonsters) do
              if m.dist <= cntRange then matchingCount = matchingCount + 1 end
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
            local hpRef = (rule.priority == 'Target Name') and (firstMatchedCreature or tgt) or tgt
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
              if tgt and tgt:getPosition() then
                adjOk = (getDistanceBetween(pPos, tgt:getPosition()) <= 1)
              else
                adjOk = (adjacentMonsters >= 1)
              end
            end
            local stopOk = (not c.stopped) or ((now - playerStopTracker.since) >= (c.stoppedMs or 1000))

            if nameOk and countOk and hpMinOk and hpMaxOk and mpOk and cdOk and trapOk and adjOk and stopOk then
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

  if tl.manaTrain.enabled and tl.manaTrain.words ~= '' and (tl.manaTrain.pzCast or not inPz)
     and mpPct >= (tonumber(tl.manaTrain.pct) or 85) and (now - lastManaTrainTime) >= 2200
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

  runFollowEngine(player, pPos, now)

  -- 4. CAVEBOT ENGINE (OTClient-native Percentage Speed + Dynamic Lure + Stand vs Node)
  local okCb, errCb = pcall(function()
  if charConfig.cavebot.enabled then
    local cb = charConfig.cavebot
    local cbS = cb.settings or {}
    local mobIdx = math.min(5, #nearbyMonsters)
    local activeSpeed = (cbS.dynamicLure ~= false and cbS.lureSpeeds and tonumber(cbS.lureSpeeds[mobIdx]))
      or tonumber(cbS.walkSpeedPct)
      or 100
    activeSpeed = math.max(0, math.min(100, math.floor(activeSpeed)))
    if cbS.dynamicLure ~= false and panels.cavebot then
      local bp = panels.cavebot:getChildById('bodyPanel')
      local tb = bp and bp:getChildById('cbTopControlsBox')
      local speedEd = tb and tb:getChildById('cbWalkSpeedEdit')
      if speedEd and not speedEd:isFocused() and speedEd:getText() ~= tostring(activeSpeed) then
        helperSpeedUiLock = true
        speedEd:setText(tostring(activeSpeed), true)
        helperSpeedUiLock = false
      end
    end
    local stepDelayMs = (activeSpeed >= 100) and 0 or math.max(120, math.floor(100 + (100 - activeSpeed) * 4.5))

    if activeSpeed <= 0 then
      if player:isAutoWalking() then
        player:stopAutoWalk()
      end
      lastCavebotStepTime = now
    else
      local stopCount = tonumber(cbS.stopMonsters) or 3
      local resumeCount = tonumber(cbS.walkMonsters) or 1
      local isGlobalLure = (cbS.lureMode == 'global')
      resumeCount = math.min(resumeCount, math.max(0, stopCount - 1))
      local wps = cb.waypoints or {}
      local idx = cb.currentWpIndex or 1
      if idx > #wps or idx < 1 then idx = 1 end
      local wpStr = wps[idx] or ''
      local wpLower = wpStr:lower()
      local wasPaused = cbPauseState

      if isGlobalLure then
        if #wps > 0 and (wpLower:find('^start lure') or wpLower:find('^end lure')) then
          cb.currentWpIndex = (idx % #wps) + 1
          idx = cb.currentWpIndex
          wpStr = wps[idx] or ''
          wpLower = wpStr:lower()
          cavebotAdvanceUI()
        end
        if #nearbyMonsters >= stopCount then
          cbPauseState = true
        elseif #nearbyMonsters <= resumeCount then
          cbPauseState = false
        end
      else
        -- BOX LURE: só segura em waypoint de lure/stand (não-Node); solta e avança na hora quando limpar
        if cbPauseState and #nearbyMonsters <= resumeCount then
          cbPauseState = false
          if #wps > 0 then
            cb.currentWpIndex = (idx % #wps) + 1
          end
          cavebotAdvanceUI()
        end
        if wpLower:find('^node') then cbPauseState = false end
      end

      if cbPauseState and not wasPaused then
        if player:isAutoWalking() then player:stopAutoWalk() end
        cavebotAdvanceUI()
      end

      if not cbPauseState and #wps > 0 then
        local function walkToCoord(destPos, forceFallbackDir)
          if activeSpeed < 100 then
            if player:isAutoWalking() then
              player:stopAutoWalk()
            end
            if (now - lastCavebotStepTime) >= stepDelayMs then
              if getDistanceBetween(pPos, destPos) == 1 then
                local dir = getDirectionFromPos(pPos, destPos)
                if dir then g_game.walk(dir) end
              else
                local path = g_map.findPath(pPos, destPos, 5000, 0)
                if path and #path > 0 then
                  g_game.walk(path[1])
                end
              end
              lastCavebotStepTime = now
            end
          elseif not player:isAutoWalking() then
            local ok = player:autoWalk(destPos)
            if not ok then
              if forceFallbackDir and getDistanceBetween(pPos, destPos) == 1 then
                local dir = getDirectionFromPos(pPos, destPos)
                if dir then g_game.walk(dir) end
              else
                local path = g_map.findPath(pPos, destPos, 5000, 0)
                if path and #path > 0 then
                  g_game.walk(path[1])
                end
              end
            end
          end
        end

        idx = cb.currentWpIndex or 1
        if idx > #wps or idx < 1 then idx = 1 end
        wpStr = wps[idx] or ''
        wpLower = wpStr:lower()

        local x, y, z = wpStr:match('(%d+),%s*(%d+),%s*(%d+)')
        if x and y and z then
          local dest = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
          if dest.z ~= pPos.z then
            ruleCooldowns.zWait = ruleCooldowns.zWait or now
            if (now - ruleCooldowns.zWait) >= 250 then
              ruleCooldowns.zWait = nil
              cb.currentWpIndex = (idx % #wps) + 1
              cavebotAdvanceUI()
            end
          else
            ruleCooldowns.zWait = nil
            local isNode = wpLower:find('^node') ~= nil
            local isAction = (wpLower:find('^rope') or wpLower:find('^hole') or wpLower:find('^shovel')
              or wpLower:find('^ladder') or wpLower:find('^use')) ~= nil
            local acceptDist = (isNode or isAction) and 1 or 0
            local dist = getDistanceBetween(pPos, dest)
            if dist <= acceptDist and (not isGlobalLure) and (not isNode) and (not isAction)
               and not cbPauseState and #nearbyMonsters >= stopCount then
              cbPauseState = true  -- box lure: segura aqui até limpar
              if player:isAutoWalking() then player:stopAutoWalk() end
              cavebotAdvanceUI()
            elseif dist <= acceptDist then
              if wpLower:find('^rope') then
                local tile = g_map.getTile(dest)
                if tile and tile:getTopUseThing() then
                  g_game.useInventoryItemWith(cb.ropeId or 3003, tile:getTopUseThing())
                end
              elseif wpLower:find('^hole') or wpLower:find('^shovel') then
                local tile = g_map.getTile(dest)
                if tile and tile:getTopUseThing() then
                  g_game.useInventoryItemWith(cb.shovelId or 5710, tile:getTopUseThing())
                end
              elseif wpLower:find('^ladder') or wpLower:find('^use') then
                local tile = g_map.getTile(dest)
                if tile and tile:getTopUseThing() then
                  g_game.use(tile:getTopUseThing())
                end
              end
              cb.currentWpIndex = (idx % #wps) + 1
              cavebotAdvanceUI()
              local nextStr = wps[cb.currentWpIndex] or ''
              local nx, ny, nz = nextStr:match('(%d+),%s*(%d+),%s*(%d+)')
              if nx and tonumber(nz) == pPos.z then
                local nextDest = { x = tonumber(nx), y = tonumber(ny), z = tonumber(nz) }
                local nextLower = nextStr:lower()
                local nextForce = (nextLower:find('^stand') or nextLower:find('^hole')) ~= nil
                walkToCoord(nextDest, nextForce)
              end
            else
              local forceDir = (wpLower:find('^stand') or wpLower:find('^hole')) ~= nil
              walkToCoord(dest, forceDir)
            end
          end
        else
          cb.currentWpIndex = (idx % #wps) + 1
        end
      end
      lastCavebotTime = now
    end
  end
  end)
  if not okCb then helperTickError('cavebot', errCb) end
end

-- ============================================================================
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

  for _, w in ipairs({ spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, keyCaptureModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal, helperWindow, statsWindow, helperButton }) do
    if w then w:destroy() end
  end
  spellSelectorModal, itemSelectorModal, renamePresetModal, conditionSettingsModal, keyCaptureModal, cavebotSettingsModal, cbControlMiniHud, idsMenuModal, huntListModal, helperWindow, statsWindow, helperButton = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
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
