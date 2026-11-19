-- Follow engine and safe pathfinding

function applyFollowTargetSelection(targetName, autoEnable)
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

function onHelperFollowCreatureChange(creature)
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

function getTileHasAnyId(tile, idSet)
  if not tile or not idSet then return nil end
  for _, item in ipairs(tile:getItems() or {}) do
    if idSet[item:getId()] then return item end
  end
  local g = tile:getGround()
  if g and idSet[g:getId()] then return g end
  return nil
end

function isAvoidTile(pos, avoidSet)
  local tile = g_map.getTile(pos)
  return getTileHasAnyId(tile, avoidSet) ~= nil
end

function isFollowTerrainWalkable(pos)
  local tile = g_map.getTile(pos)
  if not tile then return false end
  if not tile:isWalkable(false) then return false end
  return true
end

function hasBlockingMonsterAt(pos, pPos)
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

function isFollowTileWalkableSafe(pos, pPos, avoidSet)
  if not isFollowTerrainWalkable(pos) then return false end
  if isAvoidTile(pos, avoidSet) then return false end
  if hasBlockingMonsterAt(pos, pPos) then return false end
  return true
end

function findFollowNearestSafeTile(dest, pPos, avoidSet, skipPos)
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

function getFollowBestLevitateDir(pPos, preferredDir)
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

function hasFollowLocalBypass(blockPos, prevPos, nextPos, pPos, avoidSet)
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

function getFollowTrailSafeDest(dest, pPos, avoidSet)
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

DIR_DELTAS = {
  [North]     = { 0, -1 },
  [NorthEast] = { 1, -1 },
  [East]      = { 1, 0 },
  [SouthEast] = { 1, 1 },
  [South]     = { 0, 1 },
  [SouthWest] = { -1, 1 },
  [West]      = { -1, 0 },
  [NorthWest] = { -1, -1 }
}

function findSafeFollowStepAvoiding(pPos, dest, avoidSet, allowGoalPos)
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

local function getDoorThingAtPos(pos)
  local tile = g_map.getTile(pos)
  if not tile then return nil end
  if tile.getTopUseThing then
    local topUse = tile:getTopUseThing()
    if topUse and topUse.getId and DEFAULT_DOOR_ID_SET and DEFAULT_DOOR_ID_SET[topUse:getId()] then
      return topUse
    end
  end
  for _, it in ipairs(tile:getItems() or {}) do
    if it and it.getId and DEFAULT_DOOR_ID_SET and DEFAULT_DOOR_ID_SET[it:getId()] then
      return it
    end
  end
  return nil
end

function tryOpenFollowDoor(pPos, dest, now)
  if not (charConfig and charConfig.tools and charConfig.tools.follow and charConfig.tools.follow.openDoors ~= false) then
    return false
  end
  if (now - (followLastDoorUseTime or 0)) < 250 then return false end
  if not pPos or not dest then return false end

  local dx = (dest.x > pPos.x) and 1 or (dest.x < pPos.x and -1 or 0)
  local dy = (dest.y > pPos.y) and 1 or (dest.y < pPos.y and -1 or 0)
  if dx ~= 0 or dy ~= 0 then
    local frontDoor = getDoorThingAtPos({ x = pPos.x + dx, y = pPos.y + dy, z = pPos.z })
    if frontDoor then
      g_game.use(frontDoor)
      followLastDoorUseTime = now
      return true
    end
  end

  local bestDoor, bestDist = nil, 999
  for ox = -1, 1 do
    for oy = -1, 1 do
      if ox ~= 0 or oy ~= 0 then
        local cand = { x = pPos.x + ox, y = pPos.y + oy, z = pPos.z }
        local door = getDoorThingAtPos(cand)
        if door then
          local d = math.abs(cand.x - dest.x) + math.abs(cand.y - dest.y)
          if d < bestDist then
            bestDist = d
            bestDoor = door
          end
        end
      end
    end
  end
  if bestDoor then
    g_game.use(bestDoor)
    followLastDoorUseTime = now
    return true
  end
  return false
end

function walkSafeTo(player, pPos, dest, avoidSet, allowGoalPos)
  if getDistanceBetween(pPos, dest) == 1 then
    local canStep = (allowGoalPos and isFollowTerrainWalkable(dest)) or isFollowTileWalkableSafe(dest, pPos, avoidSet)
    if canStep then
      local dir = getDirectionFromPos(pPos, dest)
      if dir then
        if player.preWalk and player:canWalk() and g_game.getFeature and g_game.getFeature(GameAllowPreWalk) then
          pcall(function() player:preWalk(dir) end)
        end
        g_game.walk(dir)
        return true
      end
    end
  end
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

function runFollowEngine(player, pPos, now)
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

  if (now - lastFollowTime) < 50 then return end

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
      if dist == wantDist and not isAvoidTile(pPos, avoidSet) then
        dest = { x = pPos.x, y = pPos.y, z = pPos.z }
      else
        local bestCand, bestScore = nil, 999999
        for ox = -wantDist, wantDist do
          for oy = -wantDist, wantDist do
            if math.max(math.abs(ox), math.abs(oy)) == wantDist then
              local cand = { x = tPos.x + ox, y = tPos.y + oy, z = pPos.z }
              if isFollowTileWalkableSafe(cand, pPos, avoidSet) then
                local dMe = math.max(math.abs(cand.x - pPos.x), math.abs(cand.y - pPos.y))
                local manMe = math.abs(cand.x - pPos.x) + math.abs(cand.y - pPos.y)
                local sc = (dMe * 100) + manMe
                if sc < bestScore then
                  bestScore = sc
                  bestCand = cand
                end
              end
            end
          end
        end
        if bestCand then
          dest = bestCand
        else
          local dx, dy = pPos.x - tPos.x, pPos.y - tPos.y
          local destX = (dx > wantDist and (tPos.x + wantDist)) or (dx < -wantDist and (tPos.x - wantDist)) or pPos.x
          local destY = (dy > wantDist and (tPos.y + wantDist)) or (dy < -wantDist and (tPos.y - wantDist)) or pPos.y
          dest = { x = destX, y = destY, z = pPos.z }
        end
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
              if distAfter < distBefore and (now - followLastDoorUseTime) > 350 then
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
      local retryDelay = (player:isAutoWalking() and 350) or (isTargetMoving and 120 or 200)
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
    local dirV = DIR_DELTAS[lastFollowTargetDir] or { 0, 0 }
    local vx = (lastFollowTrailVec.x ~= 0 or lastFollowTrailVec.y ~= 0) and lastFollowTrailVec.x or dirV[1]
    local vy = (lastFollowTrailVec.x ~= 0 or lastFollowTrailVec.y ~= 0) and lastFollowTrailVec.y or dirV[2]
    local maxR = followVanishedAtEdge and 1 or 2
    local bestScore = 999999
    for r = 0, maxR do
      for ox = -r, r do
        for oy = -r, r do
          if math.max(math.abs(ox), math.abs(oy)) == r then
            local cp = { x = lastFollowTargetPos.x + ox, y = lastFollowTargetPos.y + oy, z = pPos.z }
            local tile = g_map.getTile(cp)
            if tile then
              local candKind, candThing = nil, nil
              local it = getTileHasAnyId(tile, stairsSet) or getTileHasAnyId(tile, tpSet)
              if it then
                candKind, candThing = 'step', it
              else
                it = getTileHasAnyId(tile, useSet)
                if it then
                  candKind, candThing = 'use', it
                else
                  it = getTileHasAnyId(tile, ropeSet)
                  if it then candKind, candThing = 'rope', it end
                end
              end
              if candKind then
                local score = r * 20
                if r == 0 then
                  score = -100
                elseif ox == vx and oy == vy and (vx ~= 0 or vy ~= 0) then
                  score = -50
                elseif (vx ~= 0 or vy ~= 0) then
                  score = score - ((ox * vx + oy * vy) * 8)
                end
                score = score + math.max(math.abs(cp.x - pPos.x), math.abs(cp.y - pPos.y))
                if score < bestScore then
                  bestScore = score
                  actionPos, actionKind, actionThing = cp, candKind, candThing
                end
              end
            end
          end
        end
      end
      if actionPos and r <= 1 then break end
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
          tryOpenFollowDoor(pPos, safeDest, now)
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

