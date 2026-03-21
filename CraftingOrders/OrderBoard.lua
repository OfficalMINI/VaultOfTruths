------------------------------------------------------------------------
-- Vault of Truths - CraftingOrders/OrderBoard.lua
-- Crafting order CRUD: create, accept, complete, cancel
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.OrderBoard = {}
local OB = GF.OrderBoard
GF:RegisterModule("OrderBoard", OB)

function OB:Init()
    -- Nothing to init
end

--- Create a new crafting order
---@param recipeID number Game recipe ID
---@param recipeName string Display name
---@param mats table Array of { itemID, quantity }
---@param supplyMode string "requester" (they supply mats) or "guild" (guild supplies mats)
---@return table|nil order
function OB:CreateOrder(recipeID, recipeName, mats, supplyMode)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end

    -- Calculate mat costs via TSM
    local matDetails = {}
    local totalMatCost = 0
    for _, mat in ipairs(mats) do
        local unitCost = GF.TSM:GetBestPrice(mat.itemID) or 0
        local matCost = unitCost * mat.quantity
        totalMatCost = totalMatCost + matCost
        matDetails[#matDetails + 1] = {
            itemID = mat.itemID,
            quantity = mat.quantity,
            unitCost = unitCost,
            totalCost = matCost,
        }
    end

    -- Calculate fee
    -- Guild supplies mats: mat cost + flat commission (customer pays for mats AND craft)
    -- Requester supplies mats: just the percentage-based crafting fee
    local fee
    local commission = GF.Settings:GetGuild("craftCommission") or GF.DEFAULT_CRAFT_COMMISSION
    if supplyMode == "guild" then
        fee = totalMatCost + commission
    else
        fee = GF.FeeCalculator:Calculate(totalMatCost)
    end

    -- Store the output item ID for icon/tooltip resolution
    -- recipeID might be a spell ID or item ID depending on source
    local outputItemID = recipeID
    if recipeID then
        local _, link = C_Item.GetItemInfo(recipeID)
        if not link and mats and mats[1] then
            outputItemID = mats[1].itemID
        end
    end

    local order = {
        id = GF.Utils:GenerateID(),
        recipeID = recipeID,
        outputItemID = outputItemID,
        recipeName = recipeName,
        requester = GF.Utils:GetPlayerFullName(),
        crafter = nil,
        status = GF.ORDER_STATUS.OPEN,
        supplyMode = supplyMode or "guild",
        mats = matDetails,
        totalMatCost = totalMatCost,
        fee = fee,
        created = GF.Utils:GetTime(),
        accepted = nil,
        completed = nil,
    }

    guildData.orders[#guildData.orders + 1] = order

    -- Broadcast to guild
    GF.Sender:BroadcastNewOrder(order)
    GF.Events:Fire("GF_ORDER_CREATED", order)

    GF.ChatNotify:Success("Crafting order posted: " .. recipeName .. " — Fee: " .. GF.Utils:FormatMoney(fee))
    return order
end

--- Accept a crafting order (crafter claims it)
---@param orderID string
---@return boolean success
function OB:AcceptOrder(orderID)
    local order = self:GetOrder(orderID)
    if not order then return false end

    if order.status ~= GF.ORDER_STATUS.OPEN then
        GF.ChatNotify:Warning("Order #" .. orderID .. " is not open (status: " .. order.status .. ")")
        return false
    end

    local playerName = GF.Utils:GetPlayerFullName()

    -- Must have crafter role
    if not GF.Roles:HasRole(playerName, GF.ROLES.CRAFTER) then
        GF.ChatNotify:Warning("You need the Crafter role to accept orders.")
        return false
    end

    order.status = GF.ORDER_STATUS.ACCEPTED
    order.crafter = playerName
    order.accepted = GF.Utils:GetTime()

    GF.Sender:BroadcastOrderUpdate(orderID, GF.ORDER_STATUS.ACCEPTED, playerName)
    GF.Events:Fire("GF_ORDER_ACCEPTED", order)

    GF.ChatNotify:Success("Accepted order: " .. order.recipeName)
    return true
end

--- Complete a crafting order
---@param orderID string
---@return boolean success
function OB:CompleteOrder(orderID)
    local order = self:GetOrder(orderID)
    if not order then return false end

    if order.status ~= GF.ORDER_STATUS.ACCEPTED then
        GF.ChatNotify:Warning("Order must be accepted before completing.")
        return false
    end

    local playerName = GF.Utils:GetPlayerFullName()
    if order.crafter ~= playerName then
        GF.ChatNotify:Warning("Only the assigned crafter can complete this order.")
        return false
    end

    order.status = GF.ORDER_STATUS.COMPLETED
    order.completed = GF.Utils:GetTime()

    -- Record the crafting fee as income for the crafter
    GF.Ledger:AddEntry(GF.ACTIONS.FEE, playerName, nil, order.fee,
        "Crafting fee for " .. order.recipeName)

    -- Record mat consumption from guild bank (so depositors get credited when item sells)
    if order.supplyMode == "guild" and order.mats and #order.mats > 0 then
        GF.Ledger:AddEntry(GF.ACTIONS.CRAFT_WITHDRAW, playerName, order.mats, order.totalMatCost or 0,
            "Mats used for: " .. order.recipeName, "credited")
    end

    GF.Sender:BroadcastOrderUpdate(orderID, GF.ORDER_STATUS.COMPLETED, playerName)
    GF.Events:Fire("GF_ORDER_COMPLETED", order)

    GF.ChatNotify:Success("Order completed: " .. order.recipeName .. " — Earned: " .. GF.Utils:FormatMoney(order.fee))
    return true
end

--- Cancel a crafting order
---@param orderID string
---@return boolean success
function OB:CancelOrder(orderID)
    local order = self:GetOrder(orderID)
    if not order then return false end

    local playerName = GF.Utils:GetPlayerFullName()
    -- Requester or officer can cancel
    if order.requester ~= playerName and not GF.Roles:IsAddonOfficer() then
        GF.ChatNotify:Warning("Only the requester or an officer can cancel orders.")
        return false
    end

    order.status = GF.ORDER_STATUS.CANCELLED

    GF.Sender:BroadcastOrderUpdate(orderID, GF.ORDER_STATUS.CANCELLED, playerName)
    GF.Events:Fire("GF_ORDER_CANCELLED", order)

    GF.ChatNotify:Info("Order cancelled: " .. order.recipeName)
    return true
end

--- Create an external crafting order (non-guildie submitting to a guild)
---@param guildName string Target guild name
---@param recipeID number
---@param recipeName string
---@param mats table Array of { itemID, quantity }
---@return table|nil order
function OB:CreateExternalOrder(guildName, recipeID, recipeName, mats)
    local order = {
        id = GF.Utils:GenerateID(),
        recipeID = recipeID,
        recipeName = recipeName,
        requester = GF.Utils:GetPlayerFullName(),
        crafter = nil,
        status = GF.ORDER_STATUS.OPEN,
        supplyMode = "requester",
        mats = mats or {},
        created = GF.Utils:GetTime(),
        isExternal = true,
        sourceGuild = guildName,
    }

    -- Store locally in external guild data
    local extData = GF.Settings:GetExternalGuildData(guildName)
    extData.orders[#extData.orders + 1] = order

    -- Submit via CommunityBridge whisper
    GF.CommunityBridge:SubmitOrder(guildName, order)
    GF.Events:Fire("GF_ORDER_CREATED", order)

    GF.ChatNotify:Info("Craft request sent: " .. recipeName)
    return order
end

--- Get an order by ID
---@param orderID string
---@return table|nil order
function OB:GetOrder(orderID)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return nil end

    for _, order in ipairs(guildData.orders) do
        if order.id == orderID then
            return order
        end
    end
    return nil
end

--- Get orders filtered by status
---@param status string|nil Filter by status, or nil for all
---@return table Array of orders
function OB:GetOrders(status)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    if not status then return guildData.orders end

    local results = {}
    for _, order in ipairs(guildData.orders) do
        if order.status == status then
            results[#results + 1] = order
        end
    end
    return results
end

--- Get orders assigned to a specific crafter
---@param crafterName string
---@return table Array of orders
function OB:GetCrafterOrders(crafterName)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return {} end

    local results = {}
    for _, order in ipairs(guildData.orders) do
        if order.crafter == crafterName then
            results[#results + 1] = order
        end
    end
    return results
end
