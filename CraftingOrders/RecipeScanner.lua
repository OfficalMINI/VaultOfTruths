------------------------------------------------------------------------
-- Vault of Truths - CraftingOrders/RecipeScanner.lua
-- Scans player's known recipes, stores them, syncs to guild
-- Shows which guild crafters can make what
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

GF.RecipeScanner = {}
local RS = GF.RecipeScanner
GF:RegisterModule("RecipeScanner", RS)

function RS:Init()
    -- Scan recipes when profession data is ready
    -- Note: TRADE_SKILL_LIST_UPDATE fires after the UI is shown and data is
    -- loaded, avoiding the taint that TRADE_SKILL_SHOW causes with ShowUIPanel.
    GF.Events:Register("TRADE_SKILL_LIST_UPDATE", function()
        RS:ScanCurrentProfession()
    end)

    -- Also scan on login (delayed) for professions already known
    GF.Events:On("GF_PLAYER_LOGIN", function()
        C_Timer.After(10, function()
            RS:ScanAllProfessions()
        end)
    end)

    -- Listen for synced recipe data from other guild members
    GF.Events:On("GF_RECIPES_RECEIVED", function(playerName, recipes)
        RS:StorePlayerRecipes(playerName, recipes)
    end)
end

--- Scan the currently open profession window
function RS:ScanCurrentProfession()
    if not C_TradeSkillUI.IsTradeSkillReady() then return end

    local profInfo = C_TradeSkillUI.GetBaseProfessionInfo()
    if not profInfo then return end

    local profName = profInfo.professionName or "Unknown"
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    if not recipeIDs then return end

    local playerName = GF.Utils:GetPlayerFullName()
    local recipes = {}

    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo and recipeInfo.learned then
            -- Get reagents from the recipe schematic
            local reagents = {}
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
            if schematic and schematic.reagentSlotSchematics then
                for _, slot in ipairs(schematic.reagentSlotSchematics) do
                    if slot.reagentType == Enum.CraftingReagentType.Basic then
                        for _, itemInfo in ipairs(slot.reagents) do
                            if itemInfo.itemID then
                                reagents[#reagents + 1] = {
                                    itemID = itemInfo.itemID,
                                    quantity = slot.quantityRequired or 1,
                                }
                            end
                        end
                    end
                end
            end

            -- Get output item ID
            local outputItemID = nil
            if schematic and schematic.outputItemID then
                outputItemID = schematic.outputItemID
            end

            recipes[#recipes + 1] = {
                recipeID = recipeID,
                name = recipeInfo.name,
                skillLineAbilityID = recipeInfo.skillLineAbilityID,
                difficulty = recipeInfo.difficulty,
                categoryID = recipeInfo.categoryID,
                reagents = reagents,
                outputItemID = outputItemID,
            }
        end
    end

    if GF.debug then
        GF.ChatNotify:Debug("Scanned " .. #recipes .. " recipes from " .. profName)
    end

    -- Store locally
    self:StoreMyRecipes(profName, recipes)

    -- Broadcast to guild
    self:BroadcastRecipes(profName, recipes)
end

--- Scan all professions the player has (without opening the window)
function RS:ScanAllProfessions()
    -- C_TradeSkillUI.GetAllProfessionTradeSkillLines() returns profession skill line IDs
    -- But we can only get recipe details when the tradeskill UI is open
    -- So this just ensures our stored data is available from previous scans

    local playerName = GF.Utils:GetPlayerFullName()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    -- Ensure our entry exists
    if not guildData.crafterRecipes then
        guildData.crafterRecipes = {}
    end
    if not guildData.crafterRecipes[playerName] then
        guildData.crafterRecipes[playerName] = {
            professions = {},
            lastScan = 0,
        }
    end
end

--- Store the current player's recipes for a profession
---@param profName string Profession name
---@param recipes table Array of recipe info
function RS:StoreMyRecipes(profName, recipes)
    local playerName = GF.Utils:GetPlayerFullName()
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    if not guildData.crafterRecipes then
        guildData.crafterRecipes = {}
    end
    if not guildData.crafterRecipes[playerName] then
        guildData.crafterRecipes[playerName] = { professions = {}, lastScan = 0 }
    end

    guildData.crafterRecipes[playerName].professions[profName] = {
        recipes = recipes,
        count = #recipes,
        scannedAt = GF.Utils:GetTime(),
    }
    guildData.crafterRecipes[playerName].lastScan = GF.Utils:GetTime()

    GF.Events:Fire("GF_MY_RECIPES_UPDATED", profName, #recipes)
end

--- Store another player's synced recipes
---@param playerName string
---@param data table { profName, recipes }
function RS:StorePlayerRecipes(playerName, data)
    local guildData = GF.Settings:GetGuildData()
    if not guildData then return end

    if not guildData.crafterRecipes then
        guildData.crafterRecipes = {}
    end
    if not guildData.crafterRecipes[playerName] then
        guildData.crafterRecipes[playerName] = { professions = {}, lastScan = 0 }
    end

    if data.profName and data.recipes then
        guildData.crafterRecipes[playerName].professions[data.profName] = {
            recipes = data.recipes,
            count = #data.recipes,
            scannedAt = GF.Utils:GetTime(),
        }
        guildData.crafterRecipes[playerName].lastScan = GF.Utils:GetTime()
    end
end

--- Broadcast your recipes to the guild
---@param profName string
---@param recipes table
function RS:BroadcastRecipes(profName, recipes)
    if not GF.Sender then return end

    -- Send recipe names, IDs, reagents, and output item
    local compact = {}
    for _, r in ipairs(recipes) do
        compact[#compact + 1] = {
            id = r.recipeID,
            name = r.name,
            reagents = r.reagents,
            outputItemID = r.outputItemID,
        }
    end

    GF.Sender:Send("RECIPES", {
        player = GF.Utils:GetPlayerFullName(),
        profName = profName,
        recipes = compact,
    })
end

--- Search all known guild crafters for who can make a specific item
---@param searchText string Partial recipe name to search
---@param guildName string|nil External guild name, or nil for own guild
---@return table Array of { playerName, profName, recipeName, recipeID }
function RS:FindCrafters(searchText, guildName)
    local crafterRecipes
    if guildName then
        local extData = GF.Settings:GetExternalGuildData(guildName)
        crafterRecipes = extData and extData.crafterRecipes
    else
        local guildData = GF.Settings:GetGuildData()
        crafterRecipes = guildData and guildData.crafterRecipes
    end
    if not crafterRecipes then return {} end

    searchText = searchText:lower()
    local results = {}

    for playerName, playerData in pairs(crafterRecipes) do
        for profName, profData in pairs(playerData.professions or {}) do
            for _, recipe in ipairs(profData.recipes or {}) do
                local recipeName = recipe.name or ""
                if recipeName:lower():find(searchText, 1, true) then
                    results[#results + 1] = {
                        playerName = playerName,
                        displayName = playerName:match("^(.+)-") or playerName,
                        profName = profName,
                        recipeName = recipeName,
                        recipeID = recipe.recipeID or recipe.id,
                        reagents = recipe.reagents,
                        outputItemID = recipe.outputItemID,
                    }
                end
            end
        end
    end

    -- Sort by player name
    table.sort(results, function(a, b) return a.displayName < b.displayName end)
    return results
end

--- Get all professions and recipe counts for a specific player
---@param playerName string
---@param guildName string|nil External guild name, or nil for own guild
---@return table { [profName] = { count, scannedAt } }
function RS:GetPlayerProfessions(playerName, guildName)
    local crafterRecipes
    if guildName then
        local extData = GF.Settings:GetExternalGuildData(guildName)
        crafterRecipes = extData and extData.crafterRecipes
    else
        local guildData = GF.Settings:GetGuildData()
        crafterRecipes = guildData and guildData.crafterRecipes
    end
    if not crafterRecipes then return {} end

    local playerData = crafterRecipes[playerName]
    if not playerData then return {} end

    local result = {}
    for profName, profData in pairs(playerData.professions or {}) do
        result[profName] = {
            count = profData.count or 0,
            scannedAt = profData.scannedAt or 0,
        }
    end
    return result
end

--- Get a summary of all guild crafters and their professions
---@param guildName string|nil External guild name, or nil for own guild
---@return table Array of { playerName, displayName, professions = { name, count }, lastScan }
function RS:GetCrafterSummary(guildName)
    local crafterRecipes
    if guildName then
        local extData = GF.Settings:GetExternalGuildData(guildName)
        crafterRecipes = extData and extData.crafterRecipes
    else
        local guildData = GF.Settings:GetGuildData()
        crafterRecipes = guildData and guildData.crafterRecipes
    end
    if not crafterRecipes then return {} end

    local summary = {}
    for playerName, playerData in pairs(crafterRecipes) do
        local profs = {}
        for profName, profData in pairs(playerData.professions or {}) do
            profs[#profs + 1] = {
                name = profName,
                count = profData.count or 0,
            }
        end
        if #profs > 0 then
            summary[#summary + 1] = {
                playerName = playerName,
                displayName = playerName:match("^(.+)-") or playerName,
                professions = profs,
                lastScan = playerData.lastScan or 0,
            }
        end
    end

    table.sort(summary, function(a, b) return a.displayName < b.displayName end)
    return summary
end
