-- DataManagement.lua
-- Centralized data handling for Orction.

local function OrctionData_EnsureDB()
    OrctionDB = OrctionDB or {}
    OrctionDB.priceHistory = OrctionDB.priceHistory or {}
end

local function OrctionData_GetDaySlot()
    local day = tonumber(date("%j")) or 1
    local offset = ORCTION_DAY_OFFSET or 0
    return math.mod(day + offset, 7) + 1
end

local function OrctionData_GetPriceEntry(itemId, name)
    OrctionData_EnsureDB()
    local key = itemId or ("name:" .. name)
    local entry = OrctionDB.priceHistory[key]
    if not entry then
        entry = { itemId = itemId or 0, name = name or "" }
        OrctionDB.priceHistory[key] = entry
    end
    return entry
end

function OrctionData_ShouldRecord(itemId, name)
    OrctionData_EnsureDB()
    local key = itemId or ("name:" .. name)
    local entry = OrctionDB.priceHistory[key]
    if not entry then return true end
    local cacheHours = ORCTION_DATA_CACHE_HOURS or 1
    local cacheSeconds = cacheHours * 3600
    if cacheSeconds <= 0 then return true end
    local last = entry.lastRecorded
    if not last then return true end
    return (time() - last) >= cacheSeconds
end

-- Returns the raw price history entry for an item, or nil if not found.
-- Tries numeric itemId key first, then "name:<name>" key, then a full scan by name.
function OrctionData_GetItemHistory(itemId, name)
    if not (OrctionDB and OrctionDB.priceHistory) then return nil end
    if itemId and itemId > 0 then
        local e = OrctionDB.priceHistory[itemId]
        if e then return e end
    end
    if name then
        local e = OrctionDB.priceHistory["name:" .. name]
        if e then return e end
        for _, entry in pairs(OrctionDB.priceHistory) do
            if entry.name == name then return entry end
        end
    end
    return nil
end

-- Record a buyout price observation into the day slot rolling window.
-- price is total buyout for the auction stack; count is stack size.
function OrctionData_RecordScanPrice(itemId, name, price, count)
    if not price or price <= 0 then return end
    OrctionData_EnsureDB()

    local slot = OrctionData_GetDaySlot()
    local entry = OrctionData_GetPriceEntry(itemId, name)

    local pKey = "day" .. slot .. "Price"
    local cKey = "day" .. slot .. "Count"
    local oldPrice = entry[pKey] or 0
    local oldCount = entry[cKey] or 0
    local addCount = count or 1
    local total = (oldPrice * oldCount) + (price * addCount)
    local newCount = oldCount + addCount
    if newCount > 0 then
        entry[pKey] = math.floor(total / newCount)
        entry[cKey] = newCount
    end
    entry.lastRecorded = time()
end
