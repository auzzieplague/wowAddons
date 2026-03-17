-- OrctionSync.lua
-- Basic addon message sync for auction data.

local ORCTION_SYNC_PREFIX  = "ORCTION"
local ORCTION_SYNC_VERSION = "1"
local ORCTION_SYNC_INTERVAL = 0.5

local syncQueue      = {}
local syncQueueOrder = {}
local syncElapsed    = 0

local function OrctionSync_GetChannel()
    if OrctionDB and OrctionDB.settings and OrctionDB.settings.syncChannel then
        return OrctionDB.settings.syncChannel
    end
    return ORCTION_SYNC_CHANNEL or "GUILD"
end

local function OrctionSync_CanSend(channel)
    if channel == "GUILD" then
        return IsInGuild and IsInGuild()
    elseif channel == "RAID" then
        return GetNumRaidMembers and GetNumRaidMembers() > 0
    elseif channel == "PARTY" then
        return GetNumPartyMembers and GetNumPartyMembers() > 0
    end
    return false
end

function OrctionSync_SetEnabled(enabled)
    ORCTION_SYNC_ENABLED = enabled and 1 or 0
end

function OrctionSync_SetChannel(channel)
    ORCTION_SYNC_CHANNEL = channel
end

function OrctionSync_QueueItem(itemId, name)
    if not (OrctionDB and OrctionDB.settings and OrctionDB.settings.syncEnabled) then return end
    if not name or name == "" then return end
    local key = (itemId and itemId > 0) and tostring(itemId) or ("name:" .. name)
    if syncQueue[key] then return end
    syncQueue[key] = true
    table.insert(syncQueueOrder, { key = key, itemId = itemId or 0, name = name })
end

local function OrctionSync_BuildMessage(entry)
    local parts = {}
    table.insert(parts, "D")
    table.insert(parts, tostring(entry.itemId or 0))
    table.insert(parts, entry.name or "")
    table.insert(parts, tostring(entry.lastRecorded or 0))
    for d = 1, 7 do
        table.insert(parts, tostring(entry["day" .. d .. "Price"] or 0))
        table.insert(parts, tostring(entry["day" .. d .. "Count"] or 0))
    end
    return table.concat(parts, "^")
end

local function OrctionSync_SendNext()
    if table.getn(syncQueueOrder) == 0 then return end
    local channel = OrctionSync_GetChannel()
    if not OrctionSync_CanSend(channel) then return end

    local nextItem = table.remove(syncQueueOrder, 1)
    if not nextItem then return end
    syncQueue[nextItem.key] = nil

    local entry = OrctionData_GetItemHistory(nextItem.itemId, nextItem.name)
    if not entry then return end

    local msg = OrctionSync_BuildMessage(entry)
    if SendAddonMessage then
        SendAddonMessage(ORCTION_SYNC_PREFIX, msg, channel)
    end
end

local syncFrame = CreateFrame("Frame")
syncFrame:SetScript("OnUpdate", function()
    if not (OrctionDB and OrctionDB.settings and OrctionDB.settings.syncEnabled) then return end
    syncElapsed = syncElapsed + (arg1 or 0)
    if syncElapsed < ORCTION_SYNC_INTERVAL then return end
    syncElapsed = 0
    OrctionSync_SendNext()
end)

local function OrctionSync_HandleMessage(msg, sender)
    if not msg then return end
    if sender and UnitName and sender == UnitName("player") then return end

    local fields = {}
    for part in string.gfind(msg, "([^%^]+)") do
        table.insert(fields, part)
    end
    if fields[1] ~= "D" then return end

    local itemId = tonumber(fields[2] or 0) or 0
    local name = fields[3] or ""
    if name == "" and itemId <= 0 then return end
    local lastRecorded = tonumber(fields[4] or 0) or 0

    local entry = { itemId = itemId, name = name, lastRecorded = lastRecorded }
    local idx = 5
    for d = 1, 7 do
        entry["day" .. d .. "Price"] = tonumber(fields[idx] or 0) or 0
        entry["day" .. d .. "Count"] = tonumber(fields[idx + 1] or 0) or 0
        idx = idx + 2
    end

    OrctionSync_IsApplying = true
    if OrctionData_MergeEntry then
        OrctionData_MergeEntry(entry)
    end
    OrctionSync_IsApplying = false
end

local syncEventFrame = CreateFrame("Frame")
syncEventFrame:RegisterEvent("ADDON_LOADED")
syncEventFrame:RegisterEvent("CHAT_MSG_ADDON")
syncEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(ORCTION_SYNC_PREFIX)
        end
    elseif event == "CHAT_MSG_ADDON" then
        if arg1 == ORCTION_SYNC_PREFIX then
            OrctionSync_HandleMessage(arg2, arg4)
        end
    end
end)
