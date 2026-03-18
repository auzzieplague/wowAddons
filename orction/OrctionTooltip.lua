-- OrctionTooltip.lua
-- Adds vendor sell price to bag item tooltips when tooltip feature is enabled.
-- Hooks ContainerFrameItemButton_OnEnter (requires full game restart to take effect).

if not Orction_FormatMoney then
    function Orction_FormatMoney(copper)
        local c = tonumber(copper) or 0
        if c < 0 then c = 0 end
        local g = math.floor(c / 10000)
        local s = math.floor(math.mod(c, 10000) / 100)
        local x = math.mod(c, 100)
        local parts = {}
        if g > 0 then
            table.insert(parts, "|cFFFFFFFF" .. tostring(g) .. "|r|cFFFFD700g|r")
        end
        if s > 0 then
            table.insert(parts, "|cFFFFFFFF" .. tostring(s) .. "|r|cFFC0C0C0s|r")
        end
        if x > 0 or table.getn(parts) == 0 then
            table.insert(parts, "|cFFFFFFFF" .. tostring(x) .. "|r|cFFB87333c|r")
        end
        return table.concat(parts, " ")
    end
end

local function OrctionTooltip_GetItemName(tooltip)
    if not tooltip then return nil end
    local name = tooltip:GetName()
    local nameFs = name and getglobal(name .. "TextLeft1") or getglobal("GameTooltipTextLeft1")
    if not nameFs then return nil end
    local itemName = nameFs:GetText()
    if not itemName or itemName == "" then return nil end
    return itemName
end

local orctionTooltipState = {
    itemId = nil,
    name = nil,
    lastShift = false,
    elapsed = 0,
}

local function OrctionTooltip_ParseItemId(link)
    if not link then return nil end
    local id = string.match(link, "item:(%d+)")
    if id then return tonumber(id) end
    return nil
end

local function OrctionTooltip_GetHistory(itemId, name)
    if OrctionData_GetItemHistory then
        return OrctionData_GetItemHistory(itemId, name)
    end
    return nil
end

local function OrctionTooltip_GetGraph()
    if not OrctionTooltipGraph then
        OrctionTooltipGraph = OrctionBarGraph_Create(UIParent, 200, 44)
    end
    return OrctionTooltipGraph
end

local function OrctionTooltip_ShowGraph(tooltip, entry)
    if not entry then return end
    local values = {}
    local counts = {}
    local hasData = false
    for d = 1, 7 do
        local pKey = "day" .. d .. "Price"
        local cKey = "day" .. d .. "Count"
        local pVal = entry[pKey] or 0
        local cVal = entry[cKey] or 0
        values[d] = pVal
        counts[d] = cVal
        if pVal > 0 and cVal > 0 then
            hasData = true
        end
    end
    if not hasData then return end

    local graph = OrctionTooltip_GetGraph()
    graph.frame:SetParent(tooltip)
    graph.frame:ClearAllPoints()
    graph.frame:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)
    graph.frame:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", 0, -2)
    graph:SetData(values, {"1","2","3","4","5","6","7"}, "positive", counts)
end

local function OrctionTooltip_HideGraph()
    if OrctionTooltipGraph and OrctionTooltipGraph.frame then
        OrctionTooltipGraph:Hide()
    end
end

local function OrctionTooltip_UpdateShift()
    if not GameTooltip or not GameTooltip:IsShown() then
        OrctionTooltip_HideGraph()
        return
    end
    local shift = IsShiftKeyDown and IsShiftKeyDown() or false
    if shift == orctionTooltipState.lastShift then return end
    orctionTooltipState.lastShift = shift
    if not shift then
        OrctionTooltip_HideGraph()
        return
    end
    local entry = OrctionTooltip_GetHistory(orctionTooltipState.itemId, orctionTooltipState.name)
    OrctionTooltip_ShowGraph(GameTooltip, entry)
end

local function OrctionTooltip_Apply(tooltip, itemName, context, stackCount, itemId)
    if not (OrctionDB and OrctionDB.settings and OrctionDB.settings.tooltipEnabled) then return end
    local tip = tooltip or GameTooltip
    local name = itemName or OrctionTooltip_GetItemName(tip)
    if not name then return end
    orctionTooltipState.itemId = itemId or orctionTooltipState.itemId
    orctionTooltipState.name = name

    local price = OrctionVendor_GetPrice(name)
    if price and price > 0 then
        local count = tonumber(stackCount) or 1
        if count > 1 then
            tip:AddLine(
                Orction_FormatMoney(price) ..
                " [" .. Orction_FormatMoney(price * count) .. "]",
                1, 0.82, 0)
        else
            tip:AddLine(Orction_FormatMoney(price), 1, 0.82, 0)
        end
    end
    if IsShiftKeyDown and IsShiftKeyDown() then
        orctionTooltipState.lastShift = true
        local entry = OrctionTooltip_GetHistory(orctionTooltipState.itemId, name)
        OrctionTooltip_ShowGraph(tip, entry)
    else
        orctionTooltipState.lastShift = false
        OrctionTooltip_HideGraph()
    end
    tip:Show()
end

local orig_ContainerFrameItemButton_OnEnter = ContainerFrameItemButton_OnEnter
ContainerFrameItemButton_OnEnter = function()
    orig_ContainerFrameItemButton_OnEnter()
    local count = nil
    local itemId = nil
    if this and this.GetID and this.GetParent and this:GetParent() and this:GetParent().GetID then
        local bag = this:GetParent():GetID()
        local slot = this:GetID()
        if bag and slot then
            local _, c = GetContainerItemInfo(bag, slot)
            count = c
            local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
            itemId = OrctionTooltip_ParseItemId(link)
        end
    end
    OrctionTooltip_Apply(GameTooltip, nil, "bag", count, itemId)
end

-- Mail attachments (postal / inbox)
if InboxFrameItemButton_OnEnter then
    local orig_InboxFrameItemButton_OnEnter = InboxFrameItemButton_OnEnter
    InboxFrameItemButton_OnEnter = function(...)
        local ret = orig_InboxFrameItemButton_OnEnter(unpack(arg))
        local count = nil
        local itemId = nil
        if this and this.GetParent then
            local idx = nil
            if this.GetID then idx = this:GetID() end
            if not idx and this:GetParent() and this:GetParent().GetID then
                idx = this:GetParent():GetID()
            end
            if idx and GetInboxItem then
                local _, _, c = GetInboxItem(idx)
                count = c
                if GetInboxItemLink then
                    local link = GetInboxItemLink(idx)
                    itemId = OrctionTooltip_ParseItemId(link)
                end
            end
        end
        OrctionTooltip_Apply(GameTooltip, nil, "mail", count, itemId)
        return ret
    end
end

if GameTooltip and GameTooltip.SetInboxItem then
    local orig_SetInboxItem = GameTooltip.SetInboxItem
    GameTooltip.SetInboxItem = function(self, index)
        local ret = orig_SetInboxItem(self, index)
        local count = nil
        local itemId = nil
        if index and GetInboxItem then
            local _, _, c = GetInboxItem(index)
            count = c
            if GetInboxItemLink then
                local link = GetInboxItemLink(index)
                itemId = OrctionTooltip_ParseItemId(link)
            end
        end
        OrctionTooltip_Apply(self, nil, "mail", count, itemId)
        return ret
    end
end

-- Auction House item tooltips (browse/bid/auction tabs)
if AuctionFrameItem_OnEnter then
    local orig_AuctionFrameItem_OnEnter = AuctionFrameItem_OnEnter
    AuctionFrameItem_OnEnter = function(...)
        local ret = orig_AuctionFrameItem_OnEnter(unpack(arg))
        local count = nil
        local itemId = nil
        if this and this.GetID then
            local idx = this:GetID()
            if idx and GetAuctionItemInfo then
                local _, _, c = GetAuctionItemInfo("list", idx)
                count = c
            end
            if idx and GetAuctionItemLink then
                local link = GetAuctionItemLink("list", idx)
                itemId = OrctionTooltip_ParseItemId(link)
            end
        end
        OrctionTooltip_Apply(GameTooltip, nil, "auction", count, itemId)
        return ret
    end
end

if GameTooltip then
    local orig_OnHide = GameTooltip:GetScript("OnHide")
    GameTooltip:SetScript("OnHide", function()
        OrctionTooltip_HideGraph()
        if orig_OnHide then orig_OnHide() end
    end)

    local orig_OnUpdate = GameTooltip:GetScript("OnUpdate")
    GameTooltip:SetScript("OnUpdate", function()
        if orig_OnUpdate then orig_OnUpdate() end
        orctionTooltipState.elapsed = orctionTooltipState.elapsed + (arg1 or 0)
        if orctionTooltipState.elapsed < 0.1 then return end
        orctionTooltipState.elapsed = 0
        OrctionTooltip_UpdateShift()
    end)
end
