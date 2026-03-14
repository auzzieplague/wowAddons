local ADDON_NAME = "Orction"

-- Main window
local OrctionFrame = CreateFrame("Frame", "OrctionFrame", UIParent)
OrctionFrame:SetWidth(400)
OrctionFrame:SetHeight(300)
OrctionFrame:SetPoint("CENTER", UIParent, "CENTER")
OrctionFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
OrctionFrame:SetMovable(true)
OrctionFrame:EnableMouse(true)
OrctionFrame:RegisterForDrag("LeftButton")
OrctionFrame:SetScript("OnDragStart", function() this:StartMoving() end)
OrctionFrame:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
OrctionFrame:Hide()

-- Title bar texture
local titleBar = OrctionFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(256)
titleBar:SetHeight(64)
titleBar:SetPoint("TOP", OrctionFrame, "TOP", 0, 12)

-- Title text
local titleText = OrctionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
titleText:SetPoint("TOP", OrctionFrame, "TOP", 0, -14)
titleText:SetText("Orction Helper")

-- Close button
local closeBtn = CreateFrame("Button", nil, OrctionFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", OrctionFrame, "TOPRIGHT", -3, -3)

-- Slash command
SLASH_ORCTION1 = "/orction"
SlashCmdList["ORCTION"] = function()
    if OrctionFrame:IsShown() then
        OrctionFrame:Hide()
    else
        OrctionFrame:Show()
    end
end

-- Init event
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DEFAULT_CHAT_FRAME:AddMessage(ADDON_NAME .. " initialised")
        this:UnregisterEvent("ADDON_LOADED")
    end
end)
