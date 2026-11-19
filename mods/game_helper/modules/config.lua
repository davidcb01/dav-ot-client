-- Profile defaults, schema normalization, persistence, and export/import

-- DEFAULTS & SCHEMA NORMALIZATION (Prevents nil crashes from legacy configs)
-- ============================================================================

function createDefaultSioSection(isActive, defaultWords)
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

function createDefaultVocProfile(voc)
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
            { type = 'S', words = 'exori gran', name = 'Fierce Berserk', clientId = 105, countVal = 2, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = { momentum = true } },
            { type = 'S', words = 'exori min', name = 'Front Sweep', clientId = 59, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = true, enabled = true, cond = { faceTarget = true } },
            { type = 'S', words = 'exori mas', name = 'Groundshaker', clientId = 106, countVal = 3, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 10, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = {} },
            { type = 'S', words = 'exori', name = 'Berserk', clientId = 80, countVal = 1, countOp = '>=', hpMin = 0, hpMax = 100, mpPct = 5, delay = 0, priority = 'All Monsters', targetName = '', requiresTarget = false, enabled = true, cond = {} },
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

function normalizeShooterRule(r)
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

function normalizeVocProfile(vp, voc)
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
  h.manaShield.belowHp = math.max(1, math.min(100, tonumber(h.manaShield.belowHp) or 100))
  h.manaShield.aboveHp = math.max(1, math.min(100, tonumber(h.manaShield.aboveHp) or 70))
  h.manaShield.removeOnRecovery = (h.manaShield.removeOnRecovery == true)
  h.manaShield.antiLag = (h.manaShield.antiLag == true)
  h.manaShield.antiLagPing = math.max(50, math.min(2000, tonumber(h.manaShield.antiLagPing) or 200))

  h.defEquip = type(h.defEquip) == 'table' and h.defEquip or {}
  h.defEquip.ssaEnabled = (h.defEquip.ssaEnabled == true)
  h.defEquip.ssaHp = math.max(1, math.min(100, tonumber(h.defEquip.ssaHp) or 60))
  h.defEquip.mightEnabled = (h.defEquip.mightEnabled == true)
  h.defEquip.mightHp = math.max(1, math.min(100, tonumber(h.defEquip.mightHp) or 60))
  h.defEquip.eringEnabled = (h.defEquip.eringEnabled == true)
  h.defEquip.eringHp = math.max(1, math.min(100, tonumber(h.defEquip.eringHp) or 45))
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
  s.pvpSafe = (s.pvpSafe == true)
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
  tg.mode = 'A'
  tg.maxRange = math.max(1, math.min(11, tonumber(tg.maxRange) or 7))
  tg.chase = (tg.chase == true)
  tg.chaseMode = tg.chase and 'Chase' or 'Stand'
  if tg.keepTarget == nil then tg.keepTarget = true end
  tg.finisher = type(tg.finisher) == 'table' and tg.finisher or {}
  tg.finisher.enabled = (tg.finisher.enabled == true)
  if type(tg.finisher.mode) ~= 'string' or not tg.finisher.mode:match('^[A-I]$') then
    tg.finisher.mode = 'A'
  end
  if tg.finisher.chaseMode ~= 'Chase' and tg.finisher.chaseMode ~= 'Stand' and tg.finisher.chaseMode ~= 'Keep' then
    tg.finisher.chaseMode = 'Chase'
  end
  if tg.finisher._init == nil then
    tg.finisher._init = true
    if type(tg.finisher.rules) ~= 'table' or #coerceArray(tg.finisher.rules) == 0 then
      tg.finisher.rules = {
        { name = 'Hand of Cursed Fate', hp = 50, enabled = true },
        { name = 'Blightwalker', hp = 30, enabled = true },
        { name = 'Spectre', hp = 30, enabled = true },
        { name = 'Ironblight', hp = 30, enabled = true },
        { name = 'Dark Torturer', hp = 30, enabled = true }
      }
    end
  end
  local coercedFin = coerceArray(tg.finisher.rules)
  local normFin = {}
  for _, fr in ipairs(coercedFin) do
    if type(fr) == 'table' then
      local nm = tostring(fr.name or ''):gsub('^%s+', ''):gsub('%s+$', '')
      if nm ~= '' then
        table.insert(normFin, {
          name = nm,
          hp = math.max(1, math.min(100, tonumber(fr.hp) or 30)),
          enabled = (fr.enabled ~= false)
        })
      end
    end
  end
  tg.finisher.rules = normFin
  tg.holdTarget = (tg.holdTarget == true)
  if tg.ignoreList == nil then tg.ignoreList = s.ignoreList or '' end
  tg.priorityList = nil
  tg.lowHpRules = nil
  local coercedTgtRules = coerceArray(tg.rules)
  if #coercedTgtRules == 0 then
    tg.rules = { { name = '', allMonsters = true, mode = 'A', hpMin = 0, hpMax = 100, interrupt = false, enabled = true } }
  else
    for _, tr in ipairs(coercedTgtRules) do
      if type(tr) == 'table' then
        tr.name = tr.name or ''
        if tr.allMonsters == nil then
          tr.allMonsters = (tr.name == '')
        end
        if type(tr.mode) ~= 'string' or not tr.mode:match('^[A-I]$') then
          tr.mode = 'A'
        end
        tr.hpMin = tonumber(tr.hpMin) or 0
        tr.hpMax = tonumber(tr.hpMax) or 100
        tr.interrupt = (tr.interrupt == true)
        if tr.enabled == nil then tr.enabled = true end
      end
    end
    tg.rules = coercedTgtRules
  end
  vp._normalized = true
  return vp
end

function createDefaultCharConfig()
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
      manaTrain = { words = 'exura ico', name = 'Wound Cleansing', clientId = 123, enabled = false, pct = 85, sec = 2, pzCast = true },
      haste = { words = 'utani hur', name = 'Haste', clientId = 100, enabled = false, pzCast = true },
      exercise = { enabled = false, weaponId = 0, dummyId = 0 },
      changeGold = false,
      autoEat = false,
      autoBless = false,
      antiAfk = false,
      autoAol = false,
      autoQuiver = false,
      keepBpOpen = false,
      nextBpFull = false,
      autoParty = false,
      autoOberon = false,
      follow = { enabled = false, name = '', mode = 'Default', dist = 1, turn = false, openDoors = true },
      itemTimer = { enabled = false, itemId = 3725, sec = 610 }
    },
    cavebot = {
      enabled = false,
      ropeId = 3003,
      shovelId = 5710,
      startNearest = true,
      showWaypoints = true,
      showWaypointsFloor = true,
      ignoreUnreachable = true,
      antiTrap = false,
      wpMode = 'Add',
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

function normalizeCharConfig(cfg)
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
      sec = tonumber(legacy.sec) or 2,
      pzCast = (legacy.pzCast ~= false)
    }
  elseif type(t.manaTrain) ~= 'table' or t.manaTrain.words == nil then
    t.manaTrain = deepCopy(def.tools.manaTrain)
  else
    t.manaTrain.pct = tonumber(t.manaTrain.pct) or 85
    t.manaTrain.sec = math.max(1, math.min(3600, tonumber(t.manaTrain.sec) or 2))
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
  if t.follow.openDoors == nil then t.follow.openDoors = true end
  t.itemTimer = type(t.itemTimer) == 'table' and t.itemTimer or deepCopy(def.tools.itemTimer)
  t.itemTimer.enabled = (t.itemTimer.enabled == true)
  t.itemTimer.itemId = tonumber(t.itemTimer.itemId) or 0
  t.itemTimer.sec = math.max(1, tonumber(t.itemTimer.sec) or 610)
  t.changeGold = (t.changeGold == true)
  t.autoEat = (t.autoEat == true)
  t.autoBless = (t.autoBless == true)
  t.antiAfk = (t.antiAfk == true)
  t.autoAol = (t.autoAol == true)
  t.autoQuiver = (t.autoQuiver == true)
  t.keepBpOpen = (t.keepBpOpen == true)
  t.nextBpFull = (t.nextBpFull == true)
  t.autoParty = (t.autoParty == true)
  t.autoOberon = (t.autoOberon == true)

  -- Cavebot normalization
  cfg.cavebot = type(cfg.cavebot) == 'table' and cfg.cavebot or deepCopy(def.cavebot)
  local cb = cfg.cavebot
  cb.enabled = (cb.enabled == true)
  cb.ropeId = tonumber(cb.ropeId) or 3003
  cb.shovelId = tonumber(cb.shovelId) or 5710
  if cb.startNearest == nil then cb.startNearest = true end
  if cb.showWaypoints == nil then cb.showWaypoints = true end
  if cb.showWaypointsFloor == nil then cb.showWaypointsFloor = true end
  if cb.ignoreUnreachable == nil then cb.ignoreUnreachable = true end
  cb.antiTrap = (cb.antiTrap == true)
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
  do
    local avoidArr = cfg.customIds.follow.avoid
    local avoidSeen = {}
    for _, v in ipairs(avoidArr) do avoidSeen[v] = true end
    for _, srcCat in ipairs({ 'stairs', 'teleport' }) do
      for _, v in ipairs(cfg.customIds.follow[srcCat] or {}) do
        if not avoidSeen[v] then
          avoidSeen[v] = true
          table.insert(avoidArr, v)
        end
      end
    end
  end
  cfg.customIds.dummys = type(cfg.customIds.dummys) == 'table' and cfg.customIds.dummys or {}
  cfg.customIds.weapons = type(cfg.customIds.weapons) == 'table' and cfg.customIds.weapons or {}

  cfg.vocProfiles = type(cfg.vocProfiles) == 'table' and cfg.vocProfiles or {}
  return cfg
end

charConfig = normalizeCharConfig(createDefaultCharConfig())

function getVocProfile(voc)
  voc = voc or currentVocName or detectPlayerVocation()
  if not charConfig.vocProfiles[voc] then
    charConfig.vocProfiles[voc] = normalizeVocProfile(createDefaultVocProfile(voc), voc)
  elseif not charConfig.vocProfiles[voc]._normalized then
    charConfig.vocProfiles[voc] = normalizeVocProfile(charConfig.vocProfiles[voc], voc)
  end
  return charConfig.vocProfiles[voc]
end

-- ============================================================================
-- PERSISTENCE & LIVE SYNC
-- ============================================================================

function getProfileStorageKey()
  if currentCharName and #currentCharName > 0 then
    return currentCharName
  end
  local p = g_game.getLocalPlayer()
  if p and p:getName() and #p:getName() > 0 then
    return p:getName()
  end
  return 'Default'
end

function parseNum(editWidget, defaultVal, minV, maxV)
  if not editWidget then return defaultVal end
  local v = tonumber(editWidget:getText())
  if not v then return defaultVal end
  if minV and v < minV then v = minV end
  if maxV and v > maxV then v = maxV end
  return math.floor(v)
end

DAVHELPER_NS = 'davhelper'
DAVHELPER_LEGACY_NODE = 'DAVHelperCharConfigs'

function loadHelperStoredProfile(key)
  if CharConfig then
    return CharConfig.load(DAVHELPER_NS, key, DAVHELPER_LEGACY_NODE, true)
  end
  local all = g_settings.getNode(DAVHELPER_LEGACY_NODE) or {}
  return all[key]
end

function saveHelperStoredProfile(key, cfg)
  if CharConfig then
    return CharConfig.set(DAVHELPER_NS, key, cfg, true)
  end
  local all = g_settings.getNode(DAVHELPER_LEGACY_NODE) or {}
  all[key] = cfg
  g_settings.setNode(DAVHELPER_LEGACY_NODE, all)
  g_settings.save()
  return true
end

function deleteHelperStoredProfile(key)
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

function getAllHelperProfiles()
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

