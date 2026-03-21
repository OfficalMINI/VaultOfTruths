------------------------------------------------------------------------
-- Vault of Truths - Core/Events.lua
-- Central event dispatcher using a hidden frame
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.Events = {}
local Events = GF.Events

-- Hidden frame for event registration
local eventFrame = CreateFrame("Frame")
local callbacks = {} -- [event] = { [id] = handler }
local nextID = 1

--- Register a callback for a WoW event
---@param event string WoW event name
---@param handler function Callback function(event, ...)
---@return number Registration ID for unregistering
function Events:Register(event, handler)
    if not callbacks[event] then
        callbacks[event] = {}
        eventFrame:RegisterEvent(event)
    end
    local id = nextID
    nextID = nextID + 1
    callbacks[event][id] = handler
    return id
end

--- Unregister a specific callback
---@param event string WoW event name
---@param id number Registration ID returned by Register
function Events:Unregister(event, id)
    if callbacks[event] then
        callbacks[event][id] = nil
        -- Unregister from frame if no more handlers
        if not next(callbacks[event]) then
            callbacks[event] = nil
            eventFrame:UnregisterEvent(event)
        end
    end
end

--- Fire all callbacks for a given event (with error protection)
local function DispatchEvent(event, ...)
    local handlers = callbacks[event]
    if not handlers then return end
    for id, handler in pairs(handlers) do
        local ok, err = xpcall(handler, geterrorhandler(), event, ...)
        if not ok then
            -- Log error but don't break other handlers
            if GF.debug then
                print("|cFFFF0000[Vault of Truths Error]|r " .. event .. " handler " .. id .. ": " .. tostring(err))
            end
        end
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    DispatchEvent(event, ...)
end)

-- Custom event system (for internal addon events, not WoW events)
local customCallbacks = {} -- [eventName] = { handler, ... }

--- Register a callback for a custom addon event
---@param event string Custom event name (e.g. "LEDGER_ENTRY_ADDED")
---@param handler function Callback function(...)
function Events:On(event, handler)
    if not customCallbacks[event] then
        customCallbacks[event] = {}
    end
    customCallbacks[event][#customCallbacks[event] + 1] = handler
end

--- Fire a custom addon event
---@param event string Custom event name
---@param ... any Arguments to pass to handlers
function Events:Fire(event, ...)
    local handlers = customCallbacks[event]
    if not handlers then return end
    for _, handler in ipairs(handlers) do
        local ok, err = xpcall(handler, geterrorhandler(), ...)
        if not ok and GF.debug then
            print("|cFFFF0000[Vault of Truths Error]|r Custom event " .. event .. ": " .. tostring(err))
        end
    end
end

-- Lifecycle: Initialize on ADDON_LOADED
Events:Register("ADDON_LOADED", function(event, addonName)
    if addonName ~= ADDON_NAME then return end

    -- Initialize settings (depends on SavedVariables being available)
    if GF.Settings and GF.Settings.Init then
        GF.Settings:Init()
    end

    -- Initialize all registered modules
    for name, module in pairs(GF.modules) do
        if module.Init then
            local ok, err = xpcall(module.Init, geterrorhandler(), module)
            if not ok then
                print("|cFFFF0000[Vault of Truths]|r Failed to init module '" .. name .. "': " .. tostring(err))
            end
        end
    end

    GF.Events:Fire("GF_ADDON_LOADED")

    if GF.debug then
        print("|cFF00FF00[Vault of Truths]|r v" .. GF.VERSION .. " loaded.")
    end
end)

-- Register addon message prefix for sync
Events:Register("PLAYER_LOGIN", function()
    C_ChatInfo.RegisterAddonMessagePrefix(GF.PREFIX)
    GF.Events:Fire("GF_PLAYER_LOGIN")

    if GF.debug then
        print("|cFF00FF00[Vault of Truths]|r Player login complete. Addon prefix registered.")
    end
end)

-- Detect guild membership changes (joining/leaving guild mid-session)
local wasInGuild = nil
Events:Register("PLAYER_GUILD_UPDATE", function()
    local inGuild = IsInGuild()
    -- Small delay — guild info isn't available immediately after PLAYER_GUILD_UPDATE
    C_Timer.After(2, function()
        local nowInGuild = IsInGuild()
        if nowInGuild and wasInGuild == false then
            -- Just joined a guild — re-fire login events so modules re-initialize
            GF.Events:Fire("GF_PLAYER_LOGIN")
            if GF.debug then
                print("|cFF00FF00[Vault of Truths]|r Guild joined — reinitializing.")
            end
        elseif not nowInGuild and wasInGuild == true then
            if GF.debug then
                print("|cFF00FF00[Vault of Truths]|r Left guild.")
            end
        end
        wasInGuild = nowInGuild
    end)
end)

-- Initialize wasInGuild on login
Events:Register("PLAYER_ENTERING_WORLD", function()
    wasInGuild = IsInGuild()
end)
