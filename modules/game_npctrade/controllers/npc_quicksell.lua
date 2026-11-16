local quickSellStyleLoaded = false

function controllerNpcTrader:ensureQuickSellStyle()
    if not quickSellStyleLoaded then
        g_ui.importStyle('/modules/game_npctrade/quick_sell')
        quickSellStyleLoaded = true
    end
end

function controllerNpcTrader:openQuickSellWindow()
    if not self.isTradeOpen then
        return
    end
    self:ensureQuickSellStyle()
    if not self.quickSellWindow or self.quickSellWindow:isDestroyed() then
        self.quickSellWindow = g_ui.createWidget('QuickSellWindow', rootWidget)
    end
    self.quickSellTab = self.quickSellTab or 'sell'
    self.selectedQuickSellEntry = nil
    self:updateQuickSellProgress(0, 0)
    self.quickSellWindow:show()
    self.quickSellWindow:raise()
    self.quickSellWindow:focus()
    self:refreshQuickSellWindow()
end

function controllerNpcTrader:closeQuickSellWindow()
    self.selectedQuickSellEntry = nil
    if self.quickSellWindow and not self.quickSellWindow:isDestroyed() then
        self.quickSellWindow:destroy()
    end
    self.quickSellWindow = nil
end

function controllerNpcTrader:setQuickSellTab(tabName)
    self.quickSellTab = (tabName == 'blacklist') and 'blacklist' or 'sell'
    self.selectedQuickSellEntry = nil
    self:refreshQuickSellWindow()
end

function controllerNpcTrader:updateQuickSellProgress(doneCount, totalCount)
    if not self.quickSellWindow or self.quickSellWindow:isDestroyed() then
        return
    end
    local bar = self.quickSellWindow:recursiveGetChildById('saleProgressBar')
    if not bar then
        return
    end
    if not totalCount or totalCount <= 0 then
        bar:setPercent(0)
        return
    end
    local pct = math.max(0, math.min(100, math.floor((doneCount / totalCount) * 100)))
    bar:setPercent(pct)
end

function controllerNpcTrader:getQuickSellEntries()
    local entries = {}
    local totalGold = 0
    for _, entry in ipairs(self.sellItems or {}) do
        if entry.ptr then
            local id = entry.ptr:getId()
            local qty = self:getSellQuantity(entry.ptr)
            if qty > 0 and not self:isQuickSellBlacklisted(id) then
                local price = tonumber(entry.price) or 0
                local value = qty * price
                totalGold = totalGold + value
                table.insert(entries, {
                    ptr = entry.ptr,
                    name = entry.name or string.format('Item #%d', id),
                    id = id,
                    qty = qty,
                    price = price,
                    value = value
                })
            end
        end
    end
    table.sort(entries, function(a, b)
        return a.value > b.value
    end)
    return entries, totalGold
end

function controllerNpcTrader:getQuickSellBlacklistEntries()
    local ids = {}
    for k, enabled in pairs(self.quickSellBlacklist or {}) do
        if enabled then
            local num = tonumber(k)
            if num and num > 0 then
                table.insert(ids, math.floor(num))
            end
        end
    end
    table.sort(ids)
    return ids
end

function controllerNpcTrader:refreshQuickSellWindow()
    local win = self.quickSellWindow
    if not win or win:isDestroyed() or not win:isVisible() then
        return
    end

    local tab = self.quickSellTab or 'sell'
    local sellTabBtn = win:recursiveGetChildById('sellAllTabBtn')
    local blTabBtn = win:recursiveGetChildById('blacklistTabBtn')
    local sectionHeader = win:recursiveGetChildById('sectionHeader')
    local saleProgressBar = win:recursiveGetChildById('saleProgressBar')
    local itemsGrid = win:recursiveGetChildById('itemsGrid')
    local saleValueLabel = win:recursiveGetChildById('saleValueLabel')
    local sellItemBtn = win:recursiveGetChildById('sellItemBtn')
    local executeSellAllBtn = win:recursiveGetChildById('executeSellAllBtn')

    if sellTabBtn then
        sellTabBtn:setEnabled(tab ~= 'sell')
    end
    if blTabBtn then
        blTabBtn:setEnabled(tab ~= 'blacklist')
    end

    if not itemsGrid then
        return
    end
    itemsGrid:destroyChildren()

    if tab == 'sell' then
        if sectionHeader then
            sectionHeader:setText(tr('Sale Progress'))
        end
        if saleProgressBar then
            saleProgressBar:setVisible(true)
        end
        if executeSellAllBtn then
            executeSellAllBtn:setVisible(true)
        end

        local entries, totalGold = self:getQuickSellEntries()
        local currencyText = (self.currencyName and self.currencyName:lower()) or 'gold'
        if currencyText == 'gold coin' then
            currencyText = 'gold'
        end

        local selectedStillExists = false
        for _, entry in ipairs(entries) do
            local tile = g_ui.createWidget('QuickSellItemTile', itemsGrid)
            local displayItem = Item.create(entry.id, math.min(entry.qty, 100))
            if tile.item then
                tile.item:setItem(displayItem)
                if tile.item.setItemCount then
                    tile.item:setItemCount(entry.qty)
                end
            end
            tile:setTooltip(string.format("%s x%d (%d %s)\nLeft-click: select | Right-click: Add to BlackList",
                entry.name, entry.qty, entry.value, currencyText))

            if self.selectedQuickSellEntry and self.selectedQuickSellEntry.id == entry.id then
                selectedStillExists = true
                tile:focus()
            end

            tile.onClick = function()
                self.selectedQuickSellEntry = entry
                if sellItemBtn then
                    sellItemBtn:setEnabled(not self.isSellingAll)
                end
                if saleValueLabel then
                    saleValueLabel:setText(string.format("Sale value: %d %s", entry.value, currencyText))
                end
            end

            tile.onMouseRelease = function(widget, mousePos, mouseButton)
                if mouseButton == MouseRightButton then
                    local menu = g_ui.createWidget('PopupMenu')
                    menu:setGameMenu(true)
                    menu:addOption(tr('Add to Quick Sell Blacklist'), function()
                        self:addToQuickSellBlacklist(entry.id)
                        self:refreshQuickSellWindow()
                    end)
                    menu:display(mousePos)
                    return true
                end
                return false
            end
        end

        if not selectedStillExists then
            self.selectedQuickSellEntry = nil
        end

        if saleValueLabel then
            local shownValue = self.selectedQuickSellEntry and self.selectedQuickSellEntry.value or totalGold
            saleValueLabel:setText(string.format("Sale value: %d %s", shownValue, currencyText))
        end
        if sellItemBtn then
            sellItemBtn:setEnabled((self.selectedQuickSellEntry ~= nil) and (not self.isSellingAll))
        end
        if executeSellAllBtn then
            executeSellAllBtn:setEnabled((#entries > 0) and (not self.isSellingAll))
        end
    else
        if sectionHeader then
            sectionHeader:setText(tr('BlackList Items'))
        end
        if saleProgressBar then
            saleProgressBar:setVisible(true)
            saleProgressBar:setPercent(0)
        end
        if executeSellAllBtn then
            executeSellAllBtn:setVisible(false)
        end
        if sellItemBtn then
            sellItemBtn:setEnabled(false)
        end
        if saleValueLabel then
            saleValueLabel:setText('Sale value: 0 gold')
        end

        local ids = self:getQuickSellBlacklistEntries()
        for _, itemId in ipairs(ids) do
            local tile = g_ui.createWidget('QuickSellItemTile', itemsGrid)
            local displayItem = Item.create(itemId, 1)
            if tile.item then
                tile.item:setItem(displayItem)
            end
            local thingType = g_things and g_things.getThingType(itemId, ThingCategoryItem)
            local itemName = (thingType and thingType.getName and thingType:getName()) or string.format('Item #%d', itemId)
            tile:setTooltip(string.format("%s (#%d)\nLeft/Right-click: Remove from BlackList", itemName, itemId))
            tile.onMouseRelease = function(widget, mousePos, mouseButton)
                if mouseButton == MouseRightButton or mouseButton == MouseLeftButton then
                    self:removeFromQuickSellBlacklist(itemId)
                    self:refreshQuickSellWindow()
                    return true
                end
                return false
            end
        end
    end
end

function controllerNpcTrader:sellSelectedQuickSellItem()
    local entry = self.selectedQuickSellEntry
    if not entry or not entry.ptr or self.isSellingAll then
        return
    end
    local remaining = self:getSellQuantity(entry.ptr)
    local maxPossible = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
    while remaining > 0 do
        local chunk = math.min(remaining, maxPossible)
        g_game.sellItem(entry.ptr, chunk, self.ignoreEquipped)
        remaining = remaining - chunk
    end
    self.selectedQuickSellEntry = nil
    scheduleEvent(function()
        self:refreshQuickSellWindow()
    end, 250)
end

function controllerNpcTrader:startQuickSellAll()
    if self.isSellingAll then
        return
    end
    self:updateQuickSellProgress(0, 1)
    self:sellAll()
    self:refreshQuickSellWindow()
end
