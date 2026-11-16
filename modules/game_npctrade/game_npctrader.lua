controllerNpcTrader = Controller:new()
controllerNpcTrader.widthConsole = controllerNpcTrader.DEFAULT_CONSOLE_WIDTH
controllerNpcTrader.creatureName = ""
controllerNpcTrader.outfit = nil
controllerNpcTrader.buttons = {}
controllerNpcTrader.isTradeOpen = false
controllerNpcTrader.legacyMode = false
controllerNpcTrader.npcTalkConnected = false

function controllerNpcTrader:isLegacyMode()
    return self.legacyMode
end

function controllerNpcTrader:onInit()
    self:loadQuickSellBlacklist()
end

function controllerNpcTrader:normalizeBlacklistId(itemId)
    local num = tonumber(itemId)
    if not num or num <= 0 then
        return nil
    end
    return tostring(math.floor(num))
end

function controllerNpcTrader:loadQuickSellBlacklist()
    local saved = g_settings.getNode(controllerNpcTrader.QUICK_SELL_BLACKLIST_SETTING) or {}
    local normalized = {}
    for k, v in pairs(saved) do
        if v then
            local key = self:normalizeBlacklistId(k)
            if key then
                normalized[key] = true
            end
        end
    end
    self.quickSellBlacklist = normalized
end

function controllerNpcTrader:saveQuickSellBlacklist()
    g_settings.setNode(controllerNpcTrader.QUICK_SELL_BLACKLIST_SETTING, self.quickSellBlacklist or {})
    g_settings.save()
end

function controllerNpcTrader:isQuickSellBlacklisted(itemId)
    if not self.quickSellBlacklist then
        self:loadQuickSellBlacklist()
    end
    local key = self:normalizeBlacklistId(itemId)
    return key ~= nil and self.quickSellBlacklist[key] == true
end

function controllerNpcTrader:addToQuickSellBlacklist(itemId)
    local key = self:normalizeBlacklistId(itemId)
    if not key then
        return false
    end
    if not self.quickSellBlacklist then
        self:loadQuickSellBlacklist()
    end
    if self.quickSellBlacklist[key] then
        return false
    end
    self.quickSellBlacklist[key] = true
    self:saveQuickSellBlacklist()
    self:onQuickSellBlacklistChanged()
    return true
end

function controllerNpcTrader:removeFromQuickSellBlacklist(itemId)
    local key = self:normalizeBlacklistId(itemId)
    if not key or not self.quickSellBlacklist or not self.quickSellBlacklist[key] then
        return false
    end
    self.quickSellBlacklist[key] = nil
    self:saveQuickSellBlacklist()
    self:onQuickSellBlacklistChanged()
    return true
end

function controllerNpcTrader:toggleQuickSellBlacklist(itemId)
    if self:isQuickSellBlacklisted(itemId) then
        self:removeFromQuickSellBlacklist(itemId)
        return false
    end
    self:addToQuickSellBlacklist(itemId)
    return true
end

function controllerNpcTrader:clearQuickSellBlacklist()
    self.quickSellBlacklist = {}
    self:saveQuickSellBlacklist()
    self:onQuickSellBlacklistChanged()
end

function controllerNpcTrader:getQuickSellBlacklistCount()
    local count = 0
    for _, v in pairs(self.quickSellBlacklist or {}) do
        if v then
            count = count + 1
        end
    end
    return count
end

function controllerNpcTrader:onQuickSellBlacklistChanged()
    if self:isLegacyMode() then
        if refreshTradeItems then
            refreshTradeItems()
        end
        if refreshPlayerGoods then
            refreshPlayerGoods()
        end
    elseif self.isTradeOpen then
        self:onTradeListRendered()
        self:updateSellAllButton()
    end
end

function controllerNpcTrader:onGameStart()
    self.legacyMode = not g_game.getFeature(GameNpcWindowRedesign)
    if self:isLegacyMode() then
        self:legacy_init()
    end

    self:registerEvents(g_game, {
        onNpcChatWindow = function(data)
            onNpcChatWindow(data)
        end,
        onOpenNpcTrade = function(...)
            self:startEquippedImbuementsTracking()
            if self:isLegacyMode() then
                onOpenNpcTrade(...)
            else
                self:onOpenNpcTrade(...)
            end
        end,
        onPlayerGoods = function(money, items)
            if self:isLegacyMode() then
                onPlayerGoods(money, items)
            else
                self:onPlayerGoods(money, items)
            end
        end,
        onUpdateImbuementTracker = function(items)
            self:onUpdateEquippedImbuements(items)
        end,
        onNpcChatWindowClose = function()
            self:stopEquippedImbuementsTracking()
            if self:isLegacyMode() then
                self:legacy_hide()
            else
                self:onCloseNpcDialog()
            end
        end,
        onCloseNpcTrade = function()
            self:stopEquippedImbuementsTracking()
            if self:isLegacyMode() then
                self:legacy_hide()
            else
                self:onCloseNpcTrade()
            end
        end
    })
end

function controllerNpcTrader:connectNpcTalkEvent()
    if self:isLegacyMode() or self.npcTalkConnected then
        return
    end

    connect(g_game, {
        onTalk = onNpcTalk
    })
    self.npcTalkConnected = true
end

function controllerNpcTrader:disconnectNpcTalkEvent()
    if not self.npcTalkConnected then
        return
    end

    disconnect(g_game, {
        onTalk = onNpcTalk
    })
    self.npcTalkConnected = false
end

function controllerNpcTrader:onTerminate()
    if self:isLegacyMode() then
        self:legacy_terminate()
    else
        self:onCloseNpcDialog()
    end
end

function controllerNpcTrader:onGameEnd()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:onCloseNpcDialog()
    end
end

function controllerNpcTrader:clearTradeState()
    self.isTradeOpen = false
    self.hasSellItems = false
    self.isSellingAll = false
    self.widthConsole = self.DEFAULT_CONSOLE_WIDTH
    if self.sellAllWithDelayEvent then
        removeEvent(self.sellAllWithDelayEvent)
        self.sellAllWithDelayEvent = nil
    end
    self:closeQuickSellWindow()
    self.buyItems = {}
    self.sellItems = {}
    self.playerItems = {}
    self.playerMoney = nil
    self.selectedItem = nil
    self.tradeItems = {}
    self.currentList = {}
    self.allTradeItems = {}
end

function controllerNpcTrader:onCloseNpcTrade()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:clearTradeState()
    end
end

function controllerNpcTrader:onCloseNpcDialog()
    if self:isLegacyMode() then
        self:legacy_hide()
    else
        self:disconnectNpcTalkEvent()
        if self.isTradeOpen then
            g_game.closeNpcTrade()
        end
        if controllerNpcTrader.ui and controllerNpcTrader.ui:isVisible() then
            controllerNpcTrader:unloadHtml()
        end
        self:clearTradeState()
    end
end

function sellAll(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        sellAllLegacy(...)
    else
        controllerNpcTrader:sellAll(...)
    end
end

function isTrading(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return isTradingLegacy(...)
    end

    return controllerNpcTrader.isTradeOpen == true
end

function getSellItems(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getSellItemsLegacy(...)
    end

    return controllerNpcTrader.sellItems or {}
end

function getBuyItems(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getBuyItemsLegacy(...)
    end

    return controllerNpcTrader.buyItems or {}
end

function getSellQuantity(item) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return getSellQuantityLegacy(item)
    end

    if type(item) == 'number' then
        item = Item.create(item)
    end

    return controllerNpcTrader:getSellQuantity(item)
end

function canTradeItem(item) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return canTradeItemLegacy(item)
    end

    if type(item) == 'number' then
        item = Item.create(item)
    end

    local tradeEntry = item
    if item and not item.ptr then
        for _, entry in ipairs(controllerNpcTrader.sellItems or {}) do
            if entry.ptr:getId() == item:getId() and entry.ptr:getSubType() == item:getSubType() then
                tradeEntry = entry
                break
            end
        end

        if tradeEntry == item then
            for _, entry in ipairs(controllerNpcTrader.buyItems or {}) do
                if entry.ptr:getId() == item:getId() and entry.ptr:getSubType() == item:getSubType() then
                    tradeEntry = entry
                    break
                end
            end
        end
    end

    if not tradeEntry or not tradeEntry.ptr then
        return false
    end

    return controllerNpcTrader:canTradeItem(tradeEntry)
end

function closeNpcTrade(...) -- Vbot Call
    if controllerNpcTrader:isLegacyMode() then
        return closeNpcTradeLegacy(...)
    end

    return g_game.closeNpcTrade()
end

function addToBlacklist(itemId)
    return controllerNpcTrader:addToQuickSellBlacklist(itemId)
end

function addToWhitelist(itemId) -- game_cyclopedia Quick Sell Skip alias
    return controllerNpcTrader:addToQuickSellBlacklist(itemId)
end

function addToList(itemId)
    return controllerNpcTrader:addToQuickSellBlacklist(itemId)
end

function removeFromBlacklist(itemId)
    return controllerNpcTrader:removeFromQuickSellBlacklist(itemId)
end

function removeItemInList(itemId) -- game_cyclopedia Quick Sell Skip alias
    return controllerNpcTrader:removeFromQuickSellBlacklist(itemId)
end

function removeFromList(itemId)
    return controllerNpcTrader:removeFromQuickSellBlacklist(itemId)
end

function removeItem(itemId)
    return controllerNpcTrader:removeFromQuickSellBlacklist(itemId)
end

function isInBlacklist(itemId)
    return controllerNpcTrader:isQuickSellBlacklisted(itemId)
end

function inWhiteList(itemId) -- game_cyclopedia Quick Sell Skip alias
    return controllerNpcTrader:isQuickSellBlacklisted(itemId)
end

function isInList(itemId)
    return controllerNpcTrader:isQuickSellBlacklisted(itemId)
end

function contains(itemId)
    return controllerNpcTrader:isQuickSellBlacklisted(itemId)
end

function toggleBlacklist(itemId)
    return controllerNpcTrader:toggleQuickSellBlacklist(itemId)
end

function clearBlacklist()
    return controllerNpcTrader:clearQuickSellBlacklist()
end

function getBlacklist()
    if not controllerNpcTrader.quickSellBlacklist then
        controllerNpcTrader:loadQuickSellBlacklist()
    end
    return controllerNpcTrader.quickSellBlacklist or {}
end
