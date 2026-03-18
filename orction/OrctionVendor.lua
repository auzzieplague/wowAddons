-- OrctionVendor.lua
-- Looks up vendor sell prices from the static SellValues DB (Database.lua),
-- keyed by "item:XXXX". Prices are resolved by scanning the player's bags for
-- a container link containing the item ID, then caching name -> copper.

-- ── Initialise DB on load ───────────────────────────────────────────────────

local orctionVendorLoadFrame = CreateFrame("Frame")
orctionVendorLoadFrame:RegisterEvent("ADDON_LOADED")
orctionVendorLoadFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        if SellValue_InitializeDB then
            SellValue_InitializeDB()
        end
    end
end)

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- Extract item ID from a vanilla WoW hyperlink e.g. |Hitem:12345:0:0:0|h...
local function Orction_ItemIDFromLink(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    return id
end

-- Scan bags for an item matching itemName, return its sell price from DB or 0.
local function Orction_LookupPriceFromBags(itemName)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = string.gsub(link, ".*%[(.-)%].*", "%1")
                if name == itemName then
                    local itemID = Orction_ItemIDFromLink(link)
                    if itemID and SellValues then
                        local price = SellValues["item:" .. itemID]
                        if price then
                            return price
                        end
                    end
                    return 0
                end
            end
        end
    end
    return nil  -- item not found in bags
end

-- ── Public API ──────────────────────────────────────────────────────────────

-- Returns vendor sell price in copper, or 0 if unknown.
-- Checks OrctionDB cache first, then scans bags against SellValues DB.
function OrctionVendor_GetPrice(itemName, itemId)
    if not itemName or itemName == "" then return 0 end

    -- Check persistent cache
    if itemId and OrctionDB and OrctionDB.vendorPricesById and OrctionDB.vendorPricesById[itemId] then
        return OrctionDB.vendorPricesById[itemId]
    end
    if OrctionDB and OrctionDB.vendorPrices and OrctionDB.vendorPrices[itemName] then
        return OrctionDB.vendorPrices[itemName]
    end

    -- Try to resolve via bag scan + static DB
    local price = Orction_LookupPriceFromBags(itemName)
    if price and price > 0 then
        -- Cache for future lookups
        if OrctionDB and OrctionDB.vendorPrices then
            OrctionDB.vendorPrices[itemName] = price
        end
        return price
    end

    return 0
end

function OrctionVendor_GetCache()
    return (OrctionDB and OrctionDB.vendorPrices) or {}
end
