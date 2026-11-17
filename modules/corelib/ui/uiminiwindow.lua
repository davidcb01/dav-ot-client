-- @docclass
UIMiniWindow = extends(UIWindow, 'UIMiniWindow')

local MINIWINDOWS_NS = 'char_miniwindows'
local MINIWINDOWS_LEGACY_NODE = 'CharMiniWindows'

local function getCharMiniWindows(char)
    if CharConfig then
        return CharConfig.getOrCreate(MINIWINDOWS_NS, char, MINIWINDOWS_LEGACY_NODE)
    end
    local settings = g_settings.getNode(MINIWINDOWS_LEGACY_NODE) or {}
    settings[char] = settings[char] or {}
    return settings[char]
end

local function flushMiniWindowSave()
    if CharConfig then
        CharConfig.flushNamespace(MINIWINDOWS_NS)
    else
        g_settings.save()
    end
end

local function scheduleMiniWindowSave()
    local char = g_game.getCharacterName()
    if CharConfig and char and #char > 0 then
        CharConfig.scheduleSave(MINIWINDOWS_NS, char, 250)
    else
        scheduleEvent(function() g_settings.save() end, 250)
    end
end

connect(g_game, {
    onGameEnd = flushMiniWindowSave
})
connect(g_app, {
    onExit = flushMiniWindowSave
})

function UIMiniWindow.create()
    local miniwindow = UIMiniWindow.internalCreate()
    miniwindow.UIMiniWindowContainer = true
    miniwindow:addSound(ESoundUI.SoundTypeClick, 2785)
    return miniwindow
end

function UIMiniWindow:open(dontSave)
    self:setVisible(true)
    local parent = self:getParent()
    if parent and parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:clampFloatingPosition()
        self:raise()
    end
    self:updateResizeBorders()
    if not dontSave then
        self:setSettings({
            closed = false
        })
    end
    signalcall(self.onOpen, self)
end

function UIMiniWindow:close(dontSave)
    if not self:isExplicitlyVisible() then
        return
    end
    self:setVisible(false)

    local parent = self:getParent()
    if parent and (parent:getId() == 'gameHorizontalRightPanel' or parent:getId() == 'gameHorizontalLeftPanel') then
        if modules.game_interface then
            local fallback = (parent:getId() == 'gameHorizontalLeftPanel')
                and modules.game_interface.getLeftPanel()
                or modules.game_interface.getRightPanel()
            if fallback then
                parent:removeChild(self)
                self:setWidth(176)
                fallback:addChild(self)
                self:saveParent(fallback)
            end
            if modules.game_interface.syncHorizontalPanels then
                modules.game_interface.syncHorizontalPanels()
            end
        end
    end

    if not dontSave then
        self:setSettings({
            closed = true
        })
    end

    signalcall(self.onClose, self)
end

function UIMiniWindow:minimize(dontSave)
    self:setOn(true)
    self:getChildById('contentsPanel'):hide()
    self:getChildById('miniwindowScrollBar'):hide()
    self:getChildById('bottomResizeBorder'):hide()
    self:getChildById('minimizeButton'):setOn(true)
    self.maximizedHeight = self:getHeight()
    self:setHeight(self.minimizedHeight)
    self:updateResizeBorders()

    -- Hide miniborder when minimizing
    local miniborder = self:recursiveGetChildById('miniborder')
    if miniborder then
        miniborder:setVisible(false)
    end

    if not dontSave then
        self:setSettings({
            minimized = true
        })
    end

    signalcall(self.onMinimize, self)
end

function UIMiniWindow:maximize(dontSave)
    self:setOn(false)
    self:getChildById('contentsPanel'):show()
    self:getChildById('miniwindowScrollBar'):show()
    self:getChildById('bottomResizeBorder'):show()
    self:getChildById('minimizeButton'):setOn(false)
    self:setHeight(self:getSettings('height') or self.maximizedHeight)
    self:updateResizeBorders()

    -- Show miniborder when maximizing
    local miniborder = self:recursiveGetChildById('miniborder')
    if miniborder then
        miniborder:setVisible(true)
    end

    if not dontSave then
        self:setSettings({
            minimized = false
        })
    end

    local parent = self:getParent()
    if parent and parent:getClassName() == 'UIMiniWindowContainer' then
        parent:fitAll(self)
    end

    signalcall(self.onMaximize, self)
end

function UIMiniWindow:setup()
    self:getChildById('closeButton').onClick = function()
        self:close()
    end

    self:getChildById('minimizeButton').onClick = function()
        if self:isOn() then
            self:maximize()
        else
            self:minimize()
        end
    end

    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton.onClick = function()
            if self:isDraggable() then
                self:lock()
            else
                self:unlock()
            end
        end
    end

    self:getChildById('miniwindowTopBar').onDoubleClick = function()
        if self:isOn() then
            self:maximize()
        else
            self:minimize()
        end
    end

    self:updateResizeBorders()
end

function UIMiniWindow:updateResizeBorders()
    local parent = self:getParent()
    local isFloating = parent and parent:getClassName() ~= 'UIMiniWindowContainer'
    local isMinimized = self:isOn()

    local bottomBorder = self:getChildById('bottomResizeBorder')
    if bottomBorder then
        local allowHeight = not self.resizeDisabled
        if isMinimized then
            bottomBorder:hide()
        else
            bottomBorder:show()
        end
        bottomBorder:setEnabled(allowHeight)
    end

    local rightBorder = self:getChildById('rightResizeBorder')
    if rightBorder then
        local allowWidth = isFloating and not isMinimized and not self.resizeDisabled
        rightBorder:setVisible(allowWidth)
        rightBorder:setEnabled(allowWidth)
    end
end

function UIMiniWindow:clampFloatingPosition()
    local parent = self:getParent()
    if not parent or parent:getClassName() == 'UIMiniWindowContainer' then
        return
    end
    local px, py = parent:getX(), parent:getY()
    local pw, ph = parent:getWidth(), parent:getHeight()
    if pw <= 0 or ph <= 0 then
        return
    end
    local w = math.min(self:getWidth(), pw)
    if w ~= self:getWidth() and w >= 130 then
        self:setWidth(w)
    end
    local h = self:getHeight()
    local pos = self:getPosition()
    local maxX = px + math.max(0, pw - self:getWidth())
    local maxY = py + math.max(0, ph - h)
    local nx = math.max(px, math.min(pos.x, maxX))
    local ny = math.max(py, math.min(pos.y, maxY))
    if nx ~= pos.x or ny ~= pos.y then
        self:setPosition({ x = nx, y = ny })
    end
end

function UIMiniWindow:setupOnStart(opts)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local oldParent = self:getParent()
    local newParentSet = false
    local charSettings = getCharMiniWindows(char)

    self._suppressGeometrySave = true

    local selfSettings = charSettings[self:getId()]
    if selfSettings then
        if selfSettings.parentId then
            local parent = rootWidget:recursiveGetChildById(selfSettings.parentId)
            if not parent and selfSettings.parentId == 'gameRootPanel' and modules.game_interface and modules.game_interface.getRootPanel then
                parent = modules.game_interface.getRootPanel()
            end

            if parent and parent:getClassName() == 'UIMiniWindowContainer' then
                local isHorizontal = (parent:getId() == 'gameHorizontalRightPanel' or parent:getId() == 'gameHorizontalLeftPanel')
                local willBeOpen = (not selfSettings.closed) or (opts and opts.ignoreClosed)
                if isHorizontal and willBeOpen and not parent:isOn() then
                    parent:setOn(true)
                    parent:setVisible(true)
                end
                if parent:isVisible() and selfSettings.index and parent:isOn() then
                    self.miniIndex = selfSettings.index
                    parent:scheduleInsert(self, selfSettings.index)
                    newParentSet = true
                elseif isHorizontal and willBeOpen then
                    parent:addChild(self)
                    newParentSet = true
                end
            elseif parent and not self.moveOnlyToMain then
                if oldParent and oldParent ~= parent then
                    oldParent:removeChild(self)
                end
                if self:getParent() ~= parent then
                    parent:addChild(self)
                end
                self:breakAnchors()
                if selfSettings.width and not self.resizeDisabled then
                    local savedW = tonumber(selfSettings.width)
                    if savedW and savedW >= 130 then
                        self:setWidth(savedW)
                    end
                end
                if selfSettings.position then
                    local pos = topoint(selfSettings.position)
                    if pos then
                        self:setPosition(pos)
                    end
                end
                newParentSet = true
            end
        end

        if selfSettings.height then
            local bottomBorder = self:getChildById('bottomResizeBorder')
            if not self.resizeDisabled and bottomBorder and (bottomBorder:getMinimum() ~= bottomBorder:getMaximum()) then
                self:setHeight(selfSettings.height)
                self.maximizedHeight = selfSettings.height
            elseif self:isOn() and not self.resizeDisabled then
                self:setHeight(selfSettings.height)
                self.maximizedHeight = selfSettings.height
            elseif not self.resizeDisabled then
                self:setHeight(selfSettings.height)
                self.maximizedHeight = selfSettings.height
            else
                self:eraseSettings({
                    height = true
                })
            end
        end

        if selfSettings.minimized then
            self:minimize(true)
        elseif self:isOn() then
            self:maximize(true)
        end

        if selfSettings.closed and not (opts and opts.ignoreClosed) then
            self:close(true)
        else
            self:open(true)
        end

        if selfSettings.locked then
            self:lock(true)
        else
            self:unlock(true)
        end
    else
        if self:getId() == "battleWindow" then
            self:open(true)
        end
    end

    local newParent = self:getParent()

    if not oldParent and not newParentSet then
        oldParent = modules.game_interface.getRightPanel()
        self:setParent(oldParent)
    end

    self.miniLoaded = true

    if self.save then
        if oldParent and oldParent:getClassName() == 'UIMiniWindowContainer' then
            addEvent(function()
                if oldParent and not oldParent:isDestroyed() then
                    oldParent:order()
                end
            end)
        end
        if newParent and newParent:getClassName() == 'UIMiniWindowContainer' and newParent ~= oldParent then
            addEvent(function()
                if newParent and not newParent:isDestroyed() then
                    newParent:order()
                end
            end)
        end
    end

    if newParent and newParent:getClassName() == 'UIMiniWindowContainer' then
        local isHorizontal = (newParent:getId() == 'gameHorizontalRightPanel' or newParent:getId() == 'gameHorizontalLeftPanel')
        local targetW = newParent:getWidth() - newParent:getPaddingLeft() - newParent:getPaddingRight()
        if targetW > 0 and not isHorizontal then
            self:setWidth(targetW)
        end
        self:fitOnParent()
        if isHorizontal and modules.game_interface and modules.game_interface.syncHorizontalPanels then
            addEvent(function()
                if modules.game_interface and modules.game_interface.syncHorizontalPanels then
                    modules.game_interface.syncHorizontalPanels()
                end
            end)
        end
    elseif newParent then
        addEvent(function()
            if self and not self:isDestroyed() then
                self:clampFloatingPosition()
                self:updateResizeBorders()
            end
        end)
    end

    if self:getId() == "botWindow" then
        local parent = self:getParent()
        local parentId = parent:getId()

        if parentId == "gameLeftPanel" or
            parentId == "gameLeftExtraPanel" or
            parentId == "gameRightExtraPanel" then
            if parent:isVisible() then
                parent:setWidth(190)
            end
        end
    end

    self:updateResizeBorders()
    self._suppressGeometrySave = false
end

function UIMiniWindow:onVisibilityChange(visible)
    self:fitOnParent()
end

function UIMiniWindow:onDragEnter(mousePos)
    local parent = self:getParent()
    if not parent then
        return false
    end

    self._draggingMiniWindow = true

    if parent:getClassName() == 'UIMiniWindowContainer' then
        self.oldParentDrag = parent
        self.oldParentDragIndex = parent:getChildIndex(self)
        local wasHorizontal = (parent:getId() == 'gameHorizontalRightPanel' or parent:getId() == 'gameHorizontalLeftPanel')
        local containerParent = (modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()) or parent:getParent() or rootWidget
        parent:removeChild(self)
        if wasHorizontal then
            self:setWidth(176)
            if modules.game_interface and modules.game_interface.syncHorizontalPanels then
                modules.game_interface.syncHorizontalPanels()
            end
        end
        containerParent:addChild(self)
        self:breakAnchors()
        self:raise()
        parent:saveChildren()
        self:updateResizeBorders()
    else
        self.oldParentDrag = nil
        self.oldParentDragIndex = nil
        self:raise()
    end

    local oldPos = self:getPosition()
    self.movingReference = {
        x = mousePos.x - oldPos.x,
        y = mousePos.y - oldPos.y
    }
    self:setPosition(oldPos)
    self.free = true
    return true
end

function UIMiniWindow:onDragLeave(droppedWidget, mousePos)
    if self.movedWidget then
        self.setMovedChildMargin(self.movedOldMargin or 0)
        self.movedWidget = nil
        self.setMovedChildMargin = nil
        self.movedOldMargin = nil
        self.movedIndex = nil
    end

    local currentParent = self:getParent()
    if (not currentParent or currentParent:getClassName() ~= 'UIMiniWindowContainer') and mousePos and modules.game_interface then
        local gi = modules.game_interface
        local candidateContainers = {
            gi.getHorizontalRightPanel and gi.getHorizontalRightPanel() or nil,
            gi.getHorizontalLeftPanel and gi.getHorizontalLeftPanel() or nil,
            gi.getRightPanel and gi.getRightPanel() or nil,
            gi.getRightExtraPanel and gi.getRightExtraPanel() or nil,
            gi.getRightExtraPanel2 and gi.getRightExtraPanel2() or nil,
            gi.getRightExtraPanel3 and gi.getRightExtraPanel3() or nil,
            gi.getLeftPanel and gi.getLeftPanel() or nil,
            gi.getLeftExtraPanel and gi.getLeftExtraPanel() or nil,
            gi.getLeftExtraPanel2 and gi.getLeftExtraPanel2() or nil,
            gi.getLeftExtraPanel3 and gi.getLeftExtraPanel3() or nil,
            gi.getMainRightPanel and gi.getMainRightPanel() or nil,
        }
        for _, container in ipairs(candidateContainers) do
            if container and container:isVisible() and container:containsPoint(mousePos) then
                container:onDrop(self, mousePos)
                break
            end
        end
    end

    -- Snap back only for moveOnlyToMain core panels in normal view mode; all other windows float freely
    currentParent = self:getParent()
    if self.oldParentDrag and (not currentParent or currentParent:getClassName() ~= 'UIMiniWindowContainer') then
        local isExtended = modules.game_interface and modules.game_interface.currentViewMode == 2
        if self.moveOnlyToMain and not isExtended then
            if currentParent then
                currentParent:removeChild(self)
            end
            local insertIdx = math.min(self.oldParentDragIndex or 1, self.oldParentDrag:getChildCount() + 1)
            self.oldParentDrag:insertChild(insertIdx, self)
            self.movedWidget = nil
        else
            self:clampFloatingPosition()
        end
    elseif currentParent and currentParent:getClassName() ~= 'UIMiniWindowContainer' then
        self:clampFloatingPosition()
    end

    self._draggingMiniWindow = false
    self.oldParentDrag = nil
    self.oldParentDragIndex = nil
    self:updateResizeBorders()
    self:saveParent(self:getParent())

    if modules.game_interface and modules.game_interface.syncHorizontalPanels then
        modules.game_interface.syncHorizontalPanels()
    elseif modules.game_mainpanel and modules.game_mainpanel.reloadMainPanelSizes then
        modules.game_mainpanel.reloadMainPanelSizes()
    end
    return true
end

function UIMiniWindow:onDragMove(mousePos, mouseMoved)
    local oldMousePosY = mousePos.y - mouseMoved.y
    local children = rootWidget:recursiveGetChildrenByMarginPos(mousePos)
    local overAnyWidget = false
    for i = 1, #children do
        local child = children[i]
        if child:getParent():getClassName() == 'UIMiniWindowContainer' then
            overAnyWidget = true

            local childCenterY = child:getY() + child:getHeight() / 2
            if child == self.movedWidget and mousePos.y < childCenterY and oldMousePosY < childCenterY then
                break
            end

            if self.movedWidget then
                self.setMovedChildMargin(self.movedOldMargin or 0)
                self.setMovedChildMargin = nil
            end

            if mousePos.y < childCenterY then
                self.movedOldMargin = child:getMarginTop()
                self.setMovedChildMargin = function(v)
                    child:setMarginTop(v)
                end
                self.movedIndex = 0
            else
                self.movedOldMargin = child:getMarginBottom()
                self.setMovedChildMargin = function(v)
                    child:setMarginBottom(v)
                end
                self.movedIndex = 1
            end

            self.movedWidget = child
            self.setMovedChildMargin(self:getHeight())
            break
        end
    end

    if not overAnyWidget and self.movedWidget then
        self.setMovedChildMargin(self.movedOldMargin or 0)
        self.movedWidget = nil
    end

    return UIWindow.onDragMove(self, mousePos, mouseMoved)
end

function UIMiniWindow:onMousePress()
    local parent = self:getParent()
    if not parent then
        return false
    end
    if parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:raise()
        return true
    end
end

function UIMiniWindow:onFocusChange(focused)
    if not focused then
        return
    end
    local parent = self:getParent()
    if parent and parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:raise()
    end
end

function UIMiniWindow:onHeightChange(height)
    if self._inHeightChange then
        return
    end
    self._inHeightChange = true
    if self:getId() == 'mainmappanel' and height > 0 then
        self.panelHeight = height
    end
    if not self:isOn() then
        self:setSettings({
            height = height
        })
    end
    self:fitOnParent()
    local parent = self:getParent()
    if parent and (parent:getId() == 'gameHorizontalRightPanel' or parent:getId() == 'gameHorizontalLeftPanel') then
        if modules.game_interface and modules.game_interface.syncHorizontalPanels then
            modules.game_interface.syncHorizontalPanels()
        end
    end
    self._inHeightChange = false
end

function UIMiniWindow:getSettings(name)
    if not self.save then
        return nil
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return nil
    end

    local charSettings = getCharMiniWindows(char)
    if charSettings then
        local selfSettings = charSettings[self:getId()]
        if selfSettings then
            return selfSettings[name]
        end
    end

    return nil
end

function UIMiniWindow:setSettings(data)
    if not self.save then
        return
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local charSettings = getCharMiniWindows(char)

    local id = self:getId()
    if not charSettings[id] then
        charSettings[id] = {}
    end

    for key, value in pairs(data) do
        charSettings[id][key] = value
    end

    scheduleMiniWindowSave()
end

function UIMiniWindow:eraseSettings(data)
    if not self.save then
        return
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local charSettings = getCharMiniWindows(char)

    local id = self:getId()
    if not charSettings[id] then
        charSettings[id] = {}
    end

    for key, value in pairs(data) do
        charSettings[id][key] = nil
    end

    scheduleMiniWindowSave()
end

function UIMiniWindow:saveParent(parent)
    local parent = self:getParent()
    if parent then
        if parent:getClassName() == 'UIMiniWindowContainer' then
            parent:saveChildren()
        else
            self:saveParentPosition(parent:getId(), self:getPosition())
        end
    end
end

function UIMiniWindow:saveParentPosition(parentId, position)
    local selfSettings = {}
    selfSettings.parentId = parentId
    selfSettings.position = pointtostring(position)
    selfSettings.width = self:getWidth()
    if not self:isOn() then
        selfSettings.height = self:getHeight()
    end
    self:setSettings(selfSettings)
    self:eraseSettings({
        index = true
    })
end

function UIMiniWindow:saveParentIndex(parentId, index)
    local selfSettings = {}
    selfSettings.parentId = parentId
    selfSettings.index = index
    self:setSettings(selfSettings)
    self:eraseSettings({
        position = true,
        width = true
    })
    self.miniIndex = index
end

function UIMiniWindow:onGeometryChange(oldRect, newRect)
    if not self.miniLoaded or self._suppressGeometrySave or self._draggingMiniWindow or not self:isVisible() then
        return
    end
    local parent = self:getParent()
    if not parent or parent:getClassName() == 'UIMiniWindowContainer' then
        return
    end
    if not newRect then
        return
    end
    local update = {}
    local changed = false
    if (not oldRect or oldRect.width ~= newRect.width) and newRect.width > 0 then
        update.width = newRect.width
        changed = true
    end
    if (not oldRect or oldRect.height ~= newRect.height) and not self:isOn() and newRect.height > 0 then
        update.height = newRect.height
        changed = true
    end
    if changed then
        self:setSettings(update)
    end
end

function UIMiniWindow:disableResize()
    self.resizeDisabled = true
    self:updateResizeBorders()
end

function UIMiniWindow:enableResize()
    self.resizeDisabled = false
    self:updateResizeBorders()
end

function UIMiniWindow:fitOnParent()
    local parent = self:getParent()
    if self:isVisible() and parent and parent:getClassName() == 'UIMiniWindowContainer' then
        local isHorizontal = (parent:getId() == 'gameHorizontalRightPanel' or parent:getId() == 'gameHorizontalLeftPanel')
        if not isHorizontal then
            parent:fitAll(self)
        end
    end
end

function UIMiniWindow:setParent(parent, dontsave)
    UIWidget.setParent(self, parent)
    if not dontsave then
        self:saveParent(parent)
    end
    self:updateResizeBorders()
    self:fitOnParent()
end

function UIMiniWindow:setHeight(height)
    UIWidget.setHeight(self, height)
    signalcall(self.onHeightChange, self, height)
end

function UIMiniWindow:setContentHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setParentSize(minHeight + height)
end

function UIMiniWindow:setContentMinimumHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setMinimum(minHeight + height)
end

function UIMiniWindow:setContentMaximumHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setMaximum(minHeight + height)
end

function UIMiniWindow:getMinimumHeight()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    return resizeBorder and resizeBorder:getMinimum() or self:getHeight()
end

function UIMiniWindow:getMaximumHeight()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    return resizeBorder and resizeBorder:getMaximum() or self:getHeight()
end

function UIMiniWindow:modifyMaximumHeight(height)
    local resizeBorder = self:getChildById('bottomResizeBorder')
    local newHeight = resizeBorder:getMaximum() + height
    local curHeight = self:getHeight()
    resizeBorder:setMaximum(newHeight)
    if newHeight < curHeight or newHeight - height == curHeight then
        self:setHeight(newHeight)
    end
end

function UIMiniWindow:isResizeable()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    if not resizeBorder then
        return false
    end
    return not self:isOn() and resizeBorder:isEnabled() and (resizeBorder:getMinimum() ~= resizeBorder:getMaximum())
end

function UIMiniWindow:lock(dontSave)
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton:setOn(true)
    end
    self:setDraggable(false)
    self:setBorderWidth(1)
    self:setBorderColor('#d33c3c')
    if not dontSave then
        self:setSettings({
            locked = true
        })
    end

    signalcall(self.onLockChange, self)
end

function UIMiniWindow:unlock(dontSave)
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton:setOn(false)
    end
    self:setDraggable(true)
    self:setBorderWidth(0)
    if not dontSave then
        self:setSettings({
            locked = false
        })
    end
    signalcall(self.onLockChange, self)
end
