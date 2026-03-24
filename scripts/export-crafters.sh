#!/bin/bash
# Extract crafter recipes from WoW SavedVariables into data/crafters.json
# Called by pre-commit hook to keep recipe snapshot up-to-date

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WOW_SV="/f/World of Warcraft/_retail_/WTF/Account/103877938#1/SavedVariables/VaultOfTruths.lua"
OUTPUT="$REPO_ROOT/Data/crafters.json"

if [ ! -f "$WOW_SV" ]; then
    echo "SavedVariables not found, skipping crafter export"
    exit 0
fi

# Use lua to parse the SavedVariables and output JSON
# WoW SV files are valid Lua tables
lua - "$WOW_SV" "$OUTPUT" 2>/dev/null <<'LUASCRIPT'
local svFile = arg[1]
local outFile = arg[2]

-- Load the SavedVariables file
local env = {}
local chunk, err = loadfile(svFile, "t", env)
if not chunk then
    print("Failed to parse SavedVariables: " .. (err or "unknown"))
    os.exit(0)
end
chunk()

local db = env.VaultOfTruthsDB
if not db or not db.guilds then
    print("No guild data found")
    os.exit(0)
end

-- JSON helpers
local function jsonStr(s)
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
end

local out = {}
out[#out+1] = '{"crafters":{'

local firstCrafter = true

-- Extract from all guilds
for guildKey, guildData in pairs(db.guilds) do
    local recipes = guildData.crafterRecipes
    if recipes then
        for playerName, crafterData in pairs(recipes) do
            if crafterData.professions then
                if not firstCrafter then out[#out+1] = ',' end
                firstCrafter = false
                out[#out+1] = jsonStr(playerName) .. ':{"professions":{'

                local firstProf = true
                for profName, profData in pairs(crafterData.professions) do
                    if profData.recipes then
                        if not firstProf then out[#out+1] = ',' end
                        firstProf = false
                        out[#out+1] = jsonStr(profName) .. ':{"recipes":['

                        local firstRecipe = true
                        for _, recipe in ipairs(profData.recipes) do
                            if not firstRecipe then out[#out+1] = ',' end
                            firstRecipe = false

                            local name = recipe.name or recipe.id or ""
                            local isPvp = name:lower():find("competitor") or
                                          name:lower():find("thalassian") or
                                          name:lower():find("gladiator") or
                                          name:lower():find("combatant") or false
                            out[#out+1] = '{"name":' .. jsonStr(name)
                            if recipe.recipeID then
                                out[#out+1] = ',"recipeID":' .. tostring(recipe.recipeID)
                            end
                            if recipe.outputItemID then
                                out[#out+1] = ',"outputItemID":' .. tostring(recipe.outputItemID)
                            end
                            out[#out+1] = ',"pvp":' .. tostring(isPvp and true or false) .. '}'
                        end

                        out[#out+1] = '],"count":' .. tostring(#profData.recipes) .. '}'
                    end
                end
                out[#out+1] = '}}'
            end
        end
    end
end

out[#out+1] = '},"exported":"' .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. '"}'

local f = io.open(outFile, "w")
if f then
    f:write(table.concat(out))
    f:close()
    print("Exported crafter recipes to " .. outFile)
else
    print("Failed to write " .. outFile)
end
LUASCRIPT

# Fallback: if lua isn't available, try python
if [ $? -ne 0 ] && command -v python3 &>/dev/null; then
    python3 - "$WOW_SV" "$OUTPUT" <<'PYSCRIPT'
import sys, re, json, os
from datetime import datetime, timezone

sv_path = sys.argv[1]
out_path = sys.argv[2]

with open(sv_path, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

crafters = {}

# Find crafterRecipes blocks and extract player/profession/recipe data
# Simple regex-based extraction from the Lua table format
sections = content.split('["crafterRecipes"]')

for section in sections[1:]:  # skip before first occurrence
    # Find player entries like ["PlayerName-Realm"] = {
    players = re.finditer(r'\["([^"]+)"\]\s*=\s*\{\s*\["professions"\]', section)
    for pm in players:
        player = pm.group(1)
        # Find this player's profession block
        pos = pm.start()
        prof_section = section[pos:pos+50000]  # grab enough

        profs = {}
        prof_matches = re.finditer(r'\["(\w+)"\]\s*=\s*\{\s*\["scannedAt"\]', prof_section)
        for pfm in prof_matches:
            prof_name = pfm.group(1)
            ppos = pfm.start()
            # Find recipes array
            recipe_section = prof_section[ppos:ppos+30000]

            recipes = []
            # Match recipe entries: ["name"] = "...", or name = "..."
            recipe_names = re.findall(r'\["name"\]\s*=\s*"([^"]*)"', recipe_section)
            recipe_ids = re.findall(r'\["recipeID"\]\s*=\s*(\d+)', recipe_section)
            output_ids = re.findall(r'\["outputItemID"\]\s*=\s*(\d+)', recipe_section)

            for i, name in enumerate(recipe_names):
                pvp_keywords = ['competitor', 'thalassian', 'gladiator', 'combatant']
                is_pvp = any(kw in name.lower() for kw in pvp_keywords)
                recipe = {"name": name, "pvp": is_pvp}
                if i < len(recipe_ids):
                    recipe["recipeID"] = int(recipe_ids[i])
                if i < len(output_ids):
                    recipe["outputItemID"] = int(output_ids[i])
                recipes.append(recipe)

            if recipes:
                profs[prof_name] = {"recipes": recipes, "count": len(recipes)}

        if profs:
            crafters[player] = {"professions": profs}

result = {
    "crafters": crafters,
    "exported": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(crafters)} crafters to {out_path}")
PYSCRIPT
fi

if [ -f "$OUTPUT" ]; then
    git add "$OUTPUT" 2>/dev/null
fi
