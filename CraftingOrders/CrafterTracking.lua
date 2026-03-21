------------------------------------------------------------------------
-- Vault of Truths - CraftingOrders/CrafterTracking.lua
-- Track assigned crafters, mat withdrawals, craft completion
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.CrafterTracking = {}
local CT = GF.CrafterTracking
GF:RegisterModule("CrafterTracking", CT)

-- Active mat allocations: [orderID] = { mats withdrawn, crafter, deadline }
local allocations = {}

-- Configurable deadline for craft completion after mat withdrawal (in seconds)
local DEFAULT_CRAFT_DEADLINE = 7 * 24 * 3600 -- 7 days

function CT:Init()
    -- Listen for guild bank withdrawals — record as debt with price-locked value
    GF.Events:On("GF_BANK_TRANSACTION", function(transaction)
        if transaction.type == "withdraw" then
            CT:RecordWithdrawalDebt(transaction)
            CT:CheckWithdrawalForOrder(transaction)
        elseif transaction.type == "deposit" then
            CT:CreditDeposit(transaction)
        end
    end)

    -- Check for overdue allocations on login
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(10, function()
            CT:CheckOverdueAllocations()
        end)
    end)

    -- Detect NPC crafting order completion
    -- CRAFTINGORDERS_FULFILL_ORDER_RESPONSE fires when you complete an order at the NPC
    GF.Events:Register("CRAFTINGORDERS_FULFILL_ORDER_RESPONSE", function(event, result, orderID)
        if result == Enum.CraftingOrderResult.Ok then
            CT:OnNPCOrderFulfilled(orderID)
        end
    end)

    -- TRADE_SKILL_ITEM_CRAFTED_RESULT fires after any craft completes
    GF.Events:Register("TRADE_SKILL_ITEM_CRAFTED_RESULT", function(event, resultData)
        if resultData and resultData.itemID then
            CT:OnItemCrafted(resultData)
        end
    end)
end

--- Link a guild bank withdrawal to a crafting order
---@param transaction table Bank transaction
function CT:CheckWithdrawalForOrder(transaction)
    if not transaction.player or not transaction.itemID then return end

    -- Find accepted orders assigned to this crafter that need this material
    local crafterOrders = GF.OrderBoard:GetCrafterOrders(transaction.player)

    for _, order in ipairs(crafterOrders) do
        if order.status == GF.ORDER_STATUS.ACCEPTED then
            -- Check if this item is a required mat for the order
            for _, mat in ipairs(order.mats or {}) do
                if mat.itemID == transaction.itemID then
                    -- Link withdrawal to order
                    self:RecordAllocation(order.id, transaction)

                    -- Log as craft withdrawal instead of regular withdrawal
                    -- Update the ledger entry action type
                    GF.ChatNotify:Info("Mat withdrawal linked to Order #" .. order.id ..
                        ": x" .. transaction.quantity .. " Item:" .. transaction.itemID)
                    return
                end
            end
        end
    end
end

--- Record a material allocation for an order
---@param orderID string
---@param transaction table Bank transaction
function CT:RecordAllocation(orderID, transaction)
    if not allocations[orderID] then
        allocations[orderID] = {
            crafter = transaction.player,
            withdrawals = {},
            startTime = GF.Utils:GetTime(),
            deadline = GF.Utils:GetTime() + DEFAULT_CRAFT_DEADLINE,
        }
    end

    local alloc = allocations[orderID]
    alloc.withdrawals[#alloc.withdrawals + 1] = {
        itemID = transaction.itemID,
        quantity = transaction.quantity,
        timestamp = GF.Utils:GetTime(),
    }

    -- Persist allocations in guild data
    self:SaveAllocations()

    GF.Events:Fire("GF_MAT_ALLOCATED", orderID, transaction)
end

--- Check for overdue mat allocations (officer alert)
function CT:CheckOverdueAllocations()
    if not GF.Roles:IsAddonOfficer() then return end

    local now = GF.Utils:GetTime()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.matAllocations then return end

    for orderID, alloc in pairs(guildData.matAllocations) do
        if alloc.deadline and now > alloc.deadline then
            local order = GF.OrderBoard:GetOrder(orderID)
            if order and order.status == GF.ORDER_STATUS.ACCEPTED then
                GF.ChatNotify:Warning("OVERDUE: Order #" .. orderID ..
                    " (" .. (order.recipeName or "Unknown") .. ") — Crafter: " ..
                    alloc.crafter .. " — Mats withdrawn " ..
                    GF.Utils:FormatRelativeTime(alloc.startTime))
            end
        end
    end
end

--- Get allocation info for an order
---@param orderID string
---@return table|nil allocation
function CT:GetAllocation(orderID)
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.matAllocations then return nil end
    return guildData.matAllocations[orderID]
end

--- Get all active allocations
---@return table { [orderID] = allocation }
function CT:GetActiveAllocations()
    local guildData = GF.Settings:GetGuildData()
    if not guildData or not guildData.matAllocations then return {} end
    return guildData.matAllocations
end

--- Save allocations to SavedVariables
function CT:SaveAllocations()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end
    guildData.matAllocations = allocations
end

--- Clear allocation when order is completed
---@param orderID string
function CT:ClearAllocation(orderID)
    allocations[orderID] = nil
    self:SaveAllocations()
end

-- Wire up: clear allocation on order completion
GF.Events:On("GF_ORDER_COMPLETED", function(order)
    CT:ClearAllocation(order.id)
end)

------------------------------------------------------------------------
-- NPC Craft Detection — match WoW crafting order completions to VoT orders
------------------------------------------------------------------------

--- Called when a crafting order is fulfilled via the NPC system
---@param npcOrderID number WoW's internal order ID
function CT:OnNPCOrderFulfilled(npcOrderID)
    local myName = GF.Utils:GetPlayerFullName()

    -- Get the fulfilled order info from WoW
    local orderInfo
    if C_CraftingOrders and C_CraftingOrders.GetClaimedOrder then
        orderInfo = C_CraftingOrders.GetClaimedOrder()
    end

    if not orderInfo then return end

    local craftedItemName = orderInfo.outputItemHyperlink
        and (orderInfo.outputItemHyperlink:match("%[(.-)%]") or nil)
    local customerName = orderInfo.customerName

    -- Try to match against open VoT orders assigned to us
    local matched = self:MatchVoTOrder(myName, craftedItemName, customerName)
    if matched then
        GF.ChatNotify:Success(
            "VoT order auto-detected! |cFF00AAFF" .. (matched.recipeName or "Order") ..
            "|r for " .. (customerName or "guild") ..
            " — marking complete."
        )
        GF.OrderBoard:CompleteOrder(matched.id)
    end
end

--- Called when any item is crafted (fallback detection)
---@param resultData table { itemID, itemLink, quantity, ... }
function CT:OnItemCrafted(resultData)
    local myName = GF.Utils:GetPlayerFullName()
    local itemID = resultData.itemID
    if not itemID then return end

    local itemName = resultData.hyperlink
        and (resultData.hyperlink:match("%[(.-)%]") or nil)

    -- Check if we have any accepted VoT orders that match this item
    local myOrders = GF.OrderBoard:GetCrafterOrders(myName)
    for _, order in ipairs(myOrders) do
        if order.status == GF.ORDER_STATUS.ACCEPTED then
            local isMatch = false

            -- Match by output item ID
            if order.outputItemID and order.outputItemID == itemID then
                isMatch = true
            end

            -- Match by recipe name
            if not isMatch and itemName and order.recipeName then
                if itemName:lower() == order.recipeName:lower() or
                   order.recipeName:lower():find(itemName:lower(), 1, true) then
                    isMatch = true
                end
            end

            if isMatch then
                -- Don't auto-complete — show a prompt instead
                local requester = order.requester
                    and (order.requester:match("^(.+)-") or order.requester) or "?"
                GF.ChatNotify:Info(
                    "You just crafted |cFF00AAFF" .. (order.recipeName or itemName or "an item") ..
                    "|r — this matches VoT order for |cFF00FF00" .. requester .. "|r"
                )
                GF.Toast:Show(
                    "VoT Order Match",
                    (order.recipeName or "Item") .. " for " .. requester,
                    "Interface\\Icons\\Trade_Engineering"
                )
                -- Fire event so UI can offer to complete it
                GF.Events:Fire("GF_CRAFT_MATCHED_ORDER", order, resultData)
                return -- Only match first order
            end
        end
    end
end

--- Try to match a fulfilled NPC order against VoT orders
---@param crafterName string Our player name
---@param craftedItemName string|nil Name of the crafted item
---@param customerName string|nil Name of the customer
---@return table|nil Matched VoT order
function CT:MatchVoTOrder(crafterName, craftedItemName, customerName)
    local myOrders = GF.OrderBoard:GetCrafterOrders(crafterName)

    for _, order in ipairs(myOrders) do
        if order.status == GF.ORDER_STATUS.ACCEPTED then
            local nameMatch = false
            local customerMatch = false

            -- Match by item name
            if craftedItemName and order.recipeName then
                if craftedItemName:lower() == order.recipeName:lower() or
                   order.recipeName:lower():find(craftedItemName:lower(), 1, true) or
                   craftedItemName:lower():find(order.recipeName:lower(), 1, true) then
                    nameMatch = true
                end
            end

            -- Match by customer name
            if customerName and order.requester then
                local reqShort = order.requester:match("^(.+)-") or order.requester
                if customerName == order.requester or customerName == reqShort then
                    customerMatch = true
                end
            end

            -- If both match, high confidence — auto-complete
            if nameMatch and customerMatch then
                return order
            end

            -- If only name matches and it's a guild order (no specific customer), still match
            if nameMatch and not customerName then
                return order
            end
        end
    end

    return nil
end

------------------------------------------------------------------------
-- Mat Debt Tracking
-- Withdrawals = debt (price-locked at TSM value at time of withdrawal)
-- Deposits = credit (clears debt, or adds positive balance)
-- Crafter takes mats, crafts item, deposits finished item worth more
-- The locked price protects crafters from market shifts
------------------------------------------------------------------------

--- Ensure the debt ledger exists in guild data
local function EnsureDebtLedger()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end
    if not guildData.matDebts then
        guildData.matDebts = {} -- [playerName] = { debt, credits, entries[] }
    end
    return guildData.matDebts
end

--- Get or create a player's debt record
local function GetDebtRecord(debts, player)
    if not debts[player] then
        debts[player] = {
            totalDebt = 0,      -- Total value of mats withdrawn (price-locked)
            totalCredits = 0,   -- Total value of items deposited back
            entries = {},       -- Itemized log
        }
    end
    return debts[player]
end

--- Record a guild bank withdrawal as debt on the crafter's account
--- Price is locked at current TSM value so market shifts don't hurt them
---@param transaction table { player, itemID, quantity, timestamp }
function CT:RecordWithdrawalDebt(transaction)
    if not transaction.player or not transaction.itemID then return end

    -- Only track withdrawals from crafting mat tabs as debt
    -- Tab 1 (Public Deposits) — officer management, not debt
    -- Tab 2 (PVP Supplies) — rank perk, not debt
    -- Tab 3 (Crafting Mats T1) — debt
    -- Tab 4 (Crafting Mats T2) — debt
    -- Tab 5 (Finished Goods) — AH logistics, not debt
    -- Tab 6 (Officer Reserves) — officer only, not debt
    local DEBT_TABS = { [3] = true, [4] = true }
    if transaction.tabIndex and not DEBT_TABS[transaction.tabIndex] then return end

    -- Track withdrawals from crafting tabs as debt

    local debts = EnsureDebtLedger()
    if not debts then return end

    -- Lock the price at current TSM value
    local unitPrice = 0
    if GF.TSM and GF.TSM:IsAvailable() then
        unitPrice = GF.TSM:GetBestPrice(transaction.itemID) or 0
    end

    local qty = transaction.quantity or 1
    local totalValue = unitPrice * qty

    if totalValue == 0 then return end -- Skip items with no value

    local record = GetDebtRecord(debts, transaction.player)
    record.totalDebt = record.totalDebt + totalValue

    record.entries[#record.entries + 1] = {
        type = "withdraw",
        itemID = transaction.itemID,
        quantity = qty,
        lockedUnitPrice = unitPrice,
        lockedTotal = totalValue,
        timestamp = transaction.timestamp or GF.Utils:GetTime(),
    }

    -- Keep entries manageable
    if #record.entries > 200 then
        table.remove(record.entries, 1)
    end

    -- Log to item trail
    if GF.ItemTrail then
        GF.ItemTrail:OnCraftWithdraw(transaction.player, transaction.itemID, qty, totalValue)
    end

    if GF.debug then
        local name = C_Item.GetItemInfo(transaction.itemID) or ("Item:" .. transaction.itemID)
        GF.ChatNotify:Debug("Mat debt: " .. transaction.player .. " withdrew " ..
            name .. " x" .. qty .. " — " .. GF.Utils:FormatMoney(totalValue) .. " (price-locked)")
    end
end

--- Credit a guild bank deposit against a crafter's debt
--- If they deposit a higher-value crafted item, the excess is profit
---@param transaction table { player, itemID, quantity, timestamp }
function CT:CreditDeposit(transaction)
    if not transaction.player or not transaction.itemID then return end

    local debts = EnsureDebtLedger()
    if not debts then return end

    local record = debts[transaction.player]
    if not record then return end -- No debt to credit against

    -- Price the deposited item at current TSM value
    local unitPrice = 0
    if GF.TSM and GF.TSM:IsAvailable() then
        unitPrice = GF.TSM:GetBestPrice(transaction.itemID) or 0
    end

    local qty = transaction.quantity or 1
    local totalValue = unitPrice * qty

    if totalValue == 0 then return end

    -- Track the net BEFORE this deposit so we only recognize NEW profit
    local netBefore = record.totalCredits - record.totalDebt

    record.totalCredits = record.totalCredits + totalValue

    -- Log to item trail
    if GF.ItemTrail then
        GF.ItemTrail:OnCraftDeposit(transaction.player, transaction.itemID, transaction.itemLink, qty, totalValue)
    end

    record.entries[#record.entries + 1] = {
        type = "deposit",
        itemID = transaction.itemID,
        quantity = qty,
        lockedUnitPrice = unitPrice,
        lockedTotal = totalValue,
        timestamp = transaction.timestamp or GF.Utils:GetTime(),
    }

    -- Only recognize profit for the portion of THIS deposit that pushes net above zero
    -- e.g. if net was -5000 and deposit is 8000, only 3000 is new profit
    local netAfter = record.totalCredits - record.totalDebt
    if netAfter > 0 then
        local newProfit
        if netBefore >= 0 then
            -- Already positive before — entire deposit value is new profit
            newProfit = totalValue
        else
            -- Was negative — only the amount above zero is profit
            newProfit = netAfter -- which equals totalValue + netBefore (netBefore is negative)
        end

        if newProfit > 0 then
            local itemName = C_Item.GetItemInfo(transaction.itemID) or ("Item:" .. transaction.itemID)

            -- Record crafter profit as pending (credited when item sells on AH)
            GF.Ledger:AddEntry(GF.ACTIONS.FEE, transaction.player, {
                { itemID = transaction.itemID, quantity = qty },
            }, newProfit,
                "Craft profit (pending sale): " .. itemName .. " x" .. qty,
                "pending")

            GF.ChatNotify:Info("|cFF00FF00Craft profit recognized:|r " ..
                GF.Utils:FormatMoney(newProfit) ..
                " for " .. itemName .. " — |cFFFFAA00awaiting AH sale|r")
        end
    end

    if GF.debug then
        local name = C_Item.GetItemInfo(transaction.itemID) or ("Item:" .. transaction.itemID)
        local netDebt = record.totalDebt - record.totalCredits
        GF.ChatNotify:Debug("Mat credit: " .. transaction.player .. " deposited " ..
            name .. " x" .. qty .. " — " .. GF.Utils:FormatMoney(totalValue) ..
            " | Net: " .. (netDebt > 0 and ("|cFFFF0000-" .. GF.Utils:FormatMoney(netDebt) .. "|r") or ("|cFF00FF00+" .. GF.Utils:FormatMoney(-netDebt) .. "|r")))
    end
end

--- Get a crafter's current mat debt (negative = owes, positive = excess credit)
---@param player string "Player-Realm"
---@return number netBalance Positive = credit, negative = debt
---@return number totalDebt
---@return number totalCredits
function CT:GetMatBalance(player)
    local debts = EnsureDebtLedger()
    if not debts or not debts[player] then return 0, 0, 0 end
    local r = debts[player]
    return r.totalCredits - r.totalDebt, r.totalDebt, r.totalCredits
end

--- Get all crafters with outstanding mat debts
---@return table Array of { player, debt, credits, net, entries }
function CT:GetAllMatDebts()
    local debts = EnsureDebtLedger()
    if not debts then return {} end

    local results = {}
    for player, record in pairs(debts) do
        local net = record.totalCredits - record.totalDebt
        results[#results + 1] = {
            player = player,
            displayName = player:match("^(.+)-") or player,
            debt = record.totalDebt,
            credits = record.totalCredits,
            net = net,
            entries = record.entries,
        }
    end

    -- Sort: biggest debt first
    table.sort(results, function(a, b) return a.net < b.net end)
    return results
end

--- Clear a crafter's mat debt (officer action — marks as settled)
---@param player string
function CT:ClearMatDebt(player)
    local debts = EnsureDebtLedger()
    if not debts or not debts[player] then return end
    debts[player] = nil
    GF.ChatNotify:Info("Mat debt cleared for " .. player)
end
