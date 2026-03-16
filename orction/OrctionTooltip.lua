-- OrctionTooltip.lua
-- Adds vendor sell price to bag item tooltips when tooltip feature is enabled.
-- Hooks ContainerFrameItemButton_OnEnter (requires full game restart to take effect).

local function OrctionTooltip_FormatCopper(copper)
    if not copper or copper <= 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    local out = ""
    if g > 0 then out = out .. g .. "g " end
    if s > 0 then out = out .. s .. "s " end
    if c > 0 or out == "" then out = out .. c .. "c" end
    return string.gsub(out, "%s$", "")
end

local function OrctionTooltip_AddVendorPrice()
    if not (OrctionDB and OrctionDB.settings and OrctionDB.settings.tooltipEnabled) then return end

    local nameFs = getglobal("GameTooltipTextLeft1")
    if not nameFs then return end
    local itemName = nameFs:GetText()
    if not itemName or itemName == "" then return end

    local price = OrctionVendor_GetPrice(itemName)
    if not price or price <= 0 then return end

    GameTooltip:AddLine("Vendor: " .. OrctionTooltip_FormatCopper(price), 1, 0.82, 0)
    GameTooltip:Show()
end

local orig_ContainerFrameItemButton_OnEnter = ContainerFrameItemButton_OnEnter
ContainerFrameItemButton_OnEnter = function()
    orig_ContainerFrameItemButton_OnEnter()
    OrctionTooltip_AddVendorPrice()
end
