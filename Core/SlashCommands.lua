------------------------------------------------------------------------
-- Vault of Truths - Core/SlashCommands.lua
-- Slash command router for /gf
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.SlashCommands = {}
local SC = GF.SlashCommands

-- Command registry: [command] = { handler, description, guildOnly }
local commands = {}

local GUILD_ONLY_MSG = "|cFF33AAFF[Vault of Truths]|r That command requires guild membership."

--- Register a slash subcommand
---@param cmd string Command name (lowercase)
---@param handler function Handler function(args)
---@param description string Help text
---@param guildOnly boolean|nil If true, command requires guild membership
function SC:Register(cmd, handler, description, guildOnly)
    commands[cmd:lower()] = { handler = handler, desc = description, guildOnly = guildOnly }
end

--- Process a slash command input
---@param input string Raw input after /gf
local function HandleSlashCommand(input)
    local cmd, args = input:match("^(%S+)%s*(.*)")
    if not cmd then
        -- No subcommand: open main UI or show help
        if GF.UI and GF.UI.MainFrame and GF.UI.MainFrame.Toggle then
            GF.UI.MainFrame:Toggle()
        else
            SC:ShowHelp()
        end
        return
    end

    cmd = cmd:lower()
    local entry = commands[cmd]
    if entry then
        if entry.guildOnly and not IsInGuild() then
            print(GUILD_ONLY_MSG)
            return
        end
        entry.handler(args)
    else
        print("|cFF33AAFF[Vault of Truths]|r Unknown command: " .. cmd)
        SC:ShowHelp()
    end
end

--- Display available commands
function SC:ShowHelp()
    if IsInGuild() then
        print("|cFF33AAFF[Vault of Truths]|r v" .. GF.VERSION .. " — PVP Guild Economy")
        print("  Track PVP contributions, manage crafting orders, split AH profits.")
    else
        print("|cFF33AAFF[Vault of Truths]|r v" .. GF.VERSION .. " — Crafting Orders")
        print("  Browse guild crafters and request PVP crafts. Auto-connects to nearby guilds.")
    end
    print("  |cFFFFFF00/vot|r — Open main window")
    -- Sort commands alphabetically
    local sorted = {}
    for cmd in pairs(commands) do
        sorted[#sorted + 1] = cmd
    end
    table.sort(sorted)
    local inGuild = IsInGuild()
    for _, cmd in ipairs(sorted) do
        if not commands[cmd].guildOnly or inGuild then
            print("  |cFFFFFF00/vot " .. cmd .. "|r — " .. commands[cmd].desc)
        end
    end
end

-- Register slash commands
SLASH_VAULTOFTRUTHS1 = "/vot"
SLASH_VAULTOFTRUTHS2 = "/vault"
SLASH_VAULTOFTRUTHS3 = "/vaultoftruths"
SlashCmdList["VAULTOFTRUTHS"] = HandleSlashCommand

-- Built-in commands
SC:Register("help", function()
    SC:ShowHelp()
end, "Show this help message")

SC:Register("version", function()
    print("|cFF33AAFF[Vault of Truths]|r Version " .. GF.VERSION)
end, "Show addon version")

SC:Register("debug", function(args)
    if args == "errors" then
        -- Future: dump error log
        print("|cFF33AAFF[Vault of Truths]|r Error log not yet implemented.")
        return
    end

    GF.debug = not GF.debug
    VaultOfTruthsDB.settings.debugMode = GF.debug
    if GF.debug then
        print("|cFF33AAFF[Vault of Truths]|r Debug mode |cFF00FF00ON|r")
    else
        print("|cFF33AAFF[Vault of Truths]|r Debug mode |cFFFF0000OFF|r")
    end
end, "Toggle debug mode (or 'debug errors' for error log)")

SC:Register("guildlink", function()
    if not IsInGuild() then
        print("|cFF33AAFF[Vault of Truths]|r You must be in a guild.")
        return
    end

    local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not clubId then
        print("|cFF33AAFF[Vault of Truths]|r Could not find guild club ID.")
        return
    end

    -- Request the recruitment posting info
    if C_ClubFinder and C_ClubFinder.RequestPostingInformationFromClubId then
        C_ClubFinder.RequestPostingInformationFromClubId(clubId)
    end

    -- The link may be available immediately or after a short delay
    C_Timer.After(1, function()
        local link
        if C_ClubFinder and C_ClubFinder.GetRecruitmentChatLink then
            link = C_ClubFinder.GetRecruitmentChatLink()
        end

        if link and link ~= "" then
            -- Print the link so the user can copy it
            print("|cFF33AAFF[Vault of Truths]|r Guild link: " .. link)
            print("|cFF33AAFF[Vault of Truths]|r Shift-click the link above to paste it into chat.")

            -- Also try to put it in the chat box for easy sharing
            local editBox = GetCurrentKeyBoardFocus()
            if editBox then
                editBox:Insert(link)
            end
        else
            print("|cFF33AAFF[Vault of Truths]|r Could not generate guild link.")
            print("|cFF33AAFF[Vault of Truths]|r Your guild needs a recruitment posting in the Guild Finder.")
            print("|cFF33AAFF[Vault of Truths]|r Open Guild & Communities (J) > Recruitment tab > Post a listing first.")
        end
    end)
end, "Generate a shareable guild recruitment link", true)

SC:Register("invite", function(args)
    if not args or args == "" then
        print("|cFF33AAFF[Vault of Truths]|r Usage: /vot invite PlayerName-Realm")
        return
    end
    if not CanGuildInvite or not CanGuildInvite() then
        print("|cFF33AAFF[Vault of Truths]|r You don't have permission to invite to the guild.")
        return
    end
    GuildInvite(args)
    print("|cFF33AAFF[Vault of Truths]|r Guild invite sent to " .. args)
end, "Invite a player to the guild", true)

SC:Register("config", function()
    if GF.UI and GF.UI.SettingsPanel and GF.UI.SettingsPanel.Show then
        GF.UI.SettingsPanel:Show()
    else
        print("|cFF33AAFF[Vault of Truths]|r Settings UI not yet loaded.")
    end
end, "Open settings panel")

SC:Register("status", function()
    print("|cFF33AAFF[Vault of Truths]|r Status:")
    print("  Guild: " .. (GetGuildInfo("player") or "Not in a guild"))
    print("  TSM: " .. (GF.TSM and GF.TSM:IsAvailable() and "|cFF00FF00Connected|r" or "|cFFFF0000Not detected|r"))
    print("  Debug: " .. (GF.debug and "ON" or "OFF"))

    if IsInGuild() then
        local guildData = GF.Settings:GetGuildData()
        if guildData then
            print("  Ledger entries: " .. #guildData.ledger.entries)
            print("  Crafting orders: " .. #guildData.orders)
            print("  Bank last scan: " .. (guildData.bankSnapshots.lastScan > 0 and GF.Utils:FormatRelativeTime(guildData.bankSnapshots.lastScan) or "Never"))
        end
    else
        -- Non-guildie: show external guild connections
        local names = GF.Settings:GetExternalGuildNames()
        if #names > 0 then
            for _, name in ipairs(names) do
                local extData = GF.Settings:GetExternalGuildData(name)
                local peerCount = GF.CommunityBridge:GetPeerCount(name)
                local crafterCount = 0
                for _ in pairs(extData.crafterRecipes or {}) do crafterCount = crafterCount + 1 end
                local lastSync = extData.lastSync > 0 and GF.Utils:FormatRelativeTime(extData.lastSync) or "Never"
                print("  |cFF00FF00" .. name .. "|r — " .. peerCount .. " online, " .. crafterCount .. " crafters cached, synced " .. lastSync)
            end
        else
            print("  No guilds discovered yet.")
        end
    end
end, "Show addon status")

SC:Register("role", function(args)
    local player, role = args:match("^(%S+)%s+(%S+)")
    if not player or not role then
        print("|cFF33AAFF[Vault of Truths]|r Usage: /vot role <player> <pvper|crafter|auctioneer|both>")
        return
    end
    -- Delegate to Roles module
    if GF.Roles and GF.Roles.AssignRole then
        GF.Roles:AssignRole(player, role)
    else
        print("|cFF33AAFF[Vault of Truths]|r Roles module not loaded.")
    end
end, "Assign a role to a guild member", true)

SC:Register("balance", function(args)
    if GF.Payouts and GF.Payouts.ShowBalance then
        local target = args ~= "" and args or nil
        GF.Payouts:ShowBalance(target)
    else
        print("|cFF33AAFF[Vault of Truths]|r Payouts module not loaded.")
    end
end, "Show your contribution balance (or /vot balance <player>)", true)

SC:Register("ledger", function()
    if GF.Ledger and GF.Ledger.PrintRecent then
        GF.Ledger:PrintRecent()
    else
        print("|cFF33AAFF[Vault of Truths]|r Ledger module not loaded.")
    end
end, "Print recent ledger entries to chat", true)

SC:Register("price", function(args)
    print("|cFF33AAFF[Vault of Truths]|r Running price check...")

    local itemID = tonumber(args)

    -- If no item ID given, try to get from cursor/tooltip
    if not itemID or itemID == 0 then
        local ok, _, link = pcall(GameTooltip.GetItem, GameTooltip)
        if ok and link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    if not itemID then
        print("|cFF33AAFF[Vault of Truths]|r Usage: /vot price 256559  (use item ID number)")
        return
    end

    local name = C_Item.GetItemInfo(itemID)
    print("|cFF33AAFF[Vault of Truths]|r Price check: " .. (name or "Item") .. " (ID: " .. itemID .. ")")

    if not TSM_API then
        print("  |cFFFF0000TSM_API not found. Is TSM installed and loaded?|r")
        return
    end

    -- Check what API functions exist
    print("  TSM_API type: " .. type(TSM_API))
    if type(TSM_API) == "table" then
        local funcs = {}
        for k in pairs(TSM_API) do funcs[#funcs + 1] = k end
        table.sort(funcs)
        print("  TSM_API functions: " .. table.concat(funcs, ", "))
    end

    -- Try GetCustomPriceValue
    if not TSM_API.GetCustomPriceValue then
        print("  |cFFFF0000GetCustomPriceValue not found in TSM_API|r")
        -- Try alternative: IsValid and ToItemString
        if TSM_API.ToItemString then
            print("  TSM_API.ToItemString exists")
        end
        if TSM_API.GetCustomPriceValue then
            print("  TSM_API.GetCustomPriceValue exists")
        end
        return
    end

    local itemString = "i:" .. itemID

    -- Also try TSM's own item string format
    local tsmItemString = itemString
    if TSM_API.ToItemString then
        local ok, converted = pcall(TSM_API.ToItemString, "item:" .. itemID)
        if ok and converted then
            tsmItemString = converted
            print("  TSM item string: " .. tsmItemString)
        end
    end

    -- Test all common TSM sources
    local sources = {
        "DBMinBuyout", "DBMarket", "DBHistorical",
        "DBRegionMarketAvg", "DBRegionMinBuyoutAvg", "DBRegionHistorical",
        "VendorSell", "Destroy",
        "first(DBMinBuyout, DBMarket)",
    }

    for _, src in ipairs(sources) do
        -- Try both item string formats
        local ok, val = pcall(TSM_API.GetCustomPriceValue, src, tsmItemString)
        if not ok then
            ok, val = pcall(TSM_API.GetCustomPriceValue, src, itemString)
        end
        if ok and val and val > 0 then
            print("  |cFFFFFF00" .. src .. "|r = " .. GF.Utils:FormatMoney(val))
        elseif ok then
            print("  |cFFFFFF00" .. src .. "|r = |cFF888888nil/0|r")
        else
            print("  |cFFFFFF00" .. src .. "|r = |cFFFF0000error: " .. tostring(val) .. "|r")
        end
    end

    -- Show current guild setting
    local current = GF.Settings:GetGuild("priceSource") or "first(DBMinBuyout, DBMarket)"
    print("  |cFF00AAFFGuild setting:|r " .. current)
    local ok3, val3 = pcall(TSM_API.GetCustomPriceValue, current, tsmItemString)
    if ok3 and val3 then
        print("  |cFF00FF00Result:|r " .. GF.Utils:FormatMoney(val3))
    else
        print("  |cFF00FF00Result:|r |cFFFF0000" .. tostring(val3 or "nil") .. "|r")
    end
end, "Look up TSM price for an item ID")

SC:Register("scan", function()
    if GF.Scanner and GF.Scanner.ForceScan then
        GF.Scanner:ForceScan()
    else
        print("|cFF33AAFF[Vault of Truths]|r Guild bank scanner not loaded.")
    end
end, "Force a guild bank scan (must have bank open)", true)

SC:Register("payouts", function()
    if GF.UI and GF.UI.OfficerPanel and GF.UI.OfficerPanel.ShowPayouts then
        GF.UI.OfficerPanel:ShowPayouts()
    else
        print("|cFF33AAFF[Vault of Truths]|r Officer panel not loaded.")
    end
end, "Open payout queue (officers only)", true)

SC:Register("export", function()
    if not GF.Utils:IsGuildMaster() then
        print("|cFF33AAFF[Vault of Truths]|r Export is restricted to the Guild Owner.")
        return
    end
    if GF.Ledger and GF.Ledger.ExportCSV then
        GF.Ledger:ExportCSV()
    else
        print("|cFF33AAFF[Vault of Truths]|r Export not yet implemented.")
    end
end, "Export ledger to CSV (Guild Owner only)", true)

SC:Register("queue", function()
    if GF.NPCHelper and GF.NPCHelper.Toggle then
        GF.NPCHelper:Toggle()
    else
        print("|cFF33AAFF[Vault of Truths]|r Craft queue not loaded.")
    end
end, "Pop out your craft queue")

SC:Register("cleanup", function()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then
        print("|cFF33AAFF[Vault of Truths]|r No guild data.")
        return
    end

    local removed = 0
    local cutoff = time() - (30 * 86400) -- 30 days

    -- Clean old ledger entries
    if guildData.ledger and guildData.ledger.entries then
        local kept = {}
        for _, entry in ipairs(guildData.ledger.entries) do
            if (entry.timestamp or 0) > cutoff then
                kept[#kept + 1] = entry
            else
                removed = removed + 1
            end
        end
        guildData.ledger.entries = kept
    end

    -- Clean old AH sales
    if guildData.ahSales then
        local kept = {}
        for _, sale in ipairs(guildData.ahSales) do
            if (sale.timestamp or 0) > cutoff or not sale.distributed then
                kept[#kept + 1] = sale
            else
                removed = removed + 1
            end
        end
        guildData.ahSales = kept
    end

    -- Clean old item trails
    if guildData.itemTrails then
        for id, trail in pairs(guildData.itemTrails) do
            if (trail.startedAt or 0) < cutoff and trail.status == "sold" then
                guildData.itemTrails[id] = nil
                removed = removed + 1
            end
        end
    end

    -- Clean old transaction log
    if guildData.transactionLog then
        local kept = {}
        for _, entry in ipairs(guildData.transactionLog) do
            if (entry.timestamp or 0) > cutoff then
                kept[#kept + 1] = entry
            else
                removed = removed + 1
            end
        end
        guildData.transactionLog = kept
    end

    -- Clean stale pending broadcasts
    if guildData._pendingBroadcasts then
        local kept = {}
        for _, pending in ipairs(guildData._pendingBroadcasts) do
            if (pending.savedAt or 0) > (time() - 86400) then
                kept[#kept + 1] = pending
            else
                removed = removed + 1
            end
        end
        guildData._pendingBroadcasts = kept
    end

    print("|cFF33AAFF[Vault of Truths]|r Cleanup complete: " .. removed .. " stale entries removed.")
end, "Remove old entries older than 30 days", true)

SC:Register("info", function()
    if GF.UI and GF.UI.GuildInfoPanel then
        GF.UI.GuildInfoPanel:Toggle()
    end
end, "Show guild economy info & how it works")

SC:Register("progress", function()
    if GF.UI and GF.UI.ProgressionPanel then
        GF.UI.ProgressionPanel:Toggle()
    end
end, "Show your track progression and rewards")

SC:Register("connect", function()
    print("|cFF33AAFF[Vault of Truths]|r Full addon features require guild membership.")
    print("|cFF33AAFF[Vault of Truths]|r Search for |cFFFFCC00Vault of Truths|r in Guild Finder (J) to apply.")
end, "Show discovered guilds (non-guild members)")

SC:Register("disconnect", function(args)
    if not args or args == "" then
        print("|cFF33AAFF[Vault of Truths]|r Usage: /vot disconnect <Guild Name>")
        return
    end
    GF.CommunityBridge:Disconnect(args)
end, "Stop syncing with an external guild")

SC:Register("repair", function()
    if not GF.Roles:IsAddonOfficer() then
        print("|cFFFF0000[Vault of Truths]|r Officers only.")
        return
    end
    GF.ItemTrail:RepairTrails()
end, "Officer: rebuild trail supplier links and fix FIFO credits", true)

SC:Register("redist", function()
    if not GF.Roles:IsAddonOfficer() then
        print("|cFFFF0000[Vault of Truths]|r Officers only.")
        return
    end
    GF.SalesLedger:RedistributeAll()
end, "Officer: re-distribute all sale profits (repairs broken distributions)", true)

SC:Register("test", function(args)
    if args == "bag" then
        -- Scan all bag items and check which are bankable
        print("|cFF33AAFF[VoT]|r Scanning bags for bankable items...")
        local found = 0
        for bag = 0, NUM_BAG_SLOTS + (NUM_REAGENTBAG_SLOTS or 0) do
            local numSlots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local inList = GF.PVPItems.items[info.itemID] and true or false
                    local bankable, reason = GF.PVPItems:CheckLootedItem(info.itemID, info.hyperlink)
                    if inList or bankable then
                        local name = C_Item.GetItemInfo(info.itemID) or "?"
                        print("  [" .. info.itemID .. "] " .. name ..
                            " | inList=" .. tostring(inList) ..
                            " | bankable=" .. tostring(bankable) ..
                            " | reason=" .. tostring(reason))
                        found = found + 1
                    end
                end
            end
        end
        if found == 0 then
            print("  No bankable items found in bags.")
        end
        print("|cFF33AAFF[VoT]|r Total tracked item IDs: " .. tostring(#{next(GF.PVPItems.items)} and #GF.PVPItems:GetAllItemIDs() or 0))
    elseif args == "check" then
        -- Check if specific heraldry IDs are in our list
        local testIDs = { 256559, 256607, 230285, 230286 }
        for _, id in ipairs(testIDs) do
            local name = C_Item.GetItemInfo(id) or "uncached"
            local inList = GF.PVPItems.items[id] and true or false
            print("  [" .. id .. "] " .. name .. " | inList=" .. tostring(inList))
        end
    else
        print("|cFF33AAFF[VoT]|r Test commands:")
        print("  /vot test bag — scan bags for bankable items")
        print("  /vot test check — verify heraldry IDs in list")
    end
end, "Debug: test item detection")
