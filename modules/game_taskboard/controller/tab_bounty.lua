-- Bounty tab logic — methods added to TaskBoardController
local function formatPercent(value)
    if value * 10 == math.floor(value * 10) then
        return string.format('%.1f', value)
    else
        return string.format('%.2f', value)
    end
end

local function inferTalismanLevel(index, currentRaw)
    local raw = tonumber(currentRaw) or 0
    if raw <= 0 then
        return 0
    end
    if index == 4 then
        -- Native wire formula for slot 4: (5+L)*100 for L<=15, (20+(L-15)*0.5)*100 for L<=55, (40+(L-55)*0.2)*100 above
        if raw <= 2000 then
            return math.max(0, math.floor(((raw / 100) - 5) + 0.5))
        elseif raw <= 4000 then
            return math.max(15, math.floor(15 + (((raw / 100) - 20) / 0.5) + 0.5))
        else
            return math.max(55, math.floor(55 + (((raw / 100) - 40) / 0.2) + 0.5))
        end
    else
        -- Native wire formula for slots 1..3: (2.5+L*0.5)*100 for L<=15, (10+(L-15)*0.25)*100 for L<=55, (20+(L-55)*0.1)*100 above
        if raw <= 1000 then
            return math.max(0, math.floor(((raw / 100) - 2.5) / 0.5 + 0.5))
        elseif raw <= 2000 then
            return math.max(15, math.floor(15 + (((raw / 100) - 10) / 0.25) + 0.5))
        else
            return math.max(55, math.floor(55 + (((raw / 100) - 20) / 0.1) + 0.5))
        end
    end
end

local TALISMAN_MAX_LEVEL = 40

local function normalizeTalismanValues(index, currentRaw, nextRaw)
    local level = math.min(TALISMAN_MAX_LEVEL, inferTalismanLevel(index, currentRaw))
    local currentPct = math.min(25.0, 5.0 + (level * 0.5))
    local nextPct = (level >= TALISMAN_MAX_LEVEL) and 0 or math.min(25.0, 5.0 + ((level + 1) * 0.5))
    return currentPct, nextPct, level
end

--  Server data handler 

function TaskBoardController:onBountyServerData(header, monsters, talisman)
    local rerollPoints = tonumber(header.rerollPoints) or 0
    local claimDaily = tonumber(header.claimDaily) or 0
    local difficulty = tonumber(header.difficulty) or 1

    self.claimDailyServerAvailable = claimDaily == 1
    self.rerollPoints = rerollPoints
    self.claimDailyAvailable = self.claimDailyServerAvailable and rerollPoints < REROLL_TOKEN_CAP
    self.claimDailyWarning = (rerollPoints >= REROLL_TOKEN_CAP)
    self.bountyDifficulty = difficulty

    -- Build bountyTasks table for *for loop in HTML
    local tasks = {}

    for _, m in ipairs(monsters) do
        local raceId = tonumber(m.raceId) or 0
        local currentKills = tonumber(m.currentKills) or 0
        local totalKills = tonumber(m.totalKills) or 0
        local rarity = tonumber(m.rarity) or 0
        local isActive = tonumber(m.isActive) == 1
        local isCompleted = tonumber(m.isCompleted) == 1
        local raceData = raceId > 0 and g_things.getRaceData(raceId) or nil
        local name = raceData and raceData.name or 'Unknown'
        name = name:capitalize()
        if #name > 20 then
            name = name:sub(1, 20) .. '...'
        end

        table.insert(tasks, {
            taskIndex = tonumber(m.taskIndex) or 0,
            raceId = raceId,
            name = name,
            outfit = raceData and raceData.outfit or nil,
            current = currentKills,
            total = totalKills,
            rarity = rarity,
            backdrop = RARITY_BACKDROPS[rarity] or RARITY_BACKDROPS[0],
            xp = comma_value(tonumber(m.rewardXp) or 0),
            points = tostring(tonumber(m.rewardPoints) or 0),
            reroll = tostring(tonumber(m.rewardReroll) or 0),
            isActive = isActive,
            isCompleted = isCompleted,
            canClaim = (not isCompleted) and isActive and currentKills >= totalKills
        })
    end

    self.bountyTasks = tasks
    self:syncBountyDifficultySelect()

    -- Build talismans table for *for loop
    local tals = {}
    for i = 1, 4 do
        local s = type(talisman) == 'table' and talisman[i] or nil
        if s then
            local currentValue, nextValue, level = normalizeTalismanValues(i, s.currentValue, s.nextValue)
            local upgradeCost = tonumber(s.upgradeCost) or 0
            local rawNextValue = tonumber(s.nextValue) or 0
            local isMaxed = (level >= TALISMAN_MAX_LEVEL) or (rawNextValue == 0 and upgradeCost == 0)
            table.insert(tals, {
                icon = TALISMAN_ICONS[i],
                title = TALISMAN_TITLES[i],
                current = string.format('Current: %s%%', formatPercent(currentValue)),
                buttonText = isMaxed and 'MAX' or string.format('Upgrade to %s%%', formatPercent(nextValue)),
                cost = isMaxed and '-' or tostring(upgradeCost),
                statType = i - 1,
                isMaxed = isMaxed,
                upgradeable = not isMaxed,
                showSeparator = i > 1
            })
        end
    end
    self.talismans = tals

    -- Update kill tracker
    self:updateBountyTracker(monsters)
end

--  Kill update 

function TaskBoardController:onBountyKillUpdate(raceId, currentKills, totalKills, isCompleted)
    -- Update tracker
    self:onBountyTrackerKillUpdate(raceId, currentKills, totalKills, isCompleted)

    -- Update the active task entry in bountyTasks if window is open
    for i, task in ipairs(self.bountyTasks) do
        if task.raceId == raceId then
            self.bountyTasks[i].current = currentKills
            self.bountyTasks[i].total = totalKills
            self.bountyTasks[i].isCompleted = currentKills >= totalKills
            self.bountyTasks[i].canClaim = (not self.bountyTasks[i].isCompleted) and task.isActive and currentKills >=
                                               totalKills
            -- Trigger reactive update by reassigning the table
            self.bountyTasks = self.bountyTasks
            break
        end
    end
end

--  Actions 

function TaskBoardController:rerollMonsters()
    if self.rerollPoints <= 0 then
        return
    end
    local msgBox
    local function yes()
        if msgBox then
            msgBox:destroy();
            msgBox = nil
        end
        g_game.bountyTaskAction(BOUNTY_ACTION_REROLL, 0)
    end
    local function cancel()
        if msgBox then
            msgBox:destroy();
            msgBox = nil
        end
    end
    msgBox = displayGeneralBox(tr('Reroll Tasks'),
        tr('Do you want to reroll your bounty tasks? This will consume 1 reroll token.'), {{
            text = tr('Yes'),
            callback = yes
        }, {
            text = tr('Cancel'),
            callback = cancel
        }}, yes, cancel)
end

function TaskBoardController:selectTask(taskIndex)
    local parsedTaskIndex = tonumber(taskIndex) or 0
    g_game.bountyTaskAction(BOUNTY_ACTION_SELECT, parsedTaskIndex)
end

function TaskBoardController:claimReward()
    local msgBox
    local function yes()
        if msgBox then
            msgBox:destroy();
            msgBox = nil
        end
        g_game.bountyTaskAction(BOUNTY_ACTION_CLAIM_REWARD, 0)
    end
    local function cancel()
        if msgBox then
            msgBox:destroy();
            msgBox = nil
        end
    end
    msgBox = displayGeneralBox(tr('Claim Reward'), tr('Claim reward for completing the bounty task?'), {{
        text = tr('Yes'),
        callback = yes
    }, {
        text = tr('Cancel'),
        callback = cancel
    }}, yes, cancel)
end

function TaskBoardController:changeDifficulty(event)
    -- event.data = selected option data (difficulty id set when populating the combobox)
    local diffId = event and (tonumber(event.data) or tonumber(event.value)) or nil
    if not diffId then
        return
    end
    g_game.bountyTaskAction(BOUNTY_ACTION_CHANGE_DIFFICULTY, diffId)
end

function TaskBoardController:claimDaily()
    if self.claimDailyWarning then
        local msgBox
        local function yes()
            if msgBox then
                msgBox:destroy();
                msgBox = nil
            end
            g_game.bountyTaskAction(BOUNTY_ACTION_CLAIM_DAILY, 0)
        end
        local function cancel()
            if msgBox then
                msgBox:destroy();
                msgBox = nil
            end
        end
        msgBox = displayGeneralBox(tr('Reroll Token Cap'), tr(
            'You already have 10 reroll tokens. Claiming another will discard the oldest. Continue?'), {{
            text = tr('Yes'),
            callback = yes
        }, {
            text = tr('Cancel'),
            callback = cancel
        }}, yes, cancel)
    else
        g_game.bountyTaskAction(BOUNTY_ACTION_CLAIM_DAILY, 0)
    end
end

function TaskBoardController:upgradeTalisman(statType)
    g_game.bountyTalismanUpgrade(statType)
end

--  Tracker helpers 

function TaskBoardController:updateBountyTracker(monsters)
    if not Tracker or not Tracker.Bounty then
        return
    end
    local activeMonster = nil
    for _, m in ipairs(monsters) do
        if tonumber(m.isActive) == 1 then
            activeMonster = m
            break
        end
    end
    if not activeMonster then
        Tracker.Bounty.setInactive()
        return
    end
    local raceId = tonumber(activeMonster.raceId) or 0
    local currentKills = tonumber(activeMonster.currentKills) or 0
    local totalKills = tonumber(activeMonster.totalKills) or 0
    local isCompleted = currentKills >= totalKills and 1 or 0
    self:onBountyTrackerKillUpdate(raceId, currentKills, totalKills, isCompleted)
end

function TaskBoardController:onBountyTrackerKillUpdate(raceId, currentKills, totalKills, isCompleted)
    if not Tracker or not Tracker.Bounty then
        return
    end
    Tracker.Bounty.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
end
