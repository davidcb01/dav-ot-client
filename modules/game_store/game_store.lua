-- Auxiliar miniWindows
local acceptWindow = nil
local changeNameWindow = nil
local transferPointsWindow = nil
local processingWindow = nil
local messageBox = nil


local oldProtocol = false
local a0xF2 = true

local offerDescriptions = {}
local reasonCategory = {}
local bannersHome = {}
local lastStoreProducts = nil

local currentIndex = 1

-- /*=============================================
-- =            To-do                  =
-- =============================================*/
-- - Fix filter functionality
-- - Correct HTML string syntax
-- - cache
-- - try on outfit
-- - improve homePanel/hystoryPanel

GameStore = {}
-- == Enums ==--
GameStore.website = {
    WEBSITE_GETCOINS = "https://github.com/mehah/otclient",
    --IMAGES_URL =  "http://localhost/images/store/" --./game_store --https://docs.opentibiabr.com/opentibiabr/downloads/website-applications/applications#store-for-client-13-1
}

GameStore.CoinType = {
    Coin = 0,
    Transferable = 1
}

GameStore.ClientOfferTypes = {
	CLIENT_STORE_OFFER_OTHER = 0,
	CLIENT_STORE_OFFER_NAMECHANGE = 1,
	CLIENT_STORE_OFFER_WORLD_TRANSFER = 2,
	CLIENT_STORE_OFFER_HIRELING = 3, --idk
	CLIENT_STORE_OFFER_CHARACTER = 4,--idk
	CLIENT_STORE_OFFER_TOURNAMENT = 5,--idk
	CLIENT_STORE_OFFER_CONFIRM = 6,--idk
}

GameStore.States = {
    STATE_NONE = 0,
    STATE_NEW = 1,
    STATE_SALE = 2,
    STATE_TIMED = 3
}

GameStore.SendingPackets = {
    S_CoinBalance = 0xDF, -- 223
    S_StoreError = 0xE0, -- 224
    S_RequestPurchaseData = 0xE1, -- 225
    S_CoinBalanceUpdating = 0xF2, -- 242
    S_OpenStore = 0xFB, -- 251
    S_StoreOffers = 0xFC, -- 252
    S_OpenTransactionHistory = 0xFD, -- 253
    S_CompletePurchase = 0xFE -- 254
}

GameStore.RecivedPackets = {
    C_StoreEvent = 0xE9, -- 233
    C_TransferCoins = 0xEF, -- 239
    C_ParseHirelingName = 0xEC, -- 236
    C_OpenStore = 0xFA, -- 250
    C_RequestStoreOffers = 0xFB, -- 251
    C_BuyStoreOffer = 0xFC, -- 252
    C_OpenTransactionHistory = 0xFD, -- 253
    C_RequestTransactionHistory = 0xFE -- 254
}

-- /*=============================================
-- =            Local Function auxiliaries      =
-- =============================================*/

local function showPanel(panel)
    if panel == "HomePanel" then
        controllerShop.ui.HomePanel:setVisible(true)
        controllerShop.ui.panelItem:setVisible(false)
        controllerShop.ui.transferHistory:setVisible(false)
    elseif panel == "transferHistory" then
        controllerShop.ui.HomePanel:setVisible(false)
        controllerShop.ui.panelItem:setVisible(false)
        controllerShop.ui.transferHistory:setVisible(true)
    elseif panel == "panelItem" then
        controllerShop.ui.HomePanel:setVisible(false)
        controllerShop.ui.panelItem:setVisible(true)
        controllerShop.ui.transferHistory:setVisible(false)
    end
end

local function destroyWindow(windows)
    if type(windows) == "table" then
        for _, window in ipairs(windows) do
            if window and not window:isDestroyed() then
                window:destroy()
                window = nil
            end
        end
    else
        if windows and not windows:isDestroyed() then
            windows:destroy()
            windows = nil
        end
    end
end

local function getPageLabelHistory()
    local text = controllerShop.ui.transferHistory.lblPage:getText()
    local currentPage, pageCount = text:match("Page (%d+)/(%d+)")
    return tonumber(currentPage), tonumber(pageCount)
end

local function applyLocalStoreImage(widget, localPath, isIcon)
    if not widget or widget:isDestroyed() then
        return
    end
    if isIcon then
        widget:setIcon(localPath)
    else
        widget:setImageSource(localPath)
        widget:setImageFixedRatio(true)
    end
end

local storeFileExistsCache = {}
local storeHttpImageCache = {}

local function cachedStoreFileExists(path)
    local hit = storeFileExistsCache[path]
    if hit ~= nil then
        return hit
    end
    local ok = g_resources.fileExists(path)
    storeFileExistsCache[path] = ok
    return ok
end

local function setImagenHttp(widget, url, isIcon)
    if not widget or widget:isDestroyed() then
        return
    end
    local cleanUrl = tostring(url or ""):gsub("^/+", "")
    local localPath = cleanUrl ~= "" and ("/game_store/images/" .. cleanUrl) or ""
    local fallbackPath = isIcon and "/game_store/images/13/default.png" or "/game_store/images/64/default.png"

    if cleanUrl ~= "" and cachedStoreFileExists(localPath) then
        applyLocalStoreImage(widget, localPath, isIcon)
        return
    end

    if cleanUrl ~= "" and storeHttpImageCache[cleanUrl] ~= nil then
        local cached = storeHttpImageCache[cleanUrl]
        if cached then
            applyLocalStoreImage(widget, cached, isIcon)
        else
            applyLocalStoreImage(widget, cachedStoreFileExists(fallbackPath) and fallbackPath or "/game_store/images/dynamic-image-error", isIcon)
        end
        return
    end

    local baseUrl = GameStore.website.IMAGES_URL
    if baseUrl and baseUrl ~= "" and cleanUrl ~= "" then
        HTTP.downloadImage(baseUrl .. cleanUrl, function(path, err)
            if err or not path or path == "" then
                storeHttpImageCache[cleanUrl] = false
            else
                storeHttpImageCache[cleanUrl] = path
            end
            if not widget or widget:isDestroyed() then
                return
            end
            if err or not path or path == "" then
                applyLocalStoreImage(widget, cachedStoreFileExists(fallbackPath) and fallbackPath or "/game_store/images/dynamic-image-error", isIcon)
                return
            end
            applyLocalStoreImage(widget, path, isIcon)
        end)
    else
        applyLocalStoreImage(widget, cachedStoreFileExists(fallbackPath) and fallbackPath or "/game_store/images/dynamic-image-error", isIcon)
    end
end

local STORE_ICON_PATH = "/game_store/images/store-icons-inline"
local STORE_ICON_TAGS = {
    ["{info}"]                    = {clip = "0 0 13 13",   text = ""},
    ["{character}"]               = {clip = "13 0 13 13",  text = "only usable by purchasing character"},
    ["{charactericon}"]           = {clip = "13 0 13 13",  text = ""},
    ["{usablebyall}"]             = {clip = "26 0 13 13",  text = "can be used by all characters that have access to the house"},
    ["{usablebyallicon}"]         = {clip = "26 0 13 13",  text = ""},
    ["{box}"]                     = {clip = "39 0 13 13",  text = "comes in a box which can only be unwrapped by purchasing character"},
    ["{boxicon}"]                 = {clip = "39 0 13 13",  text = ""},
    ["{storeinbox}"]              = {clip = "52 0 13 13",  text = "will be sent to your Store inbox and can only be stored there and in depot box"},
    ["{storeinboxicon}"]          = {clip = "52 0 13 13",  text = ""},
    ["{house}"]                   = {clip = "65 0 13 13",  text = "can only be unwrapped in a house owned by the purchasing character"},
    ["{houseicon}"]               = {clip = "65 0 13 13",  text = ""},
    ["{once}"]                    = {clip = "78 0 13 13",  text = "can only be purchased once"},
    ["{onceicon}"]                = {clip = "78 0 13 13",  text = ""},
    ["{backtoinbox}"]             = {clip = "91 0 13 13",  text = "will be wrapped back and sent to inbox if the purchasing character is no longer the house owner"},
    ["{backtoinboxicon}"]         = {clip = "91 0 13 13",  text = ""},
    ["{vocationlevelcheck}"]      = {clip = "104 0 13 13", text = "only buyable if fitting vocation and level of purchasing character"},
    ["{vocationlevelcheckicon}"]  = {clip = "104 0 13 13", text = ""},
    ["{speedboost}"]              = {clip = "117 0 13 13", text = "provides character with a speed boost"},
    ["{speedboosticon}"]          = {clip = "117 0 13 13", text = ""},
    ["{activated}"]               = {clip = "130 0 13 13", text = "activated at purchase"},
    ["{activatedicon}"]           = {clip = "130 0 13 13", text = ""},
    ["{battlesign}"]              = {clip = "143 0 13 13", text = "cannot be purchased by characters with protection zone block or battle sign"},
    ["{battlesignicon}"]          = {clip = "143 0 13 13", text = ""},
    ["{capacity}"]                = {clip = "156 0 13 13", text = "cannot be purchased if capacity is exceeded"},
    ["{capacityicon}"]            = {clip = "156 0 13 13", text = ""},
    ["{use}"]                     = {clip = "169 0 13 13", text = "can be used"},
    ["{useicon}"]                 = {clip = "169 0 13 13", text = ""},
    ["{transferableprice}"]       = {clip = "182 0 13 13", text = "can be purchased with transferable Tibia Coins"},
    ["{transferablepriceicon}"]   = {clip = "182 0 13 13", text = ""},
    ["{star}"]                    = {localImg = "/game_store/images/icon-star-gold", text = ""},
}

local function matchIconTag(line)
    if line:byte(1) ~= 123 then return nil end -- fast bail if not '{'
    local s, e, cap = line:find("^{limit|(%d+)}")
    if s then
        return {clip = "78 0 13 13", text = "maximum amount that can be owned by character: %s"}, e, cap
    end
    local close = line:find("}", 1, true)
    if close then
        local info = STORE_ICON_TAGS[line:sub(1, close)]
        if info then return info, close, nil end
    end
end

local function addDescriptionLine(container, lineText, color)
    if not lineText:match("%S") then return end
    lineText = lineText:gsub("<[^>]+>", ""):gsub("&nbsp;", " "):gsub("&#8226;", "- ")

    local widget = g_ui.createWidget('DescriptionLine', container)
    if not widget then return end

    local iconWidget = widget:getChildById('icon')
    local textWidget = widget:getChildById('text')
    if not iconWidget or not textWidget then return end
    if color then textWidget:setColor(color) end

    local info, tagEnd, cap = matchIconTag(lineText)
    if info then
        iconWidget:setVisible(true)
        if info.localImg then
            iconWidget:setImageSource(info.localImg)
        else
            iconWidget:setImageSource(STORE_ICON_PATH)
            iconWidget:setImageClip(info.clip)
        end
        local tagText = (cap and info.text:format(cap)) or info.text
        local rest    = lineText:sub(tagEnd + 1):match("^%s*(.-)%s*$")
        textWidget:setMarginLeft(16)
        textWidget:setText(tagText ~= "" and (tagText .. " " .. rest) or rest)
    else
        textWidget:setMarginLeft(0)
        textWidget:setText(lineText:match("^%s*(.-)%s*$"))
    end

    widget:setHeight(math.max(14, textWidget:getTextSize().height + 2))
end

local function renderDescription(panel, text, errorText)
    local descPanel = panel:getChildById('descriptionPanel')
    local container = descPanel and descPanel:getChildById('descriptionScrollArea')
    if not container or container:isDestroyed() then return end
    local layout = container:getLayout()
    if layout then layout:disableUpdates() end
    container:destroyChildren()

    if errorText then
        for line in errorText:gmatch("[^\r\n]+") do
            addDescriptionLine(container, line, "#d33c3c")
        end
    end

    if text and text ~= "" then
        for line in text:gmatch("[^\r\n]+") do
            addDescriptionLine(container, line, nil)
        end
    end
    if layout then
        layout:enableUpdates()
        layout:update()
    end
end

local function formatNumberWithCommas(value)
    local sign = value < 0 and "-" or ""
    value = math.abs(value)
    local formattedValue = string.format("%d", value)
    formattedValue = formattedValue:reverse():gsub("(%d%d%d)", "%1,")
    formattedValue = formattedValue:reverse():gsub("^,", "")
    return sign .. formattedValue
end

local function getCoinsBalance()
    local function extractNumber(text)
        if type(text) ~= "string" then 
            return 0 
        end
        local numberStr = text:match("%d[%d,]*")
        if not numberStr then 
            return 0 
        end
        local cleanNumber = numberStr:gsub("[^%d]", "")
        return tonumber(cleanNumber) or 0
    end

    -- get coins: normal (non transferableCoins) | transfer(transferableCoins))
    local lblNormal = controllerShop.ui.lblCoins.lblTibiaCoins
    local lblTransfer = controllerShop.ui.lblCoins.lblTibiaTransfer

    local normalCoins = lblNormal and extractNumber(lblNormal:getText()) or 0
    local transferableCoins = lblTransfer and extractNumber(lblTransfer:getText()) or 0

    return normalCoins, transferableCoins
end

local function fixServerNoSend0xF2()
    if a0xF2 then
        local player = g_game.getLocalPlayer()
        if not player then
            return
        end
        local coin, transfer = getCoinsBalance()
        local coinBalance = player:getResourceBalance(ResourceTypes.COIN_NORMAL)
        local transferBalance = player:getResourceBalance(ResourceTypes.COIN_TRANSFERRABLE)
        if not coin or not transfer or coin ~= coinBalance or transfer ~= transferBalance then
            controllerShop.ui.lblCoins.lblTibiaCoins:setText(formatNumberWithCommas(coinBalance))
    
            if transfer ~= transferBalance then
                controllerShop.ui.lblCoins.lblTibiaTransfer:setText(
                    string.format("(Including: %s", formatNumberWithCommas(transferBalance))
                )
            end
            local packet2 = GameStore.SendingPackets.S_CoinBalanceUpdating
            g_logger.warning(string.format("[game_store BUG] Check 0x%X (%d) on server  onParseStoreGetCoin", packet2, packet2))
        end 
    end
end

local function convert_timestamp(timestamp)
    local fecha_hora = os.date("%Y-%m-%d, %H:%M:%S", timestamp)
    return fecha_hora
end

local function getProductData(product)
    if product.itemId or product.itemType then
        return {
            VALOR = "item",
            ID = product.itemId or product.itemType
        }
    elseif product.icon then
        return {
            VALOR = "icon",
            ID = product.icon
        }
    elseif product.outfitId or product.mountId or product.sexId then
        return {
            VALOR = "mountId",
            ID = product.outfitId or product.mountId or product.sexId
        }
    elseif product.maleOutfitId then
        return {
            VALOR = "outfitId",
            ID = product.maleOutfitId
        }
    end
end

local function createProductImage(imageParent, data)
    if not imageParent or imageParent:isDestroyed() or not data or not data.ID then
        return
    end
    if data.VALOR == "item" then
        local itemWidget = g_ui.createWidget('Item', imageParent)
        itemWidget:setId(data.ID)
        itemWidget:setItemId(data.ID)
        itemWidget:setVirtual(true)
        itemWidget:fill('parent')
    elseif data.VALOR == "icon" then
        local widget = g_ui.createWidget('UIWidget', imageParent)
        setImagenHttp(widget, "/64/" .. data.ID, false)
        widget:fill('parent')
    elseif data.VALOR == "mountId" or data.VALOR:find("outfitId") then
        local creature = g_ui.createWidget('Creature', imageParent)
        creature:setOutfit({
            type = data.ID
        })
        local c = creature:getCreature()
        if c then
            c:setStaticWalking(1000)
        end
        creature:fill('parent')
    end
end

-- /*=============================================
-- =    behavior categories and subcategories    =
-- =============================================*/

local function disableAllButtons()
    local panel = controllerShop.ui.panelItem
    panel:getChildById('StackOffers'):destroyChildren()
    panel:getChildById('image'):destroyChildren()
    for i = 1, controllerShop.ui.listCategory:getChildCount() do
        local widget = controllerShop.ui.listCategory:getChildByIndex(i)
        if widget and widget.Button then
            widget.Button:setEnabled(false)
            if widget.subCategories then
                for subId, _ in ipairs(widget.subCategories) do
                    local subWidget = widget:getChildById(subId)
                    if subWidget and subWidget.Button then
                        subWidget.Button:setEnabled(false)
                    end
                end
            end
        end
    end
    offerDescriptions = {}
end

local function enableAllButtons()
    for i = 1, controllerShop.ui.listCategory:getChildCount() do
        local widget = controllerShop.ui.listCategory:getChildByIndex(i)
        if widget and widget.Button then
            widget.Button:setEnabled(true)
            if widget.subCategories then
                for subId, _ in ipairs(widget.subCategories) do
                    local subWidget = widget:getChildById(subId)
                    if subWidget and subWidget.Button then
                        subWidget.Button:setEnabled(true)
                    end
                end
            end
        end
    end
end

local function toggleSubCategories(parent, isOpen)
    for subId, _ in ipairs(parent.subCategories) do
        local subWidget = parent:getChildById(subId)
        if subWidget then
            subWidget:setVisible(isOpen)
            if subId == 1 then
                subWidget.Button:setChecked(true)
                subWidget.Button.Arrow:setVisible(true)
                subWidget.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-right")
            end
        end
    end
    parent:setHeight(isOpen and parent.openedSize or parent.closedSize)
    parent.opened = isOpen
    parent.Button.Arrow:setVisible(not isOpen)
end

local function close(parent)
    if parent.subCategories then
        toggleSubCategories(parent, false)
    end
end

local function open(parent)
    local oldOpen = controllerShop.ui.openedCategory
    if oldOpen and oldOpen ~= parent then
        close(oldOpen)
    end
    toggleSubCategories(parent, true)
    controllerShop.ui.openedCategory = parent
end

local function closeCategoryButtons()
    for i = 1, controllerShop.ui.listCategory:getChildCount() do
        local widget = controllerShop.ui.listCategory:getChildByIndex(i)
        if widget and widget.subCategories then
            for subId, _ in ipairs(widget.subCategories) do
                local subWidget = widget:getChildById(subId)
                if subWidget then
                    subWidget.Button:setChecked(false)
                    subWidget.Button.Arrow:setVisible(false)
                end
            end
        end
    end
end

local function createSubWidget(parent, subId, subButton)
    local subWidget = g_ui.createWidget("storeCategory", parent)
    subWidget:setId(subId)
    setImagenHttp(subWidget.Button.Icon, subButton.icon, true)
    subWidget.Button.Title:setText(subButton.text)
    subWidget:setVisible(false)
    subWidget.open = subButton.open
    subWidget:setMarginLeft(15)
    subWidget.Button:setSize('163 20')
    function subWidget.Button.onClick()
        disableAllButtons()
        local selectedOption = controllerShop.ui.selectedOption
        closeCategoryButtons()
        parent.Button:setChecked(false)
        parent.Button.Arrow:setVisible(false)
        subWidget.Button:setChecked(true)
        subWidget.Button.Arrow:setVisible(true)
        subWidget.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-right")
        controllerShop.ui.openedSubCategory = subWidget

        if selectedOption then
            selectedOption:hide()
        end
        if subWidget.open == "Home" then
            g_game.sendRequestStoreHome()
        else
            g_game.requestStoreOffers(subButton.text,"", 0, 1)
        end
    end

    subWidget:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
    if subId == 1 then
        subWidget:addAnchor(AnchorTop, "parent", AnchorTop)
        subWidget:setMarginTop(20)
    else
        subWidget:addAnchor(AnchorTop, "prev", AnchorBottom)
        subWidget:setMarginTop(-1)
    end

    return subWidget
end

-- /*=============================================
-- =            Controller                   =
-- =============================================*/
controllerShop = Controller:new()
g_ui.importStyle("style/ui.otui")
controllerShop:setUI('game_store')
function controllerShop:onInit()
    controllerShop.ui:hide()

    local sortCombo = controllerShop.ui.panelItem.comboBoxContainer.MostPopularFirst
    for _, v in pairs({{'Most Popular First', 'MostPopularFirst'}, {'Alphabetically', 'Alphabetically'},
                       {'Lowest Price', 'LowestPrice'}, {'Newest First', 'NewestFirst'}}) do
        sortCombo:addOption(v[1], v[2])
    end

    local filterCombo = controllerShop.ui.panelItem.comboBoxContainer.showAll
    local function reapplyFilterAndSort()
        if lastStoreProducts then
            onParseStoreCreateProducts(lastStoreProducts, true)
        end
    end
    sortCombo.onOptionChange = reapplyFilterAndSort
    filterCombo.onOptionChange = reapplyFilterAndSort

    local searchEdit = controllerShop.ui.SearchEdit
    if searchEdit then
        searchEdit.onKeyPress = function(widget, keyCode, keyboardModifiers)
            if keyCode == KeyEnter or keyCode == KeyNumpadEnter or keyCode == 3 then
                search()
                return true
            end
            return false
        end
    end

    controllerShop.ui.transferPoints.onClick = transferPoints
    controllerShop.ui.panelItem.listProduct.onChildFocusChange = chooseOffert
    controllerShop.ui.HomePanel.HomeRecentlyAdded.HomeProductos.onChildFocusChange = chooseHome
    -- /*=============================================
    -- =            Parse                         =
    -- =============================================*/

    controllerShop:registerEvents(g_game, {
        onParseStoreGetCoin = onParseStoreGetCoin,
        onParseStoreGetCategories = onParseStoreGetCategories,
        onParseStoreCreateHome = onParseStoreCreateHome,
        onParseStoreCreateProducts = onParseStoreCreateProducts,
        onParseStoreGetHistory = onParseStoreGetHistory,
        onParseStoreGetPurchaseStatus = onParseStoreGetPurchaseStatus,
        onParseStoreOfferDescriptions = onParseStoreOfferDescriptions,
        onParseStoreError = onParseStoreError,
        onStoreInit = onStoreInit
    })
end

function controllerShop:onGameStart()
    oldProtocol = g_game.getClientVersion() < 1310
end

function controllerShop:onGameEnd()
    if controllerShop.ui:isVisible() then
        controllerShop.ui:hide()
    end

    destroyWindow({transferPointsWindow, changeNameWindow, acceptWindow, processingWindow,messageBox})
end

function controllerShop:onTerminate()
    destroyWindow({transferPointsWindow, changeNameWindow, acceptWindow, processingWindow,messageBox})
end

-- /*=============================================
-- =            Parse                           =
-- =============================================*/

function onStoreInit(url, coinsPacketSize)
    if url and url ~= "" and (not GameStore.website.IMAGES_URL or GameStore.website.IMAGES_URL == "") then
        GameStore.website.IMAGES_URL = url
    end
end

function onParseStoreGetCoin(getTibiaCoins, getTransferableCoins)
    a0xF2 = false
    controllerShop.ui.lblCoins.lblTibiaCoins:setText(formatNumberWithCommas(getTibiaCoins))
    controllerShop.ui.lblCoins.lblTibiaTransfer:setText(string.format("(Including: %s",
        formatNumberWithCommas(getTransferableCoins)))
end

function onParseStoreOfferDescriptions(offerId, description)
    offerDescriptions[offerId] = {
        id = offerId,
        description = description
    }
end

function onParseStoreGetPurchaseStatus(purchaseStatus)
    destroyWindow({processingWindow, messageBox})
    controllerShop.ui:hide()
    messageBox = g_ui.createWidget('confirmarSHOP', g_ui.getRootWidget())
    messageBox.Box:setText(purchaseStatus)
    messageBox.buttonAnimation.animation:setImageClip("0 0 108 108")
    local animationEvent = nil
    local closeEvent = nil
    local function finishPurchasePopup()
        if animationEvent then
            removeEvent(animationEvent)
            animationEvent = nil
        end
        if closeEvent then
            removeEvent(closeEvent)
            closeEvent = nil
        end
        destroyWindow({messageBox})
        if controllerShop.ui then
            controllerShop.ui:show()
            controllerShop.ui:raise()
        end
        fixServerNoSend0xF2()
    end
    messageBox.onEscape = finishPurchasePopup
    messageBox.buttonAnimation.onClick = function(widget)
        messageBox.buttonAnimation:disable()
        local phase = 0
        animationEvent = periodicalEvent(function()
            if messageBox and messageBox.buttonAnimation and messageBox.buttonAnimation.animation then
                messageBox.buttonAnimation.animation:setImageClip((phase % 13 * 108) .. " 0 108 108")
                phase = phase + 1
                if phase >= 12 then
                    phase = 11
                end
            end
        end, function()
            return messageBox and messageBox.buttonAnimation and messageBox.buttonAnimation.animation
        end, 60, 60)
        closeEvent = controllerShop:scheduleEvent(finishPurchasePopup, 650)
    end
end

local function getProductMinPrice(product)
    local subOffers = product.subOffers
    if subOffers and #subOffers > 0 then
        local minPrice = subOffers[1].price or 0
        for i = 2, #subOffers do
            minPrice = math.min(minPrice, subOffers[i].price or 0)
        end
        return minPrice
    end
    return product.price or 0
end

local function isProductDisabled(product)
    local subOffers = product.subOffers
    if subOffers and #subOffers > 0 then
        for _, s in ipairs(subOffers) do
            if not s.disabled then
                return false
            end
        end
        return true
    end
    return product.disabled == true
end

function onParseStoreCreateProducts(storeProducts, isReapply)
    if not storeProducts then
        return
    end
    if not isReapply then
        lastStoreProducts = storeProducts
    end

    local comboBox = controllerShop.ui.panelItem.comboBoxContainer.showAll
    if not isReapply then
        comboBox:clearOptions()
        comboBox:addOption("Show All", "all")
        comboBox:addOption("Available Only", "available")
        if storeProducts.menuFilter and #storeProducts.menuFilter > 0 then
            for k, t in pairs(storeProducts.menuFilter) do
                if tostring(t):lower() ~= "show all" then
                    comboBox:addOption(t, "filter_" .. k)
                end
            end
        end
        reasonCategory = storeProducts.disableReasons or {}
    end

    local listProduct = controllerShop.ui.panelItem.listProduct
    local listLayout = listProduct:getLayout()
    if listLayout then listLayout:disableUpdates() end
    listProduct:destroyChildren()

    local offersList = {}
    for _, product in ipairs(storeProducts.offers or {}) do
        table.insert(offersList, product)
    end

    local filterOpt = comboBox:getCurrentOption()
    local filterData = filterOpt and filterOpt.data or "all"
    if filterData == "available" then
        local filtered = {}
        for _, product in ipairs(offersList) do
            if not isProductDisabled(product) then
                table.insert(filtered, product)
            end
        end
        offersList = filtered
    end

    local sortOpt = controllerShop.ui.panelItem.comboBoxContainer.MostPopularFirst:getCurrentOption()
    local sortKey = sortOpt and sortOpt.data or "MostPopularFirst"
    if sortKey == "Alphabetically" then
        table.sort(offersList, function(a, b)
            return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
        end)
    elseif sortKey == "LowestPrice" then
        table.sort(offersList, function(a, b)
            return getProductMinPrice(a) < getProductMinPrice(b)
        end)
    elseif sortKey == "NewestFirst" then
        table.sort(offersList, function(a, b)
            return (a.state == GameStore.States.STATE_NEW and 0 or 1) < (b.state == GameStore.States.STATE_NEW and 0 or 1)
        end)
    end

    if #offersList == 0 then
        if listLayout then
            listLayout:enableUpdates()
            listLayout:update()
        end
        local panel = controllerShop.ui.panelItem
        panel:getChildById('lblName'):setText("No offers found")
        panel:getChildById('image'):destroyChildren()
        panel:getChildById('StackOffers'):destroyChildren()
        renderDescription(panel, "No offers matched the current category or search.")
        enableAllButtons()
        showPanel("panelItem")
        return
    end

    fixServerNoSend0xF2()
    local coinsBalance2, coinsBalance1 = getCoinsBalance()

    for _, product in ipairs(offersList) do
        local row = g_ui.createWidget('RowStore', listProduct)
        row.product, row.type = product, product.type

        local nameLabel = row:getChildById('lblName')
        nameLabel:setText(product.name)
        nameLabel:setTextAlign(AlignCenter)
        nameLabel:setMarginRight(10)

        local subOffers = product.subOffers or { product }
        local stackContainer = row:getChildById('StackOffers')
        for _, subOffer in ipairs(subOffers) do
            local offerI = g_ui.createWidget('stackOfferPanel', stackContainer)
            offerI:setId(subOffer.id)
            if subOffer.disabled then
                offerI:disable()
                row:setOpacity(0.5)
            end
            local priceLabel = offerI:getChildById('lblPrice')
            priceLabel:setText(subOffer.price)

            if subOffer.count and subOffer.count > 0 then
                offerI:getChildById('count'):setText(subOffer.count .. "x")
            end
            local isTransferable = subOffer.coinType == GameStore.CoinType.Transferable
            local price = subOffer.price
            local balance = isTransferable and coinsBalance1 or (coinsBalance1 + coinsBalance2)
            priceLabel:setColor(balance < price and "#d33c3c" or "white")

            if isTransferable then
                priceLabel:setIcon("/game_store/images/icon-tibiacointransferable")
            end
        end
        local data = getProductData(product)
        if data then
            createProductImage(row:getChildById('image'), data)
        end
    end

    if listLayout then
        listLayout:enableUpdates()
        listLayout:update()
    end

    controllerShop:scheduleEvent(function()
        local redirectId = storeProducts.redirectId
        if redirectId and type(redirectId) == "number" and redirectId ~= 0 then -- home behavior 
            for _, child in ipairs(listProduct:getChildren()) do
                for _, subOffer in ipairs(child.product.subOffers or { child.product }) do
                    if subOffer.id == redirectId then
                        listProduct:focusChild(child)
                        listProduct:ensureChildVisible(child)
                        return
                    end
                end
            end
        else
            local firstChild = listProduct:getFirstChild()
            if firstChild and firstChild:isEnabled() then
                listProduct:focusChild(firstChild)
                listProduct:ensureChildVisible(firstChild)
            end
        end
    end, 15, 'onParseStoreOfferDescriptionsSafeDelay')

    enableAllButtons()
    showPanel("panelItem")
end

function onParseStoreCreateHome(offer)
    if not offer then
        return
    end
    local homeProductos = controllerShop.ui.HomePanel.HomeRecentlyAdded.HomeProductos
    local homeLayout = homeProductos:getLayout()
    if homeLayout then homeLayout:disableUpdates() end
    homeProductos:destroyChildren()
    for _, product in ipairs(offer.offers or {}) do
        local row = g_ui.createWidget('RowStore', homeProductos)
        row.product, row.type = product, product.type

        local nameLabel = row:getChildById('lblName')
        nameLabel:setText(product.name)
        nameLabel:setTextAlign(AlignCenter)
        nameLabel:setMarginRight(10)
        
        local subOfferWidget = g_ui.createWidget('stackOfferPanel', row:getChildById('StackOffers'))

        subOfferWidget.lblPrice:setText(product.price)
        if product.coinType == GameStore.CoinType.Transferable then
            subOfferWidget.lblPrice:setIcon("/game_store/images/icon-tibiacointransferable")
        else
            subOfferWidget.lblPrice:setIcon("/images/ui/tibiaCoin")
        end

        local data = getProductData(product)
        if data then
            createProductImage(row:getChildById('image'), data)
        end
    end
    if homeLayout then
        homeLayout:enableUpdates()
        homeLayout:update()
    end

    if offer.banners and #offer.banners > 0 then
        currentIndex = math.random(1, #offer.banners)
        local ramdomImg = offer.banners[currentIndex].image
        setImagenHttp(controllerShop.ui.HomePanel.HomeImagen, ramdomImg, false)
        bannersHome = table.copy(offer.banners)
    else
        bannersHome = {}
        setImagenHttp(controllerShop.ui.HomePanel.HomeImagen, "home/banner_armouredarcher.png", false)
    end
    enableAllButtons()
    showPanel("HomePanel")
    fixServerNoSend0xF2()
end

function onParseStoreGetHistory(currentPage, pageCount, historyData)
    local transferHistory = controllerShop.ui.transferHistory.historyPanel
    transferHistory:destroyChildren()
    local headerRow = g_ui.createWidget("historyData2", transferHistory)
    headerRow:setBackgroundColor("#363636")
    headerRow:setBorderColor("#00000077")
    headerRow:setBorderWidth(1)
    headerRow.date:setText("Date")
    headerRow.Balance:setText("Balance")
    headerRow.Description:setText("Description")
    controllerShop.ui.transferHistory.lblPage:setText(string.format("Page %d/%d", currentPage + 1, pageCount))
    for i, data in ipairs(historyData) do
        local row = g_ui.createWidget("historyData2", transferHistory)
        row.date:setText(convert_timestamp(data[1]))
        local balance = data[3]
        row.Balance:setText(formatNumberWithCommas(balance))
        row.Balance:setColor(balance < 0 and "#D33C3C" or "#3CD33C")
        row.Description:setText(data[5])
        row.Balance:setIcon(data[4] == GameStore.CoinType.Transferable and 
                            "/game_store/images/icon-tibiacointransferable" or 
                            "/images/ui/tibiaCoin")
        row:setBackgroundColor(i % 2 == 0 and "#ffffff12" or "#00000012")
    end
    showPanel("transferHistory")
end

function onParseStoreGetCategories(buttons)
    if controllerShop.ui.listCategory:getChildCount() > 0 then
        return
    end
    controllerShop.ui.listCategory:destroyChildren()

    local categories = {}
    if not oldProtocol then
        categories = {
            ["Home"] = {
                ["subCategories"] = {},
                ["name"] = "Home",
                ["icons"] = {
                    [1] = "icon-store-home.png"
                },
                ["state"] = 0
            }
        }
    end

    local subcategories = {}

    for _, button in ipairs(buttons) do
        if not button.parent then
            categories[button.name] = button
            categories[button.name].subCategories = {}
        else
            table.insert(subcategories, button)
        end
    end

    for _, subcat in ipairs(subcategories) do
        if categories[subcat.parent] then
            table.insert(categories[subcat.parent].subCategories, subcat)
        end
    end

    local orderedCategoryNames = {"Home", "Premium Time", "Consumables", "Cosmetics", "Houses", "Boosts", "Extras",
                                "Tournament"}

    local priority = {}
    for index, name in ipairs(orderedCategoryNames) do
        priority[name] = index
    end

    local categoryArray = {}
    for name, data in pairs(categories) do
        table.insert(categoryArray, data)
    end

    -- Ordenar el array
    table.sort(categoryArray, function(a, b)
        local prioA = priority[a.name] or math.huge
        local prioB = priority[b.name] or math.huge
        return prioA < prioB
    end)

    for _, category in ipairs(categoryArray) do
        local widget = g_ui.createWidget("storeCategory", controllerShop.ui.listCategory)
        widget:setId(category.name)
            -- widget.Button.Icon:setIcon("/game_store/images/13/" .. category.icons[1])
            if category.icons[1] == "icon-store-home.png" then
                widget.Button.Icon:setIcon("/game_store/images/icon-store-home")
            else
                setImagenHttp(widget.Button.Icon, "/13/" .. category.icons[1], true)
            end

            widget.Button.Title:setText(category.name)
            widget.open = category.name

            if #category.subCategories > 0 then
                widget.subCategories = category.subCategories
                widget.subCategoriesSize = #category.subCategories
                widget.Button.Arrow:setVisible(true)

                for subId, subButton in ipairs(category.subCategories) do
                    local subWidget = createSubWidget(widget, subId, {
                        text = subButton.name,
                        icon = "/13/" .. subButton.icons[1],
                        open = subButton.name
                    })
                end
            end

            widget:setMarginTop(10)

            widget.Button.onClick = function()
                disableAllButtons()
                local parent = widget
                local oldOpen = controllerShop.ui.openedCategory
                local panel = controllerShop.ui.panelItem
                local btnBuy = panel:getChildById('btnBuy')
                local image = panel:getChildById('image')
                local lblPrice = panel:getChildById('lblPrice')
                local btnBuy = panel:getChildById('StackOffers')

                image:setImageSource("")
                btnBuy:destroyChildren()

                local firstChild = image:getFirstChild()
                if image:getChildCount() ~= 0 and firstChild then
                    local styleClass = firstChild:getStyle().__class
                    if styleClass == "UIItem" then
                        firstChild:setItemId(nil)
                    elseif styleClass == "UICreature" then
                        firstChild:setOutfit({
                            type = nil
                        })
                    else
                        firstChild:setImageSource("")
                    end
                end

                if oldOpen and oldOpen ~= parent then
                    if oldOpen.Button then
                        oldOpen.Button:setChecked(false)
                        oldOpen.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-down")
                    end
                    close(oldOpen)
                end

                if parent.subCategoriesSize then
                    parent.closedSize = parent.closedSize or 22
                    parent.openedSize = parent.openedSize or (22 + parent.subCategoriesSize * 21)

                    open(parent)

                else
                    widget.Button:setChecked(true)
                end

                widget.Button.Arrow:setImageSource("/images/ui/icon-arrow7x7-right")
                widget.Button.Arrow:setVisible(true)

                if controllerShop.ui.selectedOption then
                    controllerShop.ui.selectedOption:hide()
                end
                if category.name == "Home" then
                    controllerShop.ui.HomePanel.HomeRecentlyAdded.HomeProductos:destroyChildren()
                    g_game.sendRequestStoreHome()
                else
                    g_game.requestStoreOffers(category.name,"", 0, 1)
                end
                controllerShop.ui.openedCategory = parent
            end
        end
        local firstCategory = controllerShop.ui.listCategory:getChildByIndex(1)
        if controllerShop.ui.openedCategory == nil and firstCategory then
            controllerShop.ui.openedCategory = firstCategory
            firstCategory.Button:onClick()
        end

end

function onParseStoreError(errorMessage)
    destroyWindow(processingWindow)
    displayErrorBox(controllerShop.ui:getText(), errorMessage)
end

-- /*=============================================
-- =            buttons                          =
-- =============================================*/

function hide()
    if not controllerShop.ui then
        return
    end
    if controllerShop.ui.SearchEdit then
        controllerShop.ui.SearchEdit:setText('')
    end
    controllerShop.ui:hide()
end

function openCatalogOffer(categoryHint, query)
    if not controllerShop.ui then
        return
    end
    show()
    local q = tostring(query or ''):trim()
    if controllerShop.ui.SearchEdit then
        controllerShop.ui.SearchEdit:setText(q)
    end
    controllerShop:scheduleEvent(function()
        if not controllerShop.ui or not controllerShop.ui:isVisible() then
            return
        end
        if q ~= '' then
            if controllerShop.ui.openedCategory ~= nil then
                close(controllerShop.ui.openedCategory)
            end
            g_game.sendRequestStoreSearch(q, 0, 1)
        elseif categoryHint and categoryHint ~= '' then
            g_game.requestStoreOffers(categoryHint, '', 0, 1)
        end
    end, 220)
end

function toggle()
    if not controllerShop.ui then
        return
    end

    if controllerShop.ui:isVisible() then
        return hide()
    end
    show()
end

function show()
    if not controllerShop.ui then
        return
    end

    controllerShop.ui:show()
    controllerShop.ui:raise()
    controllerShop.ui:focus()

    if g_game.isOnline() then
        g_game.openStore()
        controllerShop:scheduleEvent(function()
            if controllerShop.ui and controllerShop.ui:isVisible() and controllerShop.ui.listCategory:getChildCount() == 0 then
                g_game.sendRequestStoreHome() -- fix 13.10
                local packet1 = GameStore.RecivedPackets.C_OpenStore
                g_logger.warning(string.format("[game_store BUG] Check 0x%X (%d) L827", packet1, packet1))
            end
        end, 1000, function() return 'serverNoSendPackets0xF20xFA' end)
    end
end



function getUI()
    return controllerShop.ui
end

function getCoinsWebsite()
    if GameStore.website.WEBSITE_GETCOINS ~= "" then
        g_platform.openUrl(GameStore.website.WEBSITE_GETCOINS)
    else
        sendMessageBox("Error", "No data for store URL.")
    end
end
-- /*=============================================
-- =            History                         =
-- =============================================*/

function toggleTransferHistory()
    if controllerShop.ui.transferHistory:isVisible() then
        if controllerShop.ui.openedCategory and controllerShop.ui.openedCategory:getId() == "Home" then
            showPanel("HomePanel")
        else
            showPanel("panelItem")
        end
    else
        g_game.requestTransactionHistory()
    end
end

function requestTransactionHistory(widget)
    local currentPage, pageCount = getPageLabelHistory()
    local newPage = currentPage + (widget:getId() == "btnNextPage" and 1 or -1)
    
    if newPage > 0 and newPage <= pageCount then
        g_game.requestTransactionHistory(newPage - 1)
    end
end

-- /*=============================================
-- =            focusedChild                     =
-- =============================================*/

function chooseOffert(self, focusedChild)
    if not focusedChild then
        return
    end

    local product = focusedChild.product
    local panel = controllerShop.ui.panelItem
    panel:getChildById('lblName'):setText(product.name)
    local description = product.description or ""
    local subOffers = product.subOffers or {}
    if not table.empty(subOffers) then
        local descriptionInfo = offerDescriptions[subOffers[1].id]
        if descriptionInfo and descriptionInfo.description and descriptionInfo.description ~= "" then
            description = descriptionInfo.description
        end
    end

    renderDescription(panel, description)

    local data = getProductData(product)
    local imagePanel = panel:getChildById('image')
    imagePanel:destroyChildren()
    if data then
        createProductImage(imagePanel, data)
    end
    fixServerNoSend0xF2()

    -- example use getCoinsBalance
    local normalCoins, transferableCoins = getCoinsBalance()
    local offerStackPanel = panel:getChildById('StackOffers')
    offerStackPanel:destroyChildren()

    local offers = not table.empty(subOffers) and subOffers or { product }
    for _, offer in ipairs(offers) do
        local offerPanel = g_ui.createWidget('OfferPanel2', offerStackPanel)

        local priceLabel = offerPanel:getChildById('lblPrice')
        priceLabel:setText(offer.price)

        local itemCount = (offer.count and offer.count > 0) and offer.count or 1
        if itemCount > 1 then
            offerPanel:getChildById('btnBuy'):setText("Buy " .. itemCount .. "x")
        end

        if product.configurable then
            offerPanel:getChildById('btnBuy'):setText("Configurable")
        end

        local isTransferable = offer.coinType == GameStore.CoinType.Transferable
        local currentBalance = isTransferable and transferableCoins or (normalCoins + transferableCoins)

        if isTransferable then
            priceLabel:setIcon("/game_store/images/icon-tibiacointransferable")
        else
            priceLabel:setIcon("/images/ui/tibiaCoin")
        end

        if currentBalance < offer.price then
            priceLabel:setColor("#d33c3c")
            offerPanel:getChildById('btnBuy'):disable()
        else
            priceLabel:setColor("white")
            offerPanel:getChildById('btnBuy'):enable()
        end

        if offer.disabled then
            local btnBuy = offerPanel:getChildById('btnBuy')
            btnBuy:disable()
            btnBuy:setOpacity(0.8)
            renderDescription(panel, description,
                "The product is currently not available for this character. See the buy button tooltip for details.")
            if offer.reasonIdDisable then
                local tooltipOverlay = g_ui.createWidget('UIWidget', offerPanel)
                tooltipOverlay:setId('tooltipOverlay')
                tooltipOverlay:setFocusable(false)
                tooltipOverlay:setSize(btnBuy:getSize())
                tooltipOverlay:setPosition(btnBuy:getPosition())
                local reasonText = (oldProtocol and offer.reasonIdDisable or reasonCategory[(offer.reasonIdDisable or 0) + 1]) or "Unavailable for this character."
                tooltipOverlay:parseColoreDisplayToolTip(string.format(
                    "[color=#ff0000]The product is not available for this character:\n\n- %s[/color]",
                    reasonText
                ))
                tooltipOverlay:setOpacity(0)
                tooltipOverlay:addAnchor(AnchorLeft, btnBuy:getId(), AnchorLeft)
                tooltipOverlay:addAnchor(AnchorTop, btnBuy:getId(), AnchorTop)
            end
        end

        -- 👇 Confirmação corrigida
        offerPanel:getChildById('btnBuy').onClick = function(widget)
            if acceptWindow then
                destroyWindow(acceptWindow)
            end

            if product.configurable or product.name == "Character Name Change" then
                return displayChangeName(offer, product)
            end

            if product.name == "Hireling Apprentice" then
                return displayErrorBox(controllerShop.ui:getText(), "not yet, UI missing")
            end

            local function acceptFunc()
                fixServerNoSend0xF2()
                local latestNormal, latestTransferable = getCoinsBalance()
                local latestCurrentBalance = isTransferable and latestTransferable or (latestNormal + latestTransferable)

                if latestCurrentBalance >= offer.price then
                    g_game.buyStoreOffer(offer.id, GameStore.ClientOfferTypes.CLIENT_STORE_OFFER_OTHER)
                    local closeWindow = function() destroyWindow(processingWindow) end
                    controllerShop.ui:hide()
                    processingWindow = displayGeneralBox(
                        'Processing purchase.', 
                        'Your purchase is being processed',
                        {
                          { text = tr('ok'),  callback = closeWindow },
                          anchor = 50
                        }, 
                        closeWindow, 
                        closeWindow
                    )
                else
                    displayErrorBox(controllerShop.ui:getText(), tr("You don't have enough coins"))
                end
                destroyWindow(acceptWindow)
            end

            local function cancelFunc()
                destroyWindow(acceptWindow)
            end

            local coinType = isTransferable and "transferable coins" or "regular coins"
            local confirmationMessage = string.format(
                'Do you want to buy the product "%s" for %d %s?', 
                product.name, 
                offer.price, 
                coinType
            )

            local itemCountConfirm = (offer.count and offer.count > 0) and offer.count or 1
            local detailsMessage = string.format(
                "%dx %s\nPrice: %d %s",
                itemCountConfirm,
                product.name,
                offer.price,
                coinType
            )

            acceptWindow = displayGeneralSHOPBox(
                tr('Confirmation of Purchase'),
                confirmationMessage,
                detailsMessage,
                {
                    { text = tr('Buy'), callback = acceptFunc },
                    { text = tr('Cancel'), callback = cancelFunc },
                    anchor = AnchorHorizontalCenter
                },
                acceptFunc,
                cancelFunc
            )
            if data then
                createProductImage(acceptWindow.Box, data)
            end
        end
    end
end


-- /*=============================================
-- =            Home                             =
-- =============================================*/

function chooseHome(self, focusedChild)
    if not focusedChild then
        return
    end
    local product = focusedChild.product
    local panel = controllerShop.ui.HomePanel.HomeRecentlyAdded.HomeProductos
    g_game.sendRequestStoreOfferById(product.id)
end

function changeImagenHome(direction)
    if not bannersHome or #bannersHome == 0 then
        return
    end
    if direction == "nextImagen" then
        currentIndex = currentIndex + 1
        if currentIndex > #bannersHome then
            currentIndex = 1
        end
    elseif direction == "prevImagen" then
        currentIndex = currentIndex - 1
        if currentIndex < 1 then
            currentIndex = #bannersHome
        end
    end
    local currentBanner = bannersHome[currentIndex]
    local imagePath = currentBanner.image
    setImagenHttp(controllerShop.ui.HomePanel.HomeImagen, imagePath, false)
end

-- /*=============================================
-- =            Behavior  Change Name            =
-- =============================================*/

function displayChangeName(offer, product)
    controllerShop.ui:hide()
    destroyWindow(changeNameWindow)
    changeNameWindow = g_ui.displayUI('style/changename')
    changeNameWindow:show()
    local newName = changeNameWindow:getChildById('transferPointsText')
    newName:setText('')
    local function closeWindow()
        newName:setText('')
        changeNameWindow:setVisible(false)
    end
    changeNameWindow.closeButton.onClick = closeWindow
    changeNameWindow.buttonOk.onClick = function()
        local offerType = GameStore.ClientOfferTypes.CLIENT_STORE_OFFER_NAMECHANGE
        if product and (product.name == "Hireling Apprentice" or string.find(string.lower(product.name), "hireling")) then
            offerType = GameStore.ClientOfferTypes.CLIENT_STORE_OFFER_HIRELING
        end
        g_game.buyStoreOffer(offer.id, offerType, newName:getText())
        closeWindow()
    end
    changeNameWindow.onEscape = function()
        destroyWindow(changeNameWindow)
    end
end

-- /*=============================================
-- =            Button TransferPoints            =
-- =============================================*/

function transferPoints()
    destroyWindow(transferPointsWindow)
    transferPointsWindow = g_ui.displayUI('style/transferpoints')
    transferPointsWindow:show()

    local playerBalance = g_game.getLocalPlayer():getResourceBalance(ResourceTypes.COIN_TRANSFERRABLE)
    fixServerNoSend0xF2()

    local normalCoins, transferableCoins = getCoinsBalance()

    if playerBalance == 0 then
        playerBalance = transferableCoins -- temp fix canary 1340
    end

    transferPointsWindow.giftable:setText(formatNumberWithCommas(playerBalance))

    local initialValue, minimumValue = 0, 0
    if playerBalance >= 25 then
        initialValue = 25
        minimumValue = 25
    end

    transferPointsWindow.amountBar:setStep(25)
    transferPointsWindow.amountBar:setMinimum(minimumValue)
    local maxStep = math.floor(playerBalance / 25) * 25 -- coins multiple 25
    transferPointsWindow.amountBar:setMaximum(maxStep)
    transferPointsWindow.amountBar:setValue(initialValue)
    transferPointsWindow.amount:setText(formatNumberWithCommas(initialValue))

    local sliderButton = transferPointsWindow.amountBar:getChildById('sliderButton')
    if sliderButton then
        sliderButton:setEnabled(true)
        sliderButton:setVisible(true)
    end

    transferPointsWindow.onEscape = function()
        destroyWindow(transferPointsWindow)
    end

    local lastDisplayedValue = initialValue
    transferPointsWindow.amountBar.onValueChange = function(scrollbar, value)
        -- Round to the nearest multiple of 25
        local val = math.floor((value + 12) / 25) * 25
        
        -- Only update the display if the value has changed
        if val ~= lastDisplayedValue then
            lastDisplayedValue = val
            transferPointsWindow.amount:setText(formatNumberWithCommas(val))
        end
    end

    transferPointsWindow.closeButton.onClick = function()
        destroyWindow(transferPointsWindow)
    end

    transferPointsWindow.buttonOk.onClick = function()
        local receipient = transferPointsWindow.transferPointsText:getText():trim()
        local amount = transferPointsWindow.amountBar:getValue()

        if receipient:len() < 3 then
            return
        end
        if amount < 1 or playerBalance < amount then
            return
        end

        g_game.transferCoins(receipient, amount)
        destroyWindow(transferPointsWindow)
    end
end




-- /*=============================================
-- =            Search Button            =
-- =============================================*/

function search()
    if  controllerShop.ui.openedCategory ~= nil then
        close(controllerShop.ui.openedCategory)
    end
    g_game.sendRequestStoreSearch(controllerShop.ui.SearchEdit:getText(), 0, 1)
end
