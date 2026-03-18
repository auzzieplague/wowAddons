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

local function OrctionTooltip_ParseItemId(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    if id then return tonumber(id) end
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
    graph:SetSize(180, 38)
    local w = tonumber(date("%w")) or 0
    local todayIndex = w + 1
    local labelColors = {}
    labelColors[todayIndex] = { 1, 0.82, 0 }
    graph:SetData(values, {"S","M","T","W","T","F","S"}, "positive", counts, {
        showLabels = true,
        todayIndex = todayIndex,
        labelColors = labelColors,
    })
end

local function OrctionTooltip_HideGraph()
    if OrctionTooltipGraph and OrctionTooltipGraph.frame then
        OrctionTooltipGraph:Hide()
    end
end

local function OrctionTooltip_Apply(tooltip, itemName, context, stackCount, itemId)
    if not (OrctionDB and OrctionDB.settings and OrctionDB.settings.tooltipEnabled) then return end
    local tip = tooltip or GameTooltip
    local name = itemName or OrctionTooltip_GetItemName(tip)
    if not name then return end

    local price = OrctionVendor_GetPrice(name, itemId)
    if price and price > 0 then
        if not (tip.OrctionVendorDone and tip.OrctionVendorItem == name) then
            local count = tonumber(stackCount) or 1
            if count > 1 then
                tip:AddLine(
                    Orction_FormatMoney(price) ..
                    " [" .. Orction_FormatMoney(price * count) .. "]",
                    1, 0.82, 0)
            else
                tip:AddLine(Orction_FormatMoney(price), 1, 0.82, 0)
            end
            tip.OrctionVendorDone = true
            tip.OrctionVendorItem = name
        end
    end

    -- Today's average AH price from price history
    local entry = OrctionData_GetItemHistory and OrctionData_GetItemHistory(itemId, name) or nil
    if entry then
        local day    = tonumber(date("%j")) or 1
        local offset = ORCTION_DAY_OFFSET or 0
        local slot   = math.mod(day + offset, 7) + 1
        local pVal   = entry["day" .. slot .. "Price"] or 0
        local cVal   = entry["day" .. slot .. "Count"] or 0
        if pVal > 0 and cVal > 0 then
            local dayName = date("%A")
            tip:AddLine(dayName .. ":  " .. Orction_FormatMoney(pVal), 0.5, 0.85, 1)
        end
    end

    if IsShiftKeyDown and IsShiftKeyDown() then
        OrctionTooltip_ShowGraph(tip, entry)
    else
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

-- Quest reward/quest log tooltips
if GameTooltip and GameTooltip.SetQuestItem then
    local orig_SetQuestItem = GameTooltip.SetQuestItem
    GameTooltip.SetQuestItem = function(self, questType, index)
        local ret = orig_SetQuestItem(self, questType, index)
        local itemId = nil
        local name = nil
        if GetQuestItemLink then
            local link = GetQuestItemLink(questType, index)
            itemId = OrctionTooltip_ParseItemId(link)
        end
        if GetQuestItemInfo then
            name = GetQuestItemInfo(questType, index)
        end
        OrctionTooltip_Apply(self, name, "quest", nil, itemId)
        return ret
    end
end

if GameTooltip and GameTooltip.SetQuestLogItem then
    local orig_SetQuestLogItem = GameTooltip.SetQuestLogItem
    GameTooltip.SetQuestLogItem = function(self, itemType, index)
        local ret = orig_SetQuestLogItem(self, itemType, index)
        local itemId = nil
        local name = nil
        if GetQuestLogItemLink then
            local link = GetQuestLogItemLink(itemType, index)
            itemId = OrctionTooltip_ParseItemId(link)
        end
        if GetQuestLogItemInfo then
            name = GetQuestLogItemInfo(itemType, index)
        end
        OrctionTooltip_Apply(self, name, "questlog", nil, itemId)
        return ret
    end
end

if QuestLogItem_OnEnter then
    local orig_QuestLogItem_OnEnter = QuestLogItem_OnEnter
    QuestLogItem_OnEnter = function(...)
        local ret = orig_QuestLogItem_OnEnter(unpack(arg))
        local idx = this and this.GetID and this:GetID() or nil
        if idx then
            local itemId = nil
            local name = nil
            if GetQuestLogItemLink then
                local link = GetQuestLogItemLink("reward", idx)
                itemId = OrctionTooltip_ParseItemId(link)
            end
            if GetQuestLogItemInfo then
                name = GetQuestLogItemInfo("reward", idx)
            end
            OrctionTooltip_Apply(GameTooltip, name, "questlog", nil, itemId)
        end
        return ret
    end
end

local function OrctionTooltip_HookQuestLogRewardButtons()
    if not QuestLogFrame then return end
    for i = 1, 10 do
        local btn = getglobal("QuestLogItem" .. i)
        if btn and not btn.OrctionHooked then
            btn.OrctionHooked = true
            btn.OrctionOrigOnEnter = btn:GetScript("OnEnter")
            btn.OrctionOrigOnLeave = btn:GetScript("OnLeave")
            btn:SetScript("OnEnter", function()
                if btn.OrctionOrigOnEnter then
                    btn.OrctionOrigOnEnter()
                elseif GameTooltip and GameTooltip.SetQuestLogItem then
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                    local idx = btn.GetID and btn:GetID() or i
                    GameTooltip:SetQuestLogItem("reward", idx)
                end
                local idx = btn.GetID and btn:GetID() or i
                local itemId = nil
                local name = nil
                if GetQuestLogItemLink then
                    local link = GetQuestLogItemLink("reward", idx)
                    itemId = OrctionTooltip_ParseItemId(link)
                end
                if GetQuestLogItemInfo then
                    name = GetQuestLogItemInfo("reward", idx)
                end
                OrctionTooltip_Apply(GameTooltip, name, "questlog", nil, itemId)
            end)
            btn:SetScript("OnLeave", function()
                if btn.OrctionOrigOnLeave then
                    btn.OrctionOrigOnLeave()
                elseif GameTooltip then
                    GameTooltip:Hide()
                end
            end)
        end
    end
end

local questLogHookFrame = CreateFrame("Frame")
questLogHookFrame:RegisterEvent("QUEST_LOG_UPDATE")
questLogHookFrame:SetScript("OnEvent", function()
    OrctionTooltip_HookQuestLogRewardButtons()
end)

-- Merchant tooltips
if GameTooltip and GameTooltip.SetMerchantItem then
    local orig_SetMerchantItem = GameTooltip.SetMerchantItem
    GameTooltip.SetMerchantItem = function(self, index)
        local ret = orig_SetMerchantItem(self, index)
        local itemId = nil
        local name = nil
        if GetMerchantItemLink then
            local link = GetMerchantItemLink(index)
            itemId = OrctionTooltip_ParseItemId(link)
        end
        if GetMerchantItemInfo then
            name = GetMerchantItemInfo(index)
        end
        OrctionTooltip_Apply(self, name, "merchant", nil, itemId)
        return ret
    end
end

if GameTooltip then
    local orig_OnHide = GameTooltip:GetScript("OnHide")
    GameTooltip:SetScript("OnHide", function()
        OrctionTooltip_HideGraph()
        GameTooltip.OrctionVendorDone = nil
        GameTooltip.OrctionVendorItem = nil
        if orig_OnHide then orig_OnHide() end
    end)
end
