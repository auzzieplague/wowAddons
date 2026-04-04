-- OrctionBags.lua
-- /tidybags: tidy inventory by category, filling from last slot.

local PERSONAL_KEYWORDS = {
    "hearthstone",
    "fishing pole",
    "healing potion",
    "bandage",
    "flash powder",
    "mining pick",
    "skinning knife",
}

local function OrctionBags_GetItemName(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end

local function OrctionBags_GetItemId(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    return id and tonumber(id) or nil
end

local function OrctionBags_IsPersonal(name)
    if not name or name == "" then return false end
    local lname = string.lower(name)
    for _, key in ipairs(PERSONAL_KEYWORDS) do
        if string.find(lname, key, 1, true) then return true end
    end
    return false
end

local function OrctionBags_Categorize(name, itemType, subType)
    if OrctionBags_IsPersonal(name) then return "personal" end
    local t = itemType and string.lower(itemType) or ""
    local s = subType and string.lower(subType) or ""
    if t == "quest" then return "quest" end
    if t == "trade goods" then
        if s == "metal & stone" or s == "ore" then return "ore" end
        if s == "cloth" then return "cloth" end
        if s == "herb" then return "herb" end
    end
    return "other"
end

local function OrctionBags_Move(srcBag, srcSlot, dstBag, dstSlot)
    if srcBag == dstBag and srcSlot == dstSlot then return true end
    ClearCursor()
    PickupContainerItem(srcBag, srcSlot)
    if not CursorHasItem() then return false end
    PickupContainerItem(dstBag, dstSlot)
    if CursorHasItem() then
        PickupContainerItem(srcBag, srcSlot)
    end
    if CursorHasItem() then
        ClearCursor()
        return false
    end
    return true
end

function Orction_TidyBags()
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: cannot tidy bags in combat")
        return
    end
    if CursorHasItem and CursorHasItem() then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: clear cursor before tidying")
        return
    end

    local items = {}
    local slotToItem = {}
    local lockedSlots = {}

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local texture, count, locked = GetContainerItemInfo(bag, slot)
            if locked then
                lockedSlots[bag .. ":" .. slot] = true
            end
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = OrctionBags_GetItemName(link)
                local itemId = OrctionBags_GetItemId(link)
                local itemType, subType
                if itemId and GetItemInfo then
                    local _, _, _, _, _, t, s = GetItemInfo(itemId)
                    itemType = t
                    subType = s
                end
                local cat = OrctionBags_Categorize(name, itemType, subType)
                local idx = table.getn(items) + 1
                items[idx] = {
                    bag = bag, slot = slot, name = name, itemId = itemId,
                    category = cat,
                }
                slotToItem[bag .. ":" .. slot] = idx
            end
        end
    end

    local categoryOrder = { "personal", "quest", "ore", "cloth", "herb", "other" }
    local pickList = {}
    for _, cat in ipairs(categoryOrder) do
        for i, item in ipairs(items) do
            if item.category == cat then
                table.insert(pickList, i)
            end
        end
    end

    local targets = {}
    for bag = 4, 0, -1 do
        local slots = GetContainerNumSlots(bag)
        for slot = slots, 1, -1 do
            local key = bag .. ":" .. slot
            if not lockedSlots[key] then
                table.insert(targets, { bag = bag, slot = slot })
            end
        end
    end

    local pickIdx = 1
    for _, dest in ipairs(targets) do
        local itemIdx = pickList[pickIdx]
        if not itemIdx then break end
        local item = items[itemIdx]
        if item and not (item.bag == dest.bag and item.slot == dest.slot) then
            local srcKey = item.bag .. ":" .. item.slot
            local dstKey = dest.bag .. ":" .. dest.slot
            if OrctionBags_Move(item.bag, item.slot, dest.bag, dest.slot) then
                local dstItemIdx = slotToItem[dstKey]
                if dstItemIdx then
                    items[dstItemIdx].bag = item.bag
                    items[dstItemIdx].slot = item.slot
                    slotToItem[srcKey] = dstItemIdx
                else
                    slotToItem[srcKey] = nil
                end
                item.bag = dest.bag
                item.slot = dest.slot
                slotToItem[dstKey] = itemIdx
            end
        end
        pickIdx = pickIdx + 1
    end

    DEFAULT_CHAT_FRAME:AddMessage("Orction: tidy bags complete")
end

SLASH_ORCTION_TIDYBAGS1 = "/tidybags"
SlashCmdList["ORCTION_TIDYBAGS"] = function()
    Orction_TidyBags()
end
