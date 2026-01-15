--
-- Copyright (c) 2024 outdead.
-- Use of this source code is governed by the Apache 2.0 license.
--
-- Version: 1.0.1


local SafehouseClientLogger = {}

local function isLogExtenderEnabled(option)
    return type(SandboxVars) == "table" and type(SandboxVars.LogExtender) == "table" and SandboxVars.LogExtender[option]
end

local function trySet(target, key, value)
    if type(target) ~= "table" and type(target) ~= "userdata" then
        return
    end

    pcall(function()
        target[key] = value
    end)
end

local function addOnGameStart(handler)
    if type(Events) ~= "table" then
        return
    end

    local gameStart = Events.OnGameStart
    if type(gameStart) ~= "table" or type(gameStart.Add) ~= "function" then
        return
    end

    gameStart.Add(handler)
end

-- DumpSafehouse writes player's safehouse info to log file.
function SafehouseClientLogger.DumpSafehouse(player, action, safehouse, target)
    if player == nil then
        return nil;
    end

    local message = logutils.GetLogLinePrefix(player, action);

    if safehouse then
        local area = {}
        local owner = player:getUsername()
        if action == "create safehouse" then
            owner = target
            target = nil
        end

        if instanceof(safehouse, 'SafeHouse') then
            owner = safehouse:getOwner();
            area = {
                Top = safehouse:getX() .. "x" .. safehouse:getY(),
                Bottom = safehouse:getX2() .. "x" .. safehouse:getY2(),
                zone = safehouse:getX() .. "," .. safehouse:getY() .. "," .. safehouse:getX2() - safehouse:getX() .. "," .. safehouse:getY2() - safehouse:getY()
            };
        end

        message = message .. ' ' .. area.zone
        message = message .. ' owner="' .. owner .. '"'

        if action == "release safehouse" then
            message = message .. ' members=['

            local members = safehouse:getPlayers();
            for j = 0, members:size() - 1 do
                local member = members:get(j)

                if member ~= owner then
                    message = message .. '"' .. member .. '"'
                    if j ~= members:size() - 1 then
                        message = message .. ','
                    end
                end
            end
            message = message .. ']'
        end
    else
        message = message .. ' ' .. '0,0,0,0' -- TODO: What can I do?
        message = message .. ' owner="' .. player:getUsername() .. '"'
    end

    if target ~= nil then
        message = message .. ' target="' .. target .. '"'
    end

    logutils.WriteLog(logutils.filemask.safehouse, message);
end

-- OnTakeSafeHouse rewrites original ISWorldObjectContextMenu.onTakeSafeHouse and
-- adds logs for player take safehouse action.
SafehouseClientLogger.OnTakeSafeHouse = function()
    local target = ISWorldObjectContextMenu
    local original = target and target.onTakeSafeHouse
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(worldobjects, square, player)
        original(worldobjects, square, player)

        local character = getSpecificPlayer(player)
        local safehouse = nil

        local safehouseList = SafeHouse.getSafehouseList();
        -- TODO: If player owned 2 or more safehouses we can get not relevant house.
        for i = 0, safehouseList:size() - 1 do
            if safehouseList:get(i):getOwner() == character:getUsername() then
                safehouse = safehouseList:get(i);
                break;
            end
        end

        SafehouseClientLogger.DumpSafehouse(character, "take safehouse", safehouse, nil)
    end

    trySet(target, "onTakeSafeHouse", wrapped)
end

-- OnChangeSafeHouseOwner rewrites original ISSafehouseAddPlayerUI.onClick and
-- adds logs for change safehouse ownership action.
SafehouseClientLogger.OnChangeSafeHouseOwner = function()
    local target = ISSafehouseAddPlayerUI
    local original = target and target.onClick
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self, button)
        local owner = self.safehouse:getOwner()

        original(self, button)

        if button.internal == "ADDPLAYER" then
            local character = getPlayer()

            if self.changeOwnership then
                SafehouseClientLogger.DumpSafehouse(character, "change safehouse owner", self.safehouse, self.selectedPlayer)
            else
                SafehouseClientLogger.DumpSafehouse(character, "add player to safehouse", self.safehouse, self.selectedPlayer)
            end

            if owner ~= character:getUsername() then
                local message = character:getUsername() .. " change safehouse " .. logutils.GetSafehouseShrotNotation(self.safehouse)
                        .. " at " .. logutils.GetLocation(character)
                logutils.WriteLog(logutils.filemask.admin, message);
            end
        end
    end

    trySet(target, "onClick", wrapped)
end

-- OnReleaseSafeHouse rewrites original ISSafehouseUI.onReleaseSafehouse and
-- adds logs for player release safehouse action.
SafehouseClientLogger.OnReleaseSafeHouse = function()
    local target = ISSafehouseUI
    local original = target and target.onReleaseSafehouse
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self, button, player)
        local owner = button.parent.ui.safehouse:getOwner()

        if button.internal == "YES" then
            if button.parent.ui:isOwner() or button.parent.ui:hasPrivilegedAccessLevel() then
                local character = getPlayer()
                SafehouseClientLogger.DumpSafehouse(character, "release safehouse", button.parent.ui.safehouse, nil)

                if owner ~= character:getUsername() then
                    local message = character:getUsername() .. " release safehouse " .. logutils.GetSafehouseShrotNotation(button.parent.ui.safehouse)
                            .. " at " .. logutils.GetLocation(character)
                    logutils.WriteLog(logutils.filemask.admin, message);
                end
            end
        end

        original(self, button, player)
    end

    trySet(target, "onReleaseSafehouse", wrapped)
end

-- OnReleaseSafeHouseCommand rewrites original ISChat.onCommandEntered and
-- adds logs for player release safehouse action.
SafehouseClientLogger.OnReleaseSafeHouseCommand = function()
    local target = ISChat
    local original = target and target.onCommandEntered
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self)
        local command = ISChat.instance.textEntry:getText();
        if command == "/releasesafehouse" then
            local character = getSpecificPlayer(0)
            local safehouse = nil

            local safehouseList = SafeHouse.getSafehouseList();
            -- TODO: If player owned 2 or more safehouses we can get not relevant house.
            for i = 0, safehouseList:size() - 1 do
                if safehouseList:get(i):getOwner() == character:getUsername() then
                    safehouse = safehouseList:get(i);
                    break;
                end
            end

            SafehouseClientLogger.DumpSafehouse(character, "release safehouse", safehouse, nil)
        end

        original(self)
    end

    trySet(target, "onCommandEntered", wrapped)
end

-- OnRemovePlayerFromSafehouse rewrites original ISSafehouseUI.onRemovePlayerFromSafehouse
-- and adds logs for remove player from safehouse action.
SafehouseClientLogger.OnRemovePlayerFromSafehouse = function()
    local target = ISSafehouseUI
    local original = target and target.onRemovePlayerFromSafehouse
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self, button, player)
        if button.internal == "YES" then
            local character = getPlayer()
            SafehouseClientLogger.DumpSafehouse(character, "remove player from safehouse", button.parent.ui.safehouse, button.parent.ui.selectedPlayer)
        end

        original(self, button, player)
    end

    trySet(target, "onRemovePlayerFromSafehouse", wrapped)
end

-- OnSendSafeHouseInvite rewrites original ISSafehouseAddPlayerUI.onClick and
-- adds logs for send safehouse invite action.
SafehouseClientLogger.OnSendSafeHouseInvite = function()
    local target = ISSafehouseAddPlayerUI
    local original = target and target.onClick
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self, button)
        original(self, button)

        if button.internal == "ADDPLAYER" then
            if not self.changeOwnership then
                local character = getPlayer()
                SafehouseClientLogger.DumpSafehouse(character, "send safehouse invite", self.safehouse, self.selectedPlayer)
            end
        end
    end

    trySet(target, "onClick", wrapped)
end

-- OnJoinToSafehouse rewrites original ISSafehouseUI.onAnswerSafehouseInvite and
-- adds logs for players join to safehouse action.
SafehouseClientLogger.OnJoinToSafehouse = function()
    local target = ISSafehouseUI
    local original = target and target.onAnswerSafehouseInvite
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self, button)
        if button.internal == "YES" then
            local character = getPlayer()
            SafehouseClientLogger.DumpSafehouse(character, "join to safehouse", button.parent.safehouse, nil)
        end

        original(self, button)
    end

    trySet(target, "onAnswerSafehouseInvite", wrapped)
end

--
-- Admin Tools
--

-- OnAddSafeHouse rewrites original ISWorldObjectContextMenu.onTakeSafeHouse and
-- adds logs for player take safehouse action.
SafehouseClientLogger.OnAddSafeHouse = function()
    local target = ISAddSafeZoneUI
    local original = target and target.onClick
    if type(original) ~= "function" then
        return
    end

    local wrapped = function(self, button)
        original(self, button)

        local setX = math.floor(math.min(self.X1, self.X2));
        local setY = math.floor(math.min(self.Y1, self.Y2));
        local setW = math.floor(math.abs(self.X1 - self.X2) + 1);
        local setH = math.floor(math.abs(self.Y1 - self.Y2) + 1);

        local character = getPlayer()
        local safehouse = nil

        local safehouseList = SafeHouse.getSafehouseList();
        for i = 0, safehouseList:size() - 1 do
            if safehouseList:get(i):getOwner() == self.ownerEntry:getInternalText() and safehouseList:get(i):getX() == setX and safehouseList:get(i):getY() == setY then
                safehouse = safehouseList:get(i);
                break;
            end
        end

        if isLogExtenderEnabled("TakeSafeHouse") then
            SafehouseClientLogger.DumpSafehouse(character, "create safehouse", safehouse, self.ownerEntry:getInternalText())
        end

        local message = character:getUsername() .. " create safehouse " .. tostring(setX) .. "," .. tostring(setY) .. "," .. tostring(setW) .. "," .. tostring(setH)
                .. " at " .. logutils.GetLocation(character)
        logutils.WriteLog(logutils.filemask.admin, message);
    end

    trySet(target, "onClick", wrapped)
end

local function onGameStart()
    if isLogExtenderEnabled("TakeSafeHouse") then
        SafehouseClientLogger.OnTakeSafeHouse()
    end

    if isLogExtenderEnabled("ChangeSafeHouseOwner") then
        SafehouseClientLogger.OnChangeSafeHouseOwner()
    end

    if isLogExtenderEnabled("ReleaseSafeHouse") then
        SafehouseClientLogger.OnReleaseSafeHouse()
    end

    if isLogExtenderEnabled("RemovePlayerFromSafehouse") then
        SafehouseClientLogger.OnRemovePlayerFromSafehouse()
    end

    if isLogExtenderEnabled("SendSafeHouseInvite") then
        SafehouseClientLogger.OnSendSafeHouseInvite()
    end

    if isLogExtenderEnabled("JoinToSafehouse") then
        SafehouseClientLogger.OnJoinToSafehouse()
    end

    if isLogExtenderEnabled("ReleaseSafeHouse") then
        SafehouseClientLogger.OnReleaseSafeHouseCommand()
    end

    if isLogExtenderEnabled("SafehouseAdminTools") then
        SafehouseClientLogger.OnAddSafeHouse()
    end
end

addOnGameStart(onGameStart);
