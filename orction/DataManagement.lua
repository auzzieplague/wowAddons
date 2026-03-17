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

    if not OrctionSync_IsApplying and OrctionSync_QueueItem then
        OrctionSync_QueueItem(itemId, name)
    end
end

-- Merge an incoming entry from addon sync into the local history.
function OrctionData_MergeEntry(inEntry)
    if not inEntry then return end
    OrctionData_EnsureDB()

    local name = inEntry.name or ""
    local itemId = tonumber(inEntry.itemId or 0) or 0
    local key = (itemId > 0) and itemId or ("name:" .. name)
    local entry = OrctionDB.priceHistory[key]
    if not entry then
        entry = { itemId = itemId, name = name }
        OrctionDB.priceHistory[key] = entry
    end

    if entry.name == "" and name ~= "" then entry.name = name end
    if (entry.itemId == 0 or not entry.itemId) and itemId > 0 then entry.itemId = itemId end

    for d = 1, 7 do
        local pKey = "day" .. d .. "Price"
        local cKey = "day" .. d .. "Count"
        local incPrice = tonumber(inEntry[pKey] or 0) or 0
        local incCount = tonumber(inEntry[cKey] or 0) or 0
        if incPrice > 0 and incCount > 0 then
            local oldPrice = entry[pKey] or 0
            local oldCount = entry[cKey] or 0
            local total = (oldPrice * oldCount) + (incPrice * incCount)
            local newCount = oldCount + incCount
            if newCount > 0 then
                entry[pKey] = math.floor(total / newCount)
                entry[cKey] = newCount
            end
        end
    end

    local incLast = tonumber(inEntry.lastRecorded or 0) or 0
    if incLast > 0 then
        if not entry.lastRecorded or incLast > entry.lastRecorded then
            entry.lastRecorded = incLast
        end
    end
end
