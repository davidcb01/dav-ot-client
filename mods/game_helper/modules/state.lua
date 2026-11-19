-- Shared runtime state, catalogs, and math/creature helpers for game_helper

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
finisherSettingsModal = nil
refreshingFinisherUI = false

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
cavebotLureActive = false
cbPauseState = false
minimapTempFlags = {}
markedWorldTiles = {}
lastFollowTargetPos = nil
followTrail = {}
lastFollowTrailVec = { x = 0, y = 0 }
lastFollowTargetDir = South
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
followLastDoorUseTime = 0
followLastGoToTime = 0
followLastDest = nil
ignoreNativeFollowEvent = false
isLoadingUI = false
antiAfkFirstDone = false

function resetFollowRuntimeState()
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

function coerceArray(tbl)
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

function coerceIntArray(tbl)
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
activeIdsTab = 'follow'
activeFollowIdCat = 'stairs'
selectedProfileListKey = nil
refreshingLanguageCombos = false

DEFAULT_FOLLOW_IDS = {
  stairs   = { 8657,8658,1954,469,1947,437,438,607,7544,7546,385,33005,1977,5257,5691,33007,1949,34111,33181,33155,33175,33276,8690,1956,22139,29139,29143,29141 },
  rope     = { 12935, 386 },
  use      = { 1948, 1672, 8618 },
  teleport = { 1949, 33005, 11553, 35498, 34111, 29979, 29980 },
  avoid    = { 8657,8658,1954,469,1947,437,438,607,7544,7546,385,33005,1977,5257,5691,33007,1949,34111,33181,33155,33175,33276,8690,1956,29979,29980,22139,29139,29143,29141 }
}

activeSpellSlotCallback = nil
activeSpellSlotSelected = nil
activeSpellFilterGroup = nil

activeItemSlotCallback = nil
activeItemSlotSelected = nil
activeItemCategoryFilter = nil

activeKeyCaptureSlot = nil
activeKeyCaptureBtn = nil

-- Timers & cooldown tracking
lastCastTime = 0
lastShooterCastTime = 0
lastSupportShooterCastTime = 0
shooterDraftRule = nil
playerStopTracker = { pos = nil, since = 0 }
DEFAULT_ADJACENT_SPELLS = {}
origGameLook = nil
lastPotionTime = 0
lastHasteTime = 0
lastManaTrainTime = 0
lastEatTime = -15000
lastGoldTime = 0
lastExerciseTime = 0
lastBlessTime = -30000
lastBlessVisualState = nil
lastBlessDialogCoreOk = nil
lastAfkTime = 0
lastItemTimerTime = 0
lastFollowTime = 0
lastCavebotTime = 0
lastCavebotStepTime = 0
ruleCooldowns = {}
spellCooldownUntil = {}
confirmedSpellCastAt = {}
groupCooldownUntil = {}
shortcutActions = {}
lastShortcutDesc = nil
lastShortcutEventTime = 0
refreshingShooterUI = false
refreshingTargetUI = false
targetStopTracker = { id = 0, pos = nil, since = 0 }
antiStuckTracker = { wpIdx = 0, pos = nil, since = 0 }

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

function isSpellOnClientCooldown(words, now)
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
scannedExerciseWeapons = {}
scannedScreenDummys = {}
selectedWeaponScanIdx = 1
selectedDummyScanIdx = 1

-- All 134 Canary Server Food IDs (canary/data/scripts/actions/items/foods.lua)
CANARY_FOOD_IDS = {
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
FOOD_ID_SET = {}
for _, fid in ipairs(CANARY_FOOD_IDS) do
  FOOD_ID_SET[fid] = true
end

-- All Canary Exercise Weapon IDs (standard / store / durable / lasting)
EXERCISE_WEAPON_CATALOG = {
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
EXERCISE_DUMMY_CATALOG = {
  [28558] = 'Exercise Dummy',
  [28559] = 'Ferumbras Exercise Dummy',
  [28560] = 'Ferumbras Exercise Dummy',
  [28561] = 'Demon Exercise Dummy',
  [28562] = 'Demon Exercise Dummy',
  [28563] = 'Monk Exercise Dummy',
  [28564] = 'Monk Exercise Dummy',
  [28565] = 'Exercise Dummy'
}

function getExerciseWeaponName(id)
  local custom = charConfig and charConfig.customIds and charConfig.customIds.weapons
  if custom and custom[tostring(id)] then return custom[tostring(id)] end
  return EXERCISE_WEAPON_CATALOG[id]
end

function getExerciseDummyName(id)
  local custom = charConfig and charConfig.customIds and charConfig.customIds.dummys
  if custom and custom[tostring(id)] then return custom[tostring(id)] end
  return EXERCISE_DUMMY_CATALOG[id]
end

function getFollowIdSet(cat)
  local set = {}
  local followIds = charConfig and charConfig.customIds and charConfig.customIds.follow
  local cats = (cat == 'avoid') and { 'avoid', 'stairs', 'teleport' } or { cat }
  for _, c in ipairs(cats) do
    local list = (followIds and followIds[c]) or DEFAULT_FOLLOW_IDS[c] or {}
    for _, v in ipairs(list) do
      local n = tonumber(v)
      if n then set[n] = true end
    end
  end
  return set
end

ITEM_CATALOG = {
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

  -- Ammunition (Paladin Quiver Refill)
  { id = 35901, name = 'Diamond Arrow', desc = 'AoE Paladin Arrow (Lvl 150+)', cat = 'ammo' },
  { id = 15793, name = 'Crystalline Arrow', desc = 'Single-target Earth Arrow (Lvl 90+)', cat = 'ammo' },
  { id = 35902, name = 'Spectral Bolt', desc = 'High damage Bolt (Lvl 150+)', cat = 'ammo' },
  { id = 16141, name = 'Prismatic Bolt', desc = 'High damage Bolt (Lvl 90+)', cat = 'ammo' },
  { id = 16142, name = 'Drill Bolt', desc = 'Physical Bolt (Lvl 70+)', cat = 'ammo' },
  { id = 16143, name = 'Envenomed Arrow', desc = 'Earth Arrow (Lvl 70+)', cat = 'ammo' },
  { id = 14251, name = 'Tarsal Arrow', desc = 'Earth Arrow (Lvl 30+)', cat = 'ammo' },
  { id = 14252, name = 'Vortex Bolt', desc = 'Energy Bolt (Lvl 40+)', cat = 'ammo' },
  { id = 7365,  name = 'Onyx Arrow', desc = 'Physical Arrow (Lvl 40+)', cat = 'ammo' },
  { id = 7364,  name = 'Sniper Arrow', desc = 'Physical Arrow (Lvl 20+)', cat = 'ammo' },
  { id = 7363,  name = 'Piercing Bolt', desc = 'Physical Bolt (Lvl 30+)', cat = 'ammo' },
  { id = 3450,  name = 'Power Bolt', desc = 'Physical Bolt (Lvl 55+)', cat = 'ammo' },
  { id = 6528,  name = 'Infernal Bolt', desc = 'High damage Bolt (Lvl 110+)', cat = 'ammo' },
  { id = 3449,  name = 'Burst Arrow', desc = 'AoE Fire Arrow', cat = 'ammo' },
  { id = 3447,  name = 'Arrow', desc = 'Basic Arrow', cat = 'ammo' },
  { id = 3446,  name = 'Bolt', desc = 'Basic Bolt', cat = 'ammo' },
  { id = 25759, name = 'Royal Star', desc = 'Throwing Star (Lvl 120+)', cat = 'ammo' },
  { id = 7368,  name = 'Assassin Star', desc = 'Throwing Star (Lvl 80+)', cat = 'ammo' },

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
SPELL_CLIENTID_OVERRIDES = {
  ['exura vita'] = 3,
  ['exeta res'] = 96,
  ['exeta amp res'] = 111
}

EXTRA_SPELLS = {
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

function deepCopy(orig)
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

function getVocMatchTable(vocName)
  if vocName == 'Knight' then return { [4] = true, [8] = true }
  elseif vocName == 'Paladin' then return { [3] = true, [7] = true }
  elseif vocName == 'Sorcerer' then return { [1] = true, [5] = true }
  elseif vocName == 'Druid' then return { [2] = true, [6] = true }
  elseif vocName == 'Monk' then return { [9] = true, [10] = true }
  end
  return { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true }
end

-- ============================================================================


function getDistanceBetween(p1, p2)
  if not p1 or not p2 then return 999 end
  if p1.z ~= p2.z then return 999 end
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

function getDirectionFromPos(fromPos, toPos)
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

function resolveFloorChangeStandPos(oldPos, newPos)
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

function parseCommaSet(str)
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

function isValidMonsterCreature(cr)
  if not cr or (cr.isDead and cr:isDead()) then return false end
  if not (cr.isMonster and cr:isMonster()) then return false end
  if cr.isNpc and cr:isNpc() then return false end
  if cr.isPlayer and cr:isPlayer() then return false end
  if cr.getHealthPercent and cr:getHealthPercent() <= 0 then return false end
  return true
end

reachabilityCache = {}

function isMonsterReachable(pPos, cr, now)
  if not pPos or not cr then return false end
  local cPos = cr:getPosition()
  if not cPos or cPos.z ~= pPos.z then return false end
  if getDistanceBetween(pPos, cPos) <= 1 then return true end
  local cid = cr.getId and cr:getId() or tostring(cr)
  local entry = reachabilityCache[cid]
  if entry and (now - entry.t) < 350 and entry.px == pPos.x and entry.py == pPos.y and entry.pz == pPos.z
     and entry.cx == cPos.x and entry.cy == cPos.y then
    return entry.ok
  end
  local ok = false
  local directPath = g_map.findPath(pPos, cPos, 2500, 1)
  if directPath and #directPath > 0 then
    ok = true
  else
    for dx = -1, 1 do
      for dy = -1, 1 do
        if dx ~= 0 or dy ~= 0 then
          local adj = { x = cPos.x + dx, y = cPos.y + dy, z = cPos.z }
          local tile = g_map.getTile(adj)
          if tile and tile:isWalkable(false) then
            local p = g_map.findPath(pPos, adj, 2500, 0)
            if p and #p > 0 then
              ok = true
              break
            end
          end
        end
      end
      if ok then break end
    end
  end
  reachabilityCache[cid] = { t = now, px = pPos.x, py = pPos.y, pz = pPos.z, cx = cPos.x, cy = cPos.y, ok = ok }
  return ok
end

function getNearbyMonsters(playerPos, range, ignoreListStr)
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

function checkCountCondition(actualCount, op, expected)
  local exp = tonumber(expected) or 1
  if op == '<' then return actualCount < exp
  elseif op == '=' then return actualCount == exp
  else return actualCount >= exp end
end

function faceCreatureDirection(player, target)
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

function isFriendAllowed(creature, filters)
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

function getCreatureVocName(cr)
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

function hasCoreBlessings(player)
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

function findVisibleDummyThing(pPos, dummyId)
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

function findContainerItemById(targetId)
  for _, cont in pairs(g_game.getContainers()) do
    for _, item in ipairs(cont:getItems()) do
      if item:getId() == targetId then return item end
    end
  end
  return nil
end


function helperTickError(section, err)
  helperTickErrAt = helperTickErrAt or {}
  local t = g_clock.millis()
  if t - (helperTickErrAt[section] or -10000) > 5000 then
    helperTickErrAt[section] = t
    perror('[Helper] erro em ' .. section .. ': ' .. tostring(err))
  end
end

-- ============================================================================
-- Extended Automation Catalogs & Runtime State
-- ============================================================================
DEFAULT_DOOR_IDS = {
  5007, 8265, 1629, 1632, 5129, 6252, 6249, 7715, 7712, 7714,
  7719, 6256, 1669, 1672, 5125, 5115, 5124, 17701, 17710, 1642,
  6260, 5107, 4912, 6251, 5291, 1683, 1696, 1692, 5006, 2179,
  5116, 11705, 30772, 30774, 6248, 5735, 5732, 5120, 23873, 5736,
  6264, 5122, 30049, 30042, 5131, 8363, 5293, 1664, 5111, 5098,
  22632, 22639, 36547, 1671, 1694, 8361, 31570, 20444, 17572, 17563,
  17712, 17703, 2177, 1689, 30833, 30835, 30849, 33632, 5104, 20446,
  20453, 6891, 6900, 6901, 1685, 5113, 50282, 50284, 49678, 49684,
  49686, 49680, 8250, 8253, 5281, 5278, 9874, 5102, 51285, 51287,
  1676, 1674, 1680, 1668, 6192, 1644, 5277, 5280, 7043, 7034,
  39936, 39934, 8352, 42744, 23876, 1665, 1666, 9565, 5734, 1678,
  39351, 17570, 17561, 11714, 5289, 11246
}
DEFAULT_DOOR_ID_SET = {}
for _, _id in ipairs(DEFAULT_DOOR_IDS) do DEFAULT_DOOR_ID_SET[_id] = true end

DEFAULT_QUIVER_AMMO_IDS = {
  3446, 16142, 6528, 7363, 3450, 16141, 25785, 14252, 3447, 3449, 15793,
  25757, 774, 16143, 763, 761, 7365, 3448, 762, 21470, 7364, 14251,
  7368, 25759, 3287, 7366, 3298, 25758
}
DEFAULT_QUIVER_AMMO_SET = {}
for _, _id in ipairs(DEFAULT_QUIVER_AMMO_IDS) do DEFAULT_QUIVER_AMMO_SET[_id] = true end

DEFAULT_BP_CONTAINER_IDS = {
  9605, 2854, 3253, 2853, 5949, 5950, 2869, 2861, 8860, 8861, 2872, 2864,
  9601, 10326, 10324, 10325, 7342, 7343, 2863, 2865, 2857, 2870, 2862, 10202,
  5801, 10327, 9604, 3244, 9602, 9603, 5927, 2868, 2860, 2867, 2859, 10346,
  2866, 2858
}
DEFAULT_BP_CONTAINER_SET = {}
for _, _id in ipairs(DEFAULT_BP_CONTAINER_IDS) do DEFAULT_BP_CONTAINER_SET[_id] = true end

OBERON_EXACT_RESPONSES = {
  ["the world will suffer for its iddle laziness!"] = "Are you ever going to fight or do you prefer talking!",
  ["you appear like a worm among men!"] = "How appropriate, you look like something worms already got the better of!",
  ["people fall at my feet when they see me coming!"] = "Even before they smell your breath?",
  ["this will be the end of mortal man!"] = "Then let me show you the concept of mortality before it!",
  ["i will remove you from this plane of existence!"] = "Too bad you barely exist at all!",
  ["dragons will soon rule this world, i am their herald!"] = "Excuse me but I still do not get the message!",
  ["the true virtue of chivalry are my belief!"] = "Dare strike up a Minnesang and you will receive your last accolade!",
  ["i lead the most honourable and formidable following of knights!"] = "Then why are we fighting alone right now?",
  ["ultah salid'ar, esdo lo!"] = "SEHWO ASIMO, TOLIDO ESD!"
}

quiverRefillingActive = false
lastQuiverTime = 0
lastOberonTime = 0
lastAntiTrapTime = 0
lastAutoUtamoTime = 0
lastEquipDefenseTime = 0
antiLagShieldActive = false
