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
    bgFile   = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true,
    tileSize = 32,
    edgeSize = 32,
    insets   = { left = 11, right = 12, top = 12, bottom = 11 },
})
OrctionFrame:SetBackdropColor(0.12, 0.12, 0.12, 1)

-------------------------------------------------------------------------------
-- Title bar texture + title text
-------------------------------------------------------------------------------

local titleBar = OrctionFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(256)
titleBar:SetHeight(64)
titleBar:SetPoint("TOP", OrctionFrame, "TOP", 0, 12)

local titleText = OrctionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", OrctionFrame, "TOP", 0, 6)
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
local dataPanel       = CreateContentPanel("OrctionDataPanel")
local devPanel        = CreateContentPanel("OrctionDevPanel")
local creditsPanel    = CreateContentPanel("OrctionCreditsPanel")

-- Table for easy indexed access
local orctionPanels = { auctionPanel, postPanel, inventoryPanel, dataPanel, devPanel, creditsPanel }

-------------------------------------------------------------------------------
-- Tab buttons
-------------------------------------------------------------------------------

local tabLabels = { "Auction", "Post", "Inventory", "Data", "Dev", "Credits" }

OrctionFrame.numTabs = 6
PanelTemplates_SetNumTabs(OrctionFrame, 6)

for i = 1, 6 do
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
    for i = 1, 6 do
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

-- Enable checkbox (left column)
local auctionEnabledCheck = CreateFrame("CheckButton", "OrctionAuctionEnabledCheck", auctionPanel, "OptionsCheckButtonTemplate")
auctionEnabledCheck:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 10, -10)
getglobal("OrctionAuctionEnabledCheckText"):SetText("Enable Auction Features")

auctionEnabledCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.auctionEnabled = (this:GetChecked() == 1)
    end
end)

local autoOpenTabCheck = CreateFrame("CheckButton", "OrctionAutoOpenTabCheck", auctionPanel, "OptionsCheckButtonTemplate")
autoOpenTabCheck:SetPoint("TOPLEFT", auctionEnabledCheck, "BOTTOMLEFT", 0, -6)
getglobal("OrctionAutoOpenTabCheckText"):SetText("Auto-open Orction tab when AH opens")

autoOpenTabCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.autoOpenTab = (this:GetChecked() == 1)
    end
end)

-- Feature description box (read-only)
local auctionDesc = CreateFrame("EditBox", nil, auctionPanel)
auctionDesc:SetMultiLine(true)
auctionDesc:SetWidth(230)
auctionDesc:SetHeight(60)
auctionDesc:SetPoint("TOPLEFT", autoOpenTabCheck, "BOTTOMLEFT", 0, -10)
auctionDesc:SetFontObject("GameFontHighlightSmall")
auctionDesc:EnableMouse(false)
auctionDesc:EnableKeyboard(false)
auctionDesc:SetAutoFocus(false)
auctionDesc:SetText("- Compare market price before posting\n- Automatic stack posting\n- Vendor profit snatching")

local titleCaseCheck = CreateFrame("CheckButton", "OrctionTitleCaseSearchCheck", auctionPanel, "OptionsCheckButtonTemplate")
titleCaseCheck:SetPoint("TOPLEFT", auctionDesc, "BOTTOMLEFT", 0, -8)
getglobal("OrctionTitleCaseSearchCheckText"):SetText("Title-case text search terms")

titleCaseCheck:SetScript("OnClick", function()
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.titleCaseSearch = (this:GetChecked() == 1)
    end
end)

-- "Pages to Scan" label
local pagesLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pagesLabel:SetPoint("TOPLEFT", titleCaseCheck, "BOTTOMLEFT", 0, -12)
pagesLabel:SetText("Pages to Scan")

-- Slider
local pagesSlider = CreateFrame("Slider", "OrctionPagesSlider", auctionPanel, "OptionsSliderTemplate")
pagesSlider:SetWidth(150)
pagesSlider:SetPoint("TOPLEFT", pagesLabel, "BOTTOMLEFT", 0, -6)
pagesSlider:SetMinMaxValues(1, 10)
pagesSlider:SetValueStep(1)
pagesSlider:SetValue(3)

-- Slider low/high labels (set via the template globals)
getglobal("OrctionPagesSliderLow"):SetText("1")
getglobal("OrctionPagesSliderHigh"):SetText("10")

-- Current value display next to slider
local pagesValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
pagesValueText:SetPoint("LEFT", pagesSlider, "RIGHT", 6, 0)
pagesValueText:SetText("3")

pagesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    pagesValueText:SetText(tostring(val))
    ORCTION_MAX_PAGES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.maxPages = val
    end
end)

-- "Retry Delay" label
local retryDelayLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
retryDelayLabel:SetPoint("TOPLEFT", auctionPanel, "TOPLEFT", 270, -10)
retryDelayLabel:SetText("Page Delay (s)")

-- Retry delay slider (3000–10000 ms in 1s steps)
local retryDelaySlider = CreateFrame("Slider", "OrctionRetryDelaySlider", auctionPanel, "OptionsSliderTemplate")
retryDelaySlider:SetWidth(150)
retryDelaySlider:SetPoint("TOPLEFT", retryDelayLabel, "BOTTOMLEFT", 0, -6)
retryDelaySlider:SetMinMaxValues(3000, 10000)
retryDelaySlider:SetValueStep(1000)
retryDelaySlider:SetValue(5000)

getglobal("OrctionRetryDelaySliderLow"):SetText("3s")
getglobal("OrctionRetryDelaySliderHigh"):SetText("10s")

local retryDelayValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
retryDelayValueText:SetPoint("LEFT", retryDelaySlider, "RIGHT", 6, 0)
retryDelayValueText:SetText("5s")

retryDelaySlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() / 1000 + 0.5) * 1000
    retryDelayValueText:SetText(math.floor(val / 1000) .. "s")
    ORCTION_RETRY_DELAY = val / 1000
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.retryDelay = val
    end
end)

-- "Max Retries" label
local maxRetriesLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
maxRetriesLabel:SetPoint("TOPLEFT", retryDelaySlider, "BOTTOMLEFT", 0, -12)
maxRetriesLabel:SetText("Max Retries")

-- Max retries slider (0–5, step 1)
local maxRetriesSlider = CreateFrame("Slider", "OrctionMaxRetriesSlider", auctionPanel, "OptionsSliderTemplate")
maxRetriesSlider:SetWidth(150)
maxRetriesSlider:SetPoint("TOPLEFT", maxRetriesLabel, "BOTTOMLEFT", 0, -6)
maxRetriesSlider:SetMinMaxValues(0, 5)
maxRetriesSlider:SetValueStep(1)
maxRetriesSlider:SetValue(2)

getglobal("OrctionMaxRetriesSliderLow"):SetText("0")
getglobal("OrctionMaxRetriesSliderHigh"):SetText("5")

local maxRetriesValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
maxRetriesValueText:SetPoint("LEFT", maxRetriesSlider, "RIGHT", 6, 0)
maxRetriesValueText:SetText("2")

maxRetriesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    maxRetriesValueText:SetText(tostring(val))
    ORCTION_MAX_RETRIES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.maxRetries = val
    end
end)

-- "Data Cache" label
local dataCacheLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dataCacheLabel:SetPoint("TOPLEFT", maxRetriesSlider, "BOTTOMLEFT", 0, -12)
dataCacheLabel:SetText("Data Cache (hours)")

-- Data cache slider (1–24 hours, step 1)
local dataCacheSlider = CreateFrame("Slider", "OrctionDataCacheSlider", auctionPanel, "OptionsSliderTemplate")
dataCacheSlider:SetWidth(150)
dataCacheSlider:SetPoint("TOPLEFT", dataCacheLabel, "BOTTOMLEFT", 0, -6)
dataCacheSlider:SetMinMaxValues(1, 24)
dataCacheSlider:SetValueStep(1)
dataCacheSlider:SetValue(1)

getglobal("OrctionDataCacheSliderLow"):SetText("1")
getglobal("OrctionDataCacheSliderHigh"):SetText("24")

local dataCacheValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dataCacheValueText:SetPoint("LEFT", dataCacheSlider, "RIGHT", 6, 0)
dataCacheValueText:SetText("1")

dataCacheSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    dataCacheValueText:SetText(tostring(val))
    ORCTION_DATA_CACHE_HOURS = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.dataCacheHours = val
    end
end)

-- "Vendor Price Multiplier" label
local vendorMultLabel = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
vendorMultLabel:SetPoint("TOPLEFT", dataCacheSlider, "BOTTOMLEFT", 0, -12)
vendorMultLabel:SetText("No-Results Price (x vendor)")

-- Slider: 2x–8x vendor price, step 0.5
local vendorMultSlider = CreateFrame("Slider", "OrctionVendorMultSlider", auctionPanel, "OptionsSliderTemplate")
vendorMultSlider:SetWidth(150)
vendorMultSlider:SetPoint("TOPLEFT", vendorMultLabel, "BOTTOMLEFT", 0, -6)
vendorMultSlider:SetMinMaxValues(2, 8)
vendorMultSlider:SetValueStep(0.5)
vendorMultSlider:SetValue(5)

getglobal("OrctionVendorMultSliderLow"):SetText("2x")
getglobal("OrctionVendorMultSliderHigh"):SetText("8x")

local vendorMultValueText = auctionPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
vendorMultValueText:SetPoint("LEFT", vendorMultSlider, "RIGHT", 6, 0)
vendorMultValueText:SetText("5x")

vendorMultSlider:SetScript("OnValueChanged", function()
    -- Round to nearest 0.5
    local raw = this:GetValue()
    local val = math.floor(raw * 2 + 0.5) / 2
    vendorMultValueText:SetText(val .. "x")
    ORCTION_VENDOR_MULTIPLIER = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.vendorMultiplier = val
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

-- "Mail Open Delay" label
local mailDelayLabel = postPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mailDelayLabel:SetPoint("TOPLEFT", postEnabledCheck, "BOTTOMLEFT", 0, -14)
mailDelayLabel:SetText("Mail Open Delay (ms)")

-- Slider: 100–2000 ms, step 100
local mailDelaySlider = CreateFrame("Slider", "OrctionMailDelaySlider", postPanel, "OptionsSliderTemplate")
mailDelaySlider:SetWidth(200)
mailDelaySlider:SetPoint("TOPLEFT", mailDelayLabel, "BOTTOMLEFT", 0, -6)
mailDelaySlider:SetMinMaxValues(100, 2000)
mailDelaySlider:SetValueStep(100)
mailDelaySlider:SetValue(500)

getglobal("OrctionMailDelaySliderLow"):SetText("100")
getglobal("OrctionMailDelaySliderHigh"):SetText("2000")

local mailDelayValueText = postPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mailDelayValueText:SetPoint("LEFT", mailDelaySlider, "RIGHT", 10, 0)
mailDelayValueText:SetText("500")

mailDelaySlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() / 100 + 0.5) * 100
    mailDelayValueText:SetText(tostring(val))
    ORCTION_MAIL_OPEN_DELAY = val / 1000
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.mailOpenDelay = val
    end
end)

-- "Mail Open Retries" label
local mailRetriesLabel = postPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
mailRetriesLabel:SetPoint("TOPLEFT", mailDelaySlider, "BOTTOMLEFT", 0, -16)
mailRetriesLabel:SetText("Mail Open Retries")

-- Slider: 0–5, step 1
local mailRetriesSlider = CreateFrame("Slider", "OrctionMailRetriesSlider", postPanel, "OptionsSliderTemplate")
mailRetriesSlider:SetWidth(200)
mailRetriesSlider:SetPoint("TOPLEFT", mailRetriesLabel, "BOTTOMLEFT", 0, -6)
mailRetriesSlider:SetMinMaxValues(0, 5)
mailRetriesSlider:SetValueStep(1)
mailRetriesSlider:SetValue(2)

getglobal("OrctionMailRetriesSliderLow"):SetText("0")
getglobal("OrctionMailRetriesSliderHigh"):SetText("5")

local mailRetriesValueText = postPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mailRetriesValueText:SetPoint("LEFT", mailRetriesSlider, "RIGHT", 10, 0)
mailRetriesValueText:SetText("2")

mailRetriesSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    mailRetriesValueText:SetText(tostring(val))
    ORCTION_MAIL_OPEN_RETRIES = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.mailOpenRetries = val
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
-- TAB 4: Data
-------------------------------------------------------------------------------

local dataSearchText = ""
local dataPage = 1
local dataPageSize = 10
local dataRows = {}

local function OrctionSettings_GetDaySlot()
    local day = tonumber(date("%j")) or 1
    return math.mod(day, 7) + 1
end

local function OrctionSettings_GetDataKeys()
    local keys = {}
    if OrctionDB and OrctionDB.priceHistory then
        for k, v in pairs(OrctionDB.priceHistory) do
            local name = v and v.name or ""
            if dataSearchText == "" or string.find(string.lower(name), string.lower(dataSearchText), 1, true) then
                table.insert(keys, k)
            end
        end
    end
    table.sort(keys)
    return keys
end

local function OrctionSettings_RefreshData()
    local keys = OrctionSettings_GetDataKeys()
    local total = table.getn(keys)
    local maxPage = math.max(1, math.ceil(total / dataPageSize))
    if dataPage > maxPage then dataPage = maxPage end
    if dataPage < 1 then dataPage = 1 end

    local startIdx = (dataPage - 1) * dataPageSize + 1

    for i = 1, dataPageSize do
        local row = dataRows[i]
        local idx = startIdx + i - 1
        if row and idx <= total then
            local key = keys[idx]
            local entry = OrctionDB.priceHistory[key]
            row.name:SetText(entry.name or "")
            local weeklySum = 0
            for d = 1, 7 do
                local pKey = "day" .. d .. "Price"
                local cKey = "day" .. d .. "Count"
                local cVal = entry[cKey] or 0
                local pVal = entry[pKey] or 0
                if row.dayCells and row.dayCells[d] then
                    if cVal > 0 then
                        row.dayCells[d]:SetText(tostring(cVal))
                    else
                        row.dayCells[d]:SetText("-")
                    end
                end
                if cVal > 0 and pVal > 0 then
                    weeklySum = weeklySum + (cVal * pVal)
                end
            end
            if row.value then
                row.value:SetText(tostring(math.floor(weeklySum / 7)))
            end
            row.frame:Show()
        elseif row then
            row.frame:Hide()
        end
    end

    if OrctionDataPageText then
        OrctionDataPageText:SetText("Page " .. dataPage .. " / " .. maxPage)
    end
end

local dataSearchBox = CreateFrame("EditBox", "OrctionDataSearchBox", dataPanel, "InputBoxTemplate")
dataSearchBox:SetWidth(80)
dataSearchBox:SetHeight(22)
dataSearchBox:SetPoint("TOPLEFT", dataPanel, "TOPLEFT", 10, -10)
dataSearchBox:SetAutoFocus(false)
dataSearchBox:SetScript("OnEnterPressed", function()
    dataSearchText = this:GetText() or ""
    dataPage = 1
    OrctionSettings_RefreshData()
    this:ClearFocus()
end)

local dataSearchBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
dataSearchBtn:SetWidth(60)
dataSearchBtn:SetHeight(22)
dataSearchBtn:SetPoint("LEFT", dataSearchBox, "RIGHT", 6, 0)
dataSearchBtn:SetText("Search")
dataSearchBtn:SetScript("OnClick", function()
    dataSearchText = dataSearchBox:GetText() or ""
    dataPage = 1
    OrctionSettings_RefreshData()
end)

local dataOffsetLabel = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dataOffsetLabel:SetPoint("LEFT", dataSearchBtn, "RIGHT", 20, 0)
dataOffsetLabel:SetText("Day Offset")

local dataOffsetSlider = CreateFrame("Slider", "OrctionDataOffsetSlider", dataPanel, "OptionsSliderTemplate")
dataOffsetSlider:SetWidth(120)
dataOffsetSlider:SetPoint("LEFT", dataOffsetLabel, "RIGHT", 8, 0)
dataOffsetSlider:SetMinMaxValues(0, 6)
dataOffsetSlider:SetValueStep(1)
dataOffsetSlider:SetValue(0)

getglobal("OrctionDataOffsetSliderLow"):SetText("0")
getglobal("OrctionDataOffsetSliderHigh"):SetText("6")

local dataOffsetValueText = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dataOffsetValueText:SetPoint("LEFT", dataOffsetSlider, "RIGHT", 6, 0)
dataOffsetValueText:SetText("0")

dataOffsetSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    dataOffsetValueText:SetText(tostring(val))
    ORCTION_DAY_OFFSET = val
    if OrctionDB and OrctionDB.settings then
        OrctionDB.settings.dayOffset = val
    end
end)

local purgeBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
purgeBtn:SetWidth(90)
purgeBtn:SetHeight(22)
purgeBtn:SetText("Purge Data")
purgeBtn:SetScript("OnClick", function()
    if OrctionDB then OrctionDB.priceHistory = {} end
    OrctionSettings_RefreshData()
end)

local analyzeBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
analyzeBtn:SetWidth(90)
analyzeBtn:SetHeight(22)
analyzeBtn:SetText("Analyze")
analyzeBtn:SetScript("OnClick", function()
    DEFAULT_CHAT_FRAME:AddMessage("Orction: analyze data not implemented")
end)

local headerName = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerName:SetPoint("TOPLEFT", dataPanel, "TOPLEFT", 10, -42)
headerName:SetText("Name")

local dayHeaders = {}
for i = 1, 7 do
    local h = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if i == 1 then
        h:SetPoint("LEFT", headerName, "RIGHT", 100, 0)
    else
        h:SetPoint("LEFT", dayHeaders[i - 1], "RIGHT", 20, 0)
    end
    h:SetText(tostring(i))
    dayHeaders[i] = h
end

local headerValue = dataPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
headerValue:SetPoint("LEFT", dayHeaders[7], "RIGHT", 20, 0)
headerValue:SetText("Value")

local rowsFrame = CreateFrame("Frame", nil, dataPanel)
rowsFrame:SetWidth(480)
rowsFrame:SetHeight(240)
rowsFrame:SetPoint("TOPLEFT", dataPanel, "TOPLEFT", 10, -60)

for i = 1, dataPageSize do
    local row = CreateFrame("Frame", nil, rowsFrame)
    row:SetWidth(480)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", rowsFrame, "TOPLEFT", 0, -(i - 1) * 20)

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetWidth(100)
    name:SetJustifyH("LEFT")

    local dayCells = {}
    for d = 1, 7 do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if d == 1 then
            cell:SetPoint("LEFT", name, "RIGHT", 10, 0)
        else
            cell:SetPoint("LEFT", dayCells[d - 1], "RIGHT", 12, 0)
        end
        cell:SetWidth(20)
        cell:SetJustifyH("RIGHT")
        dayCells[d] = cell
    end

    local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    value:SetPoint("LEFT", dayCells[7], "RIGHT", 8, 0)
    value:SetWidth(40)
    value:SetJustifyH("RIGHT")

    row.name = name
    row.dayCells = dayCells
    row.value = value
    row.frame = row
    row:Hide()
    dataRows[i] = row
end

local prevBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
prevBtn:SetWidth(60)
prevBtn:SetHeight(20)
prevBtn:SetPoint("TOPLEFT", rowsFrame, "BOTTOMLEFT", 0, -8)
prevBtn:SetText("Prev")
prevBtn:SetScript("OnClick", function()
    dataPage = dataPage - 1
    OrctionSettings_RefreshData()
end)

local nextBtn = CreateFrame("Button", nil, dataPanel, "UIPanelButtonTemplate")
nextBtn:SetWidth(60)
nextBtn:SetHeight(20)
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
nextBtn:SetText("Next")
nextBtn:SetScript("OnClick", function()
    dataPage = dataPage + 1
    OrctionSettings_RefreshData()
end)

OrctionDataPageText = dataPanel:CreateFontString("OrctionDataPageText", "OVERLAY", "GameFontHighlightSmall")
OrctionDataPageText:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)
OrctionDataPageText:SetText("Page 1 / 1")
purgeBtn:SetPoint("BOTTOMRIGHT", OrctionFrame, "BOTTOMRIGHT", -110, 12)
analyzeBtn:SetPoint("LEFT", purgeBtn, "RIGHT", 6, 0)

-------------------------------------------------------------------------------
-- TAB 5: Dev
-------------------------------------------------------------------------------

local devTitle = devPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
devTitle:SetPoint("TOPLEFT", devPanel, "TOPLEFT", 10, -10)
devTitle:SetText("Icon Picker (Item IDs)")

local devIconBtn = CreateFrame("Button", nil, devPanel)
devIconBtn:SetWidth(40)
devIconBtn:SetHeight(40)
devIconBtn:SetPoint("TOPLEFT", devTitle, "BOTTOMLEFT", 0, -10)

local devIconTex = devIconBtn:CreateTexture(nil, "ARTWORK")
devIconTex:SetAllPoints(devIconBtn)
devIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

local devNameText = devPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
devNameText:SetPoint("LEFT", devIconBtn, "RIGHT", 10, 6)
devNameText:SetText("Item not cached")

local devDetailText = devPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
devDetailText:SetPoint("TOPLEFT", devNameText, "BOTTOMLEFT", 0, -2)
devDetailText:SetText("ID: 1")

local devPathText = devPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
devPathText:SetPoint("TOPLEFT", devDetailText, "BOTTOMLEFT", 0, -2)
devPathText:SetText("")

local devItemIdLabel = devPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
devItemIdLabel:SetPoint("TOPLEFT", devIconBtn, "BOTTOMLEFT", 0, -12)
devItemIdLabel:SetText("Item ID")

local devItemIdBox = CreateFrame("EditBox", "OrctionDevItemIdBox", devPanel, "InputBoxTemplate")
devItemIdBox:SetWidth(80)
devItemIdBox:SetHeight(20)
devItemIdBox:SetPoint("LEFT", devItemIdLabel, "RIGHT", 8, 0)
devItemIdBox:SetAutoFocus(false)
devItemIdBox:SetText("1")

local devItemIdSlider = CreateFrame("Slider", "OrctionDevItemIdSlider", devPanel, "OptionsSliderTemplate")
devItemIdSlider:SetWidth(220)
devItemIdSlider:SetPoint("TOPLEFT", devItemIdLabel, "BOTTOMLEFT", 0, -8)
devItemIdSlider:SetMinMaxValues(1, 30000)
devItemIdSlider:SetValueStep(1)
devItemIdSlider:SetValue(1)

getglobal("OrctionDevItemIdSliderLow"):SetText("1")
getglobal("OrctionDevItemIdSliderHigh"):SetText("30000")

local devItemIdValueText = devPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
devItemIdValueText:SetPoint("LEFT", devItemIdSlider, "RIGHT", 8, 0)
devItemIdValueText:SetText("1")

local devTooltip = CreateFrame("GameTooltip", "OrctionDevTooltip", UIParent, "GameTooltipTemplate")
devTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local devPendingId = nil
local devPendingElapsed = 0

local fstackCheck = CreateFrame("CheckButton", "OrctionDevFstackCheck", devPanel, "OptionsCheckButtonTemplate")
fstackCheck:SetPoint("TOPLEFT", devItemIdSlider, "BOTTOMLEFT", 0, -12)
getglobal("OrctionDevFstackCheckText"):SetText("Enable /fstack overlay")
fstackCheck:SetScript("OnClick", function()
    if Orction_FStack_SetEnabled then
        Orction_FStack_SetEnabled(this:GetChecked() == 1)
    end
end)

local function OrctionDev_RequestItemInfo(id)
    devTooltip:SetHyperlink("item:" .. id)
    devTooltip:Hide()
end

local function OrctionDev_UpdateItemInfo(id, noRequest)
    local name, link, quality, level, minLevel, itemType, subType, stack, equipLoc, texture = GetItemInfo(id)
    if not name then
        devIconTex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        devNameText:SetText("Item not cached")
        devDetailText:SetText("ID: " .. id)
        devPathText:SetText("")
        if not noRequest then
            devPendingId = id
            devPendingElapsed = 0
            OrctionDev_RequestItemInfo(id)
        end
        return
    end

    devPendingId = nil
    devIconTex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    devNameText:SetText(name)
    devDetailText:SetText("ID: " .. id .. "  " .. (itemType or "") .. " / " .. (subType or ""))
    devPathText:SetText(texture or "")
end

devItemIdBox:SetScript("OnEnterPressed", function()
    local v = tonumber(this:GetText())
    if not v then
        this:ClearFocus()
        return
    end
    if v < 1 then v = 1 end
    if v > 30000 then v = 30000 end
    devItemIdSlider:SetValue(v)
    this:ClearFocus()
end)

devItemIdSlider:SetScript("OnValueChanged", function()
    local val = math.floor(this:GetValue() + 0.5)
    devItemIdValueText:SetText(tostring(val))
    devItemIdBox:SetText(tostring(val))
    OrctionDev_UpdateItemInfo(val)
end)

local devTimer = CreateFrame("Frame")
devTimer:SetScript("OnUpdate", function()
    if not devPendingId then return end
    devPendingElapsed = devPendingElapsed + (arg1 or 0)
    if devPendingElapsed < 0.2 then return end
    devPendingElapsed = 0
    local name = GetItemInfo(devPendingId)
    if name then
        OrctionDev_UpdateItemInfo(devPendingId, true)
    else
        OrctionDev_RequestItemInfo(devPendingId)
    end
end)

OrctionDev_UpdateItemInfo(1)

-------------------------------------------------------------------------------
-- TAB 6: Credits
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
    if s.autoOpenTab      then OrctionAutoOpenTabCheck:SetChecked(1)      else OrctionAutoOpenTabCheck:SetChecked(nil)      end
    if s.postEnabled      then OrctionPostEnabledCheck:SetChecked(1)      else OrctionPostEnabledCheck:SetChecked(nil)      end
    if s.inventoryEnabled then OrctionInventoryEnabledCheck:SetChecked(1) else OrctionInventoryEnabledCheck:SetChecked(nil) end
    if s.tooltipEnabled   then OrctionTooltipEnabledCheck:SetChecked(1)  else OrctionTooltipEnabledCheck:SetChecked(nil)  end
    if s.titleCaseSearch  then OrctionTitleCaseSearchCheck:SetChecked(1) else OrctionTitleCaseSearchCheck:SetChecked(nil) end

    -- Sliders
    local pages = s.maxPages or 3
    pagesSlider:SetValue(pages)
    pagesValueText:SetText(tostring(pages))

    local rd = s.retryDelay or 5000
    retryDelaySlider:SetValue(rd)
    retryDelayValueText:SetText(math.floor(rd / 1000) .. "s")

    local mr = s.maxRetries or 2
    maxRetriesSlider:SetValue(mr)
    maxRetriesValueText:SetText(tostring(mr))

    local dch = s.dataCacheHours or 1
    dataCacheSlider:SetValue(dch)
    dataCacheValueText:SetText(tostring(dch))

    local md = s.mailOpenDelay or 500
    mailDelaySlider:SetValue(md)
    mailDelayValueText:SetText(tostring(md))

    local mrt = s.mailOpenRetries or 2
    mailRetriesSlider:SetValue(mrt)
    mailRetriesValueText:SetText(tostring(mrt))

    local off = s.dayOffset or 0
    dataOffsetSlider:SetValue(off)
    dataOffsetValueText:SetText(tostring(off))

    local vm = s.vendorMultiplier or 5.0
    vendorMultSlider:SetValue(vm)
    vendorMultValueText:SetText(vm .. "x")

    -- Re-apply duration button highlights when settings window opens
    local dur = s.auctionDuration or 2
    for j = 1, 3 do
        local bj = getglobal("OrctionDurBtn"..j)
        if bj then
            if j == dur then bj:GetFontString():SetTextColor(1, 0.82, 0)
            else              bj:GetFontString():SetTextColor(1, 1, 1) end
        end
    end
end

OrctionFrame:SetScript("OnShow", function()
    OrctionSettings_ApplyToUI()
    OrctionSettings_RefreshData()
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
        if s.autoOpenTab      == nil then s.autoOpenTab      = true  end
        if s.postEnabled      == nil then s.postEnabled      = true  end
        if s.inventoryEnabled == nil then s.inventoryEnabled = true  end
        if s.tooltipEnabled   == nil then s.tooltipEnabled   = true  end
        if s.titleCaseSearch  == nil then s.titleCaseSearch  = true  end
        if s.maxPages         == nil then s.maxPages         = 3     end
        if s.exactMatch       == nil then s.exactMatch       = true  end
        if s.retryDelay       == nil then s.retryDelay       = 5000  end
        if s.maxRetries       == nil then s.maxRetries       = 2     end
        if s.dataCacheHours   == nil then s.dataCacheHours   = 1     end
        if s.dayOffset        == nil then s.dayOffset        = 0     end
        if s.mailOpenDelay    == nil then s.mailOpenDelay    = 500   end
        if s.mailOpenRetries  == nil then s.mailOpenRetries  = 2     end
        if s.vendorMultiplier == nil then s.vendorMultiplier = 5.0   end
        if s.auctionDuration  == nil then s.auctionDuration  = 2     end

        -- Sync exact match checkbox
        if OrctionExactMatchCheck then
            if s.exactMatch then OrctionExactMatchCheck:SetChecked(1)
            else                 OrctionExactMatchCheck:SetChecked(nil) end
        end

        -- Sync globals used by Orction.lua and OrctionPostbox.lua
        ORCTION_MAX_PAGES         = s.maxPages
        ORCTION_RETRY_DELAY       = s.retryDelay / 1000
        ORCTION_MAX_RETRIES       = s.maxRetries
        ORCTION_DATA_CACHE_HOURS  = s.dataCacheHours
        ORCTION_DAY_OFFSET        = s.dayOffset
        ORCTION_MAIL_OPEN_DELAY   = s.mailOpenDelay / 1000
        ORCTION_MAIL_OPEN_RETRIES = s.mailOpenRetries
        ORCTION_VENDOR_MULTIPLIER = s.vendorMultiplier
        ORCTION_AUCTION_DURATION  = s.auctionDuration

        -- Ensure persistent tables exist
        if not OrctionDB.vendorPrices then OrctionDB.vendorPrices = {} end
        if not OrctionDB.watchlist     then OrctionDB.watchlist     = {} end
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

-------------------------------------------------------------------------------
-- Debug: /fstack — show hovered frame name
-------------------------------------------------------------------------------

local orctionFStackEnabled = false
local orctionFStackLast    = nil
local orctionFStackElapsed = 0
local orctionFStackFrame   = CreateFrame("Frame")
orctionFStackFrame:SetScript("OnUpdate", function()
    if not orctionFStackEnabled then return end
    orctionFStackElapsed = orctionFStackElapsed + (arg1 or 0)
    if orctionFStackElapsed < 0.1 then return end
    orctionFStackElapsed = 0
    local f = GetMouseFocus and GetMouseFocus() or nil
    if f == orctionFStackLast then return end
    orctionFStackLast = f
    local name    = f and f.GetName    and f:GetName()    or "nil"
    local ftype   = f and f.GetObjectType and f:GetObjectType() or "?"
    local parent  = f and f.GetParent  and f:GetParent()  or nil
    local pname   = parent and parent.GetName and parent:GetName() or "nil"
    local w       = f and f.GetWidth   and math.floor(f:GetWidth()  + 0.5) or "?"
    local h       = f and f.GetHeight  and math.floor(f:GetHeight() + 0.5) or "?"
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(name, 1, 1, 0)
    GameTooltip:AddLine("Type: "   .. ftype,          1, 1, 1)
    GameTooltip:AddLine("Parent: " .. pname,           0.8, 0.8, 0.8)
    GameTooltip:AddLine("Size: "   .. w .. " x " .. h, 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

SLASH_ORCTION_FSTACK1 = "/fstack"
function Orction_FStack_SetEnabled(enabled)
    orctionFStackEnabled = enabled and true or false
    if not orctionFStackEnabled then
        orctionFStackLast = nil
        GameTooltip:Hide()
        DEFAULT_CHAT_FRAME:AddMessage("Orction: fstack off")
    else
        DEFAULT_CHAT_FRAME:AddMessage("Orction: fstack on (hover to see frame)")
    end
    if OrctionDevFstackCheck then
        if orctionFStackEnabled then OrctionDevFstackCheck:SetChecked(1)
        else OrctionDevFstackCheck:SetChecked(nil) end
    end
end

SlashCmdList["ORCTION_FSTACK"] = function()
    Orction_FStack_SetEnabled(not orctionFStackEnabled)
end
