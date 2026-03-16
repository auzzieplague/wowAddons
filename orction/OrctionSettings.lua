-- OrctionSettings.lua
-- Settings window for Orction (TurtleWoW / vanilla 1.12, Lua 5.0)
-- Opens via /orction slash command
-- NOTE: uses `this` / `event` / `arg1` globals in all script handlers (no `self`)

-------------------------------------------------------------------------------
-- Main frame
-------------------------------------------------------------------------------

OrctionFrame = CreateFrame("Frame", "OrctionFrame", UIParent)
OrctionFrame:SetWidth(520)
OrctionFrame:SetHeight(460)
OrctionFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
OrctionFrame:SetFrameStrata("DIALOG")
OrctionFrame:SetMovable(true)
OrctionFrame:EnableMouse(true)
OrctionFrame:SetToplevel(true)
OrctionFrame:Hide()

-- Drag support
OrctionFrame:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" then
        OrctionFrame:StartMoving()
    end
end)
OrctionFrame:SetScript("OnMouseUp", function()
    OrctionFrame:StopMovingOrSizing()
end)

-- Backdrop
OrctionFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true,
    tileSize = 32,
    edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
})

-------------------------------------------------------------------------------
-- Title bar texture + title text
-------------------------------------------------------------------------------

local titleBar = OrctionFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(256)
titleBar:SetHeight(64)
titleBar:SetPoint("TOP", OrctionFrame, "TOP", 0, 12)

local titleText = OrctionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", OrctionFrame, "TOP", 0, -14)
titleText:SetText("Orction")

-------------------------------------------------------------------------------
-- Close button
-------------------------------------------------------------------------------

local closeButton = CreateFrame("Button", "OrctionFrameCloseButton", OrctionFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", OrctionFrame, "TOPRIGHT", -3, -3)
closeButton:SetScript("OnClick", function()
    OrctionFrame:Hide()
end)

-------------------------------------------------------------------------------
-- Tab content panels (created before tabs so tabs can reference them)
-------------------------------------------------------------------------------

-- Helper: create a content panel (child of OrctionFrame, fills the content area)
local function CreateContentPanel(name)
    local panel = CreateFrame("Frame", name, OrctionFrame)
    panel:SetPoint("TOPLEFT",     OrctionFrame, "TOPLEFT",  14, -80)
    panel:SetPoint("BOTTOMRIGHT", OrctionFrame, "BOTTOMRIGHT", -14, 14)
    panel:Hide()
    return panel
end

local auctionPanel    = CreateContentPanel("OrctionAuctionPanel")
local postPanel       = CreateContentPanel("OrctionPostPanel")
local inventoryPanel  = CreateContentPanel("OrctionInventoryPanel")
local creditsPanel    = CreateContentPanel("OrctionCreditsPanel")

-- Table for easy indexed access
local orctionPanels = { auctionPanel, postPanel, inventoryPanel, creditsPanel }

-------------------------------------------------------------------------------
-- Tab buttons
-------------------------------------------------------------------------------

local tabLabels = { "Auction", "Post", "Inventory", "Credits" }

OrctionFrame.numTabs = 4
PanelTemplates_SetNumTabs(OrctionFrame, 4)

for i = 1, 4 do
    local tab = CreateFrame("Button", "OrctionFrameTab"..i, OrctionFrame, "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(tabLabels[i])

    -- Resize tab to fit text (minimum 60 px)
    local textWidth = tab:GetTextWidth()
    local tabWidth  = math.max(textWidth + 24, 60)
    tab:SetWidth(tabWidth)

    if i == 1 then
        tab:SetPoint("TOPLEFT", OrctionFrame, "TOPLEFT", 10, -46)
    else
        local prevTab = getglobal("OrctionFrameTab"..(i-1))
        tab:SetPoint("LEFT", prevTab, "RIGHT", -14, 0)
    end

    tab:SetScript("OnClick", function()
        OrctionSettings_SelectTab(this:GetID())
    end)
end

-------------------------------------------------------------------------------
-- Tab selection function
-------------------------------------------------------------------------------

function OrctionSettings_SelectTab(id)
    -- Hide all panels
    for i = 1, 4 do
        orctionPanels[i]:Hide()
    end
    -- Show the selected panel
    if orctionPanels[id] then
        orctionPanels[id]:Show()
    end
    -- Highlight the correct tab button
    PanelTemplates_SetTab(OrctionFrame, id)
end

-------------------------------------------------------------------------------
-- TAB 1: Auction
-------------------------------------------------------------------------------

-- Enable checkbox
local auctionEnabledCheck = CreateFrame("CheckButton", "OrctionAuctionEnabledCheck", auctionPanel, "OptionsCheckButtonTemplate")
auctionEnabledCheck:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 10, -10)
getglobal("OrctionAuctionEnabledCheckText"):SetText("Enable Auction Features")

auctionEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.auctionEnabled = (this:GetChecked() == 1)
    end
end)

-- Feature description box (read-only)
local auctionDesc = CreateFrame("EditBox", nil, auctionPanel)
auctionDesc:SetMultiLine(true)
auctionDesc:SetWidth(460)
auctionDesc:SetHeight(60)
auctionDesc:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 10, -45)
auctionDesc:SetFontObject("GameFontHighlightSmall")
auctionDesc:EnableMouse(false)
auctionDesc:EnableKeyboard(false)
auctionDesc:SetAutoFocus(false)
auctionDesc:SetText("- Compare market price before posting\n- Automatic stack posting\n- Vendor profit snatching")

-- "Pages to Scan" label
local pagesLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pagesLabel:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 10, -120)
pagesLabel:SetText("Pages to Scan")

-- Slider
local pagesSlider = CreateFrame("Slider", "OrctionPagesSlider", auctionPanel, "OptionsSliderTemplate")
pagesSlider:SetWidth(200)
pagesSlider:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 10, -140)
pagesSlider:SetMinMaxValues(1, 10)
pagesSlider:SetValueStep(1)
pagesSlider:SetValue(3)

-- Slider low/high labels (set via the template globals)
getglobal("OrctionPagesSliderLow"):SetText("1")
getglobal("OrctionPagesSliderHigh"):SetText("10")

-- Current value display next to slider
local pagesValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pagesValueText:SetPoint("LEFT", pagesSlider, "RIGHT", 10, 0)
pagesValueText:SetText("3")

pagesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    pagesValueText:SetText(tostring(val))
    -- Sync to global used by Orction.lua
    ORCTION_MAX_PAGES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.maxPages = val
    end
end)

-------------------------------------------------------------------------------
-- TAB 2: Post
-------------------------------------------------------------------------------

local postEnabledCheck = CreateFrame("CheckButton", "OrctionPostEnabledCheck", postPanel, "OptionsCheckButtonTemplate")
postEnabledCheck:SetPoint("TOPLEFT", postPanel, "TOPLEFT", 10, -10)
getglobal("OrctionPostEnabledCheckText"):SetText("Enable Post Features")

postEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.postEnabled = (this:GetChecked() == 1)
    end
end)

-------------------------------------------------------------------------------
-- TAB 3: Inventory
-------------------------------------------------------------------------------

local inventoryEnabledCheck = CreateFrame("CheckButton", "OrctionInventoryEnabledCheck", inventoryPanel, "OptionsCheckButtonTemplate")
inventoryEnabledCheck:SetPoint("TOPLEFT", inventoryPanel, "TOPLEFT", 10, -10)
getglobal("OrctionInventoryEnabledCheckText"):SetText("Enable Inventory Features")

inventoryEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.inventoryEnabled = (this:GetChecked() == 1)
    end
end)

local tooltipEnabledCheck = CreateFrame("CheckButton", "OrctionTooltipEnabledCheck", inventoryPanel, "OptionsCheckButtonTemplate")
tooltipEnabledCheck:SetPoint("TOPLEFT", inventoryEnabledCheck, "BOTTOMLEFT", 0, -6)
getglobal("OrctionTooltipEnabledCheckText"):SetText("Show vendor price on item tooltip")

tooltipEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.tooltipEnabled = (this:GetChecked() == 1)
    end
end)

-------------------------------------------------------------------------------
-- TAB 4: Credits
-------------------------------------------------------------------------------

local creditsLine1 = creditsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
creditsLine1:SetPoint("TOPLEFT", creditsPanel, "TOPLEFT", 14, -14)
creditsLine1:SetText("Orction by q concerned citizen of Azeroth")

local creditsLine2 = creditsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
creditsLine2:SetPoint("TOPLEFT", creditsLine1, "BOTTOMLEFT", 0, -8)
creditsLine2:SetText("Vendor sell prices provided by SellValue")

local creditsLine3 = creditsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
creditsLine3:SetPoint("TOPLEFT", creditsLine2, "BOTTOMLEFT", 0, -4)
creditsLine3:SetText("github.com/anzz1/SellValue")

-------------------------------------------------------------------------------
-- Clear Cache button (bottom-left of main frame)
-------------------------------------------------------------------------------

local clearCacheBtn = CreateFrame("Button", "OrctionClearCacheButton", OrctionFrame, "UIPanelButtonTemplate")
clearCacheBtn:SetWidth(80)
clearCacheBtn:SetHeight(22)
clearCacheBtn:SetPoint("BOTTOMLEFT", OrctionFrame, "BOTTOMLEFT", 14, 12)
clearCacheBtn:SetText("Clear Cache")

clearCacheBtn:SetScript("OnClick", function()
    if OrctionDB then
        OrctionDB.vendorPrices = {}
    end
    DEFAULT_CHAT_FRAME:AddMessage("Orction: cache cleared")
end)

-------------------------------------------------------------------------------
-- Apply saved settings to UI controls (called on frame OnShow)
-------------------------------------------------------------------------------

local function OrctionSettings_ApplyToUI()
    if not (OrctionDB and OrctionDB.settings) then return end
    local s = OrctionDB.settings

    -- Checkboxes (SetChecked expects 1/nil in 1.12)
    if s.auctionEnabled   then OrctionAuctionEnabledCheck:SetChecked(1)   else OrctionAuctionEnabledCheck:SetChecked(nil)   end
    if s.postEnabled      then OrctionPostEnabledCheck:SetChecked(1)      else OrctionPostEnabledCheck:SetChecked(nil)      end
    if s.inventoryEnabled then OrctionInventoryEnabledCheck:SetChecked(1) else OrctionInventoryEnabledCheck:SetChecked(nil) end
    if s.tooltipEnabled   then OrctionTooltipEnabledCheck:SetChecked(1)  else OrctionTooltipEnabledCheck:SetChecked(nil)  end

    -- Slider
    local pages = s.maxPages or 3
    pagesSlider:SetValue(pages)
    pagesValueText:SetText(tostring(pages))
end

OrctionFrame:SetScript("OnShow", function()
    OrctionSettings_ApplyToUI()
end)

-------------------------------------------------------------------------------
-- ADDON_LOADED: initialise OrctionDB.settings with defaults
-------------------------------------------------------------------------------

local settingsEventFrame = CreateFrame("Frame")
settingsEventFrame:RegisterEvent("ADDON_LOADED")
settingsEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        -- Ensure top-level table exists (Database.lua may have created it)
        if not OrctionDB then
            OrctionDB = {}
        end
        -- Initialise settings with defaults, preserving any already-saved values
        if not OrctionDB.settings then
            OrctionDB.settings = {}
        end
        local s = OrctionDB.settings
        if s.auctionEnabled   == nil then s.auctionEnabled   = true  end
        if s.postEnabled      == nil then s.postEnabled      = true  end
        if s.inventoryEnabled == nil then s.inventoryEnabled = true  end
        if s.tooltipEnabled   == nil then s.tooltipEnabled   = true  end
        if s.maxPages         == nil then s.maxPages         = 3     end

        -- Sync global used by Orction.lua search logic
        ORCTION_MAX_PAGES = s.maxPages
    end
end)

-------------------------------------------------------------------------------
-- Default to tab 1 on first open
-------------------------------------------------------------------------------

OrctionSettings_SelectTab(1)

-------------------------------------------------------------------------------
-- Slash command  /orction  — toggle the settings window
-------------------------------------------------------------------------------

SLASH_ORCTION1 = "/orction"
SlashCmdList["ORCTION"] = function()
    if OrctionFrame:IsShown() then
        OrctionFrame:Hide()
    else
        OrctionFrame:Show()
    end
end
