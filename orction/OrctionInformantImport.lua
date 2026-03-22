-- OrctionInformantImport.lua
-- Imports Informant item data (InfData.lua) into Orction vendor price cache.
-- Import is deferred until ADDON_LOADED has fired AND both the Informant item
-- database and vendor table have been captured, regardless of load order.

OrctionInformantDB      = OrctionInformantDB      or nil
OrctionInformantVendors = OrctionInformantVendors or nil  -- id (number) -> vendor name

local orctionAddonLoaded = false  -- true once ADDON_LOADED has fired for Orction

-- ── Helpers ───────────────────────────────────────────────────────────────

local function Orction_Split(str, sep)
    local out = {}
    if type(str) ~= "string" then return out end
    local start = 1
    while true do
        local pos = string.find(str, sep, start, true)
        if not pos then
            table.insert(out, string.sub(str, start))
            break
        end
        table.insert(out, string.sub(str, start, pos - 1))
        start = pos + 1
    end
    return out
end

-- Resolve a comma-separated string of vendor IDs to a comma-separated string
-- of vendor names using the captured Informant vendors table.
-- Returns "" if idStr is empty or vendors table is unavailable.
local function Orction_ResolveVendorIds(idStr)
    if not idStr or idStr == "" then return "" end
    if not OrctionInformantVendors then return "" end
    local names = {}
    for idPart in string.gfind(idStr .. ",", "([^,]+),") do
        local id   = tonumber(idPart)
        local name = id and OrctionInformantVendors[id]
        if name and name ~= "" then
            table.insert(names, name)
        end
    end
    return table.concat(names, ",")
end

-- ── Import ────────────────────────────────────────────────────────────────

local function Orction_TryImport()
    if not orctionAddonLoaded  then return end
    if not OrctionInformantDB  then return end
    if not OrctionInformantVendors then return end

    OrctionDB = OrctionDB or {}
    OrctionDB.vendorPrices         = OrctionDB.vendorPrices         or {}
    OrctionDB.vendorPricesById     = OrctionDB.vendorPricesById     or {}
    OrctionDB.vendorMerchantById   = OrctionDB.vendorMerchantById   or {}
    OrctionDB.vendorMerchantByName = OrctionDB.vendorMerchantByName or {}

    for itemId, baseData in pairs(OrctionInformantDB) do
        if type(baseData) == "string" then
            local fields    = Orction_Split(baseData, ":")
            local buy       = tonumber(fields[1] or 0) or 0
            local sell      = tonumber(fields[2] or 0) or 0
            local vendorIds = fields[10] or ""
            local merchants = Orction_ResolveVendorIds(vendorIds)

            if buy > 0 or merchants ~= "" then
                if not OrctionDB.vendorMerchantById[itemId] then
                    OrctionDB.vendorMerchantById[itemId] = { buy = buy, merchants = merchants }
                end
            end
            if sell > 0 then
                if not OrctionDB.vendorPricesById[itemId] then
                    OrctionDB.vendorPricesById[itemId] = sell
                end
            end
            if (buy > 0 or merchants ~= "") and GetItemInfo then
                local name = GetItemInfo(itemId)
                if name and name ~= "" then
                    if not OrctionDB.vendorMerchantByName[name] then
                        OrctionDB.vendorMerchantByName[name] = { buy = buy, merchants = merchants }
                    end
                    if sell > 0 and not OrctionDB.vendorPrices[name] then
                        OrctionDB.vendorPrices[name] = sell
                    end
                end
            end
        end
    end

    OrctionInformantDB = nil  -- free memory; vendors table kept for runtime lookups
end

-- ── Informant hooks ───────────────────────────────────────────────────────

local function Orction_OnDatabase(db)
    OrctionInformantDB = db
    Orction_TryImport()
end

local function Orction_OnVendors(vendors)
    OrctionInformantVendors = vendors
    Orction_TryImport()
end

if Informant and Informant.SetDatabase then
    local orig = Informant.SetDatabase
    Informant.SetDatabase = function(db) Orction_OnDatabase(db) ; return orig(db) end
else
    Informant = Informant or {}
    Informant.SetDatabase     = Orction_OnDatabase
    Informant.SetSkills       = Informant.SetSkills       or function() end
    Informant.SetRequirements = Informant.SetRequirements or function() end
end

if Informant.SetVendors then
    local orig = Informant.SetVendors
    Informant.SetVendors = function(vendors) Orction_OnVendors(vendors) ; return orig(vendors) end
else
    Informant.SetVendors = Orction_OnVendors
end

-- ── ADDON_LOADED ──────────────────────────────────────────────────────────

local informantImportFrame = CreateFrame("Frame")
informantImportFrame:RegisterEvent("ADDON_LOADED")
informantImportFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        orctionAddonLoaded = true
        Orction_TryImport()
    end
end)
