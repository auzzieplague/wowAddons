-- DataManagement.lua
-- Centralized data handling for Orction.

local function OrctionData_EnsureDB()
    OrctionDB = OrctionDB or {}
    OrctionDB.priceHistory = OrctionDB.priceHistory or {}
end

local function OrctionData_GetDaySlot()
    local day = tonumber(date("%j")) or 1
    return math.mod(day, 7) + 1
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
end
