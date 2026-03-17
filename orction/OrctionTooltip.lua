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

local function OrctionTooltip_Apply(tooltip, itemName, context, stackCount)
    if not (OrctionDB and OrctionDB.settings and OrctionDB.settings.tooltipEnabled) then return end
    local tip = tooltip or GameTooltip
    local name = itemName or OrctionTooltip_GetItemName(tip)
    if not name then return end

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
    -- Future: add auction data lines here (e.g. "Sells for:")
    tip:Show()
end

local orig_ContainerFrameItemButton_OnEnter = ContainerFrameItemButton_OnEnter
ContainerFrameItemButton_OnEnter = function()
    orig_ContainerFrameItemButton_OnEnter()
    local count = nil
    if this and this.GetID and this.GetParent and this:GetParent() and this:GetParent().GetID then
        local bag = this:GetParent():GetID()
        local slot = this:GetID()
        if bag and slot then
            local _, c = GetContainerItemInfo(bag, slot)
            count = c
        end
    end
    OrctionTooltip_Apply(GameTooltip, nil, "bag", count)
end

-- Mail attachments (postal / inbox)
if InboxFrameItemButton_OnEnter then
    local orig_InboxFrameItemButton_OnEnter = InboxFrameItemButton_OnEnter
    InboxFrameItemButton_OnEnter = function(...)
        local ret = orig_InboxFrameItemButton_OnEnter(unpack(arg))
        local count = nil
        if this and this.GetParent then
            local idx = nil
            if this.GetID then idx = this:GetID() end
            if not idx and this:GetParent() and this:GetParent().GetID then
                idx = this:GetParent():GetID()
            end
            if idx and GetInboxItem then
                local _, _, c = GetInboxItem(idx)
                count = c
            end
        end
        OrctionTooltip_Apply(GameTooltip, nil, "mail", count)
        return ret
    end
end

if GameTooltip and GameTooltip.SetInboxItem then
    local orig_SetInboxItem = GameTooltip.SetInboxItem
    GameTooltip.SetInboxItem = function(self, index)
        local ret = orig_SetInboxItem(self, index)
        local count = nil
        if index and GetInboxItem then
            local _, _, c = GetInboxItem(index)
            count = c
        end
        OrctionTooltip_Apply(self, nil, "mail", count)
        return ret
    end
end

-- Auction House item tooltips (browse/bid/auction tabs)
if AuctionFrameItem_OnEnter then
    local orig_AuctionFrameItem_OnEnter = AuctionFrameItem_OnEnter
    AuctionFrameItem_OnEnter = function(...)
        local ret = orig_AuctionFrameItem_OnEnter(unpack(arg))
        local count = nil
        if this and this.GetID then
            local idx = this:GetID()
            if idx and GetAuctionItemInfo then
                local _, _, c = GetAuctionItemInfo("list", idx)
                count = c
            end
        end
        OrctionTooltip_Apply(GameTooltip, nil, "auction", count)
        return ret
    end
end
