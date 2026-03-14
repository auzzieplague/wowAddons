local ADDON_NAME = "Orction"
local ORCTION_TAB_INDEX = nil
local orig_AuctionFrameTab_OnClick = nil
local ORCTION_DURATION = 1440  -- 24 hours in minutes

-- ── Helpers ───────────────────────────────────────────────────────────────

local function ResizeMoneyInputFrame(frameName)
    local gold   = getglobal(frameName .. "Gold")
    local silver = getglobal(frameName .. "Silver")
    local copper = getglobal(frameName .. "Copper")
    if gold   then gold:SetWidth(32)   end
    if silver then silver:SetWidth(26) end
    if copper then copper:SetWidth(26) end
end

local function CopperToString(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    return g .. "g " .. s .. "s " .. c .. "c"
end

-- ── AH panel state ────────────────────────────────────────────────────────

local function Orction_UpdateDeposit()
    local deposit = CalculateAuctionDeposit(ORCTION_DURATION) or 0
    OrctionDepositValue:SetText(CopperToString(deposit))
end

local function Orction_UpdateItemSlot()
    local name, texture = GetAuctionSellItemInfo()
    if name then
        OrctionItemTexture:SetTexture(texture)
        OrctionItemTexture:Show()
        OrctionItemName:SetText(name)
        Orction_UpdateDeposit()
    else
        OrctionItemTexture:Hide()
        OrctionItemName:SetText("Drag an item here")
        OrctionDepositValue:SetText("--")
    end
end

local function Orction_CreateAuction()
    local name = GetAuctionSellItemInfo()
    if not name then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: Place an item in the auction slot first.")
        return
    end
    local startBid = MoneyInputFrame_GetCopper(OrctionStartBid)
    local buyout   = MoneyInputFrame_GetCopper(OrctionBuyout)
    if buyout > 0 and startBid > buyout then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: Starting price cannot exceed buyout price.")
        return
    end
    StartAuction(startBid, buyout, ORCTION_DURATION)
end

-- ── Build the AH panel ────────────────────────────────────────────────────

local function Orction_BuildAHPanel()
    OrctionAHPanel = CreateFrame("Frame", "OrctionAHPanel", AuctionFrame)
    OrctionAHPanel:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 0, 0)
    OrctionAHPanel:SetWidth(AuctionFrame:GetWidth())
    OrctionAHPanel:SetHeight(AuctionFrame:GetHeight())
    OrctionAHPanel:SetFrameLevel(AuctionFrameAuctions:GetFrameLevel() + 20)

    -- Opaque background covers any bleed-through from Blizzard frames below
    local bg = OrctionAHPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    bg:SetAllPoints(OrctionAHPanel)

    OrctionAHPanel:Hide()

    -- ── Left panel: all elements within x = 0-150 ────────────────────────
    -- Anchored from TOPLEFT, stacked vertically

    local X       = 29   -- left margin
    local Y       = -115 -- top of content (below AH title bar)
    local LABEL_H = 16   -- font string height
    local GAP     = 8    -- gap between label and its input
    local ROW_SEP = 10   -- gap between rows

    -- Item slot
    local itemLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    itemLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", X, Y)
    itemLabel:SetText("Auction Item")

    local itemSlot = CreateFrame("Button", "OrctionItemSlot", OrctionAHPanel)
    itemSlot:SetWidth(64)
    itemSlot:SetHeight(64)
    itemSlot:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 0, -GAP)
    itemSlot:RegisterForDrag("LeftButton")
    itemSlot:EnableMouse(true)

    local slotBg = itemSlot:CreateTexture(nil, "BACKGROUND")
    slotBg:SetTexture("Interface\\Buttons\\UI-Slot-Background")
    slotBg:SetAllPoints()

    OrctionItemTexture = itemSlot:CreateTexture("OrctionItemTexture", "ARTWORK")
    OrctionItemTexture:SetWidth(64)
    OrctionItemTexture:SetHeight(64)
    OrctionItemTexture:SetPoint("TOPLEFT", itemSlot, "TOPLEFT", 0, 0)
    OrctionItemTexture:Hide()

    local slotHighlight = itemSlot:CreateTexture(nil, "OVERLAY")
    slotHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    slotHighlight:SetAllPoints()
    slotHighlight:SetBlendMode("ADD")
    itemSlot:SetHighlightTexture(slotHighlight)

    itemSlot:SetScript("OnClick", function()
        ClickAuctionSellItemButton()
        ClearCursor()
    end)
    itemSlot:SetScript("OnReceiveDrag", function()
        ClickAuctionSellItemButton()
        ClearCursor()
    end)
    itemSlot:SetScript("OnEnter", function()
        local name = GetAuctionSellItemInfo()
        if name then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetAuctionSellItem()
            GameTooltip:Show()
        end
    end)
    itemSlot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    OrctionItemName = OrctionAHPanel:CreateFontString("OrctionItemName", "ARTWORK", "GameFontHighlightSmall")
    OrctionItemName:SetPoint("TOPLEFT", itemSlot, "BOTTOMLEFT", 0, -GAP)
    OrctionItemName:SetText("Drag an item here")

    -- Starting Price
    local startLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    startLabel:SetPoint("TOPLEFT", OrctionItemName, "BOTTOMLEFT", 0, -ROW_SEP)
    startLabel:SetText("Starting Price")

    OrctionStartBid = CreateFrame("Frame", "OrctionStartBid", OrctionAHPanel, "MoneyInputFrameTemplate")
    OrctionStartBid:SetPoint("TOPLEFT", startLabel, "BOTTOMLEFT", 0, -GAP)
    ResizeMoneyInputFrame("OrctionStartBid")

    -- Buyout Price
    local buyoutLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    buyoutLabel:SetPoint("TOPLEFT", OrctionStartBid, "BOTTOMLEFT", 0, -ROW_SEP)
    buyoutLabel:SetText("Buyout Price")

    OrctionBuyout = CreateFrame("Frame", "OrctionBuyout", OrctionAHPanel, "MoneyInputFrameTemplate")
    OrctionBuyout:SetPoint("TOPLEFT", buyoutLabel, "BOTTOMLEFT", 0, -GAP)
    ResizeMoneyInputFrame("OrctionBuyout")

    -- Deposit
    local depositLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    depositLabel:SetPoint("TOPLEFT", OrctionBuyout, "BOTTOMLEFT", 0, -ROW_SEP)
    depositLabel:SetText("Deposit")

    OrctionDepositValue = OrctionAHPanel:CreateFontString("OrctionDepositValue", "ARTWORK", "GameFontHighlightSmall")
    OrctionDepositValue:SetPoint("TOPLEFT", depositLabel, "BOTTOMLEFT", 0, -GAP)
    OrctionDepositValue:SetText("--")

    -- Create Auction button
    local createBtn = CreateFrame("Button", "OrctionCreateBtn", OrctionAHPanel, "UIPanelButtonTemplate")
    createBtn:SetWidth(110)
    createBtn:SetHeight(22)
    createBtn:SetPoint("TOPLEFT", OrctionDepositValue, "BOTTOMLEFT", 0, -ROW_SEP)
    createBtn:SetText("Create Auction")
    createBtn:SetScript("OnClick", Orction_CreateAuction)

    -- ── Listen for item slot changes ──────────────────────────────────────

    OrctionAHPanel:RegisterEvent("NEW_AUCTION_UPDATE")
    OrctionAHPanel:SetScript("OnEvent", function()
        if event == "NEW_AUCTION_UPDATE" then
            Orction_UpdateItemSlot()
        end
    end)
end


-- ── Tab click hook ────────────────────────────────────────────────────────

local function Orction_OnTabClick(index)
    if not index then
        index = this:GetID()
    end

    if index == ORCTION_TAB_INDEX then
        orig_AuctionFrameTab_OnClick(3)
        PanelTemplates_SetTab(AuctionFrame, ORCTION_TAB_INDEX)
        AuctionFrameAuctions:Hide()
        OrctionAHPanel:Show()
        Orction_UpdateItemSlot()
    else
        OrctionAHPanel:Hide()
        orig_AuctionFrameTab_OnClick(index)
    end
end

local function Orction_SetupAH()
    Orction_BuildAHPanel()
    AuctionFrameAuctions:Hide()

    local n = AuctionFrame.numTabs + 1
    ORCTION_TAB_INDEX = n

    local tab = CreateFrame("Button", "AuctionFrameTab"..n, AuctionFrame, "AuctionTabTemplate")
    tab:SetID(n)
    tab:SetText("Orction")
    tab:SetPoint("LEFT", getglobal("AuctionFrameTab"..(n - 1)), "RIGHT", -8, 0)
    tab:Show()

    PanelTemplates_SetNumTabs(AuctionFrame, n)
    PanelTemplates_EnableTab(AuctionFrame, n)

    orig_AuctionFrameTab_OnClick = AuctionFrameTab_OnClick
    AuctionFrameTab_OnClick = Orction_OnTabClick
end

-- ── Debug output capture ──────────────────────────────────────────────────

local orctionChatLines = {}

local function Orction_StripCodes(msg)
    msg = string.gsub(msg, "|c%x%x%x%x%x%x%x%x", "")
    msg = string.gsub(msg, "|r", "")
    msg = string.gsub(msg, "|H[^|]+|h([^|]+)|h", "%1")
    return msg
end

local function Orction_RefreshDebugBox()
    if OrctionDebugEditBox then
        OrctionDebugEditBox:SetText(table.concat(orctionChatLines, "\n"))
    end
end

local function Orction_HookChat()
    local orig = DEFAULT_CHAT_FRAME.AddMessage
    DEFAULT_CHAT_FRAME.AddMessage = function(self, msg, r, g, b, id)
        orig(self, msg, r, g, b, id)
        local clean = Orction_StripCodes(msg or "")
        table.insert(orctionChatLines, clean)
        while table.getn(orctionChatLines) > 300 do
            table.remove(orctionChatLines, 1)
        end
        if OrctionFrame:IsShown() then
            Orction_RefreshDebugBox()
        end
    end
end

-- ── Standalone window (/orction) ──────────────────────────────────────────

local OrctionFrame = CreateFrame("Frame", "OrctionFrame", UIParent)
OrctionFrame:SetWidth(460)
OrctionFrame:SetHeight(440)
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
OrctionFrame:SetScript("OnShow", function() Orction_RefreshDebugBox() end)
OrctionFrame:Hide()

local titleBar = OrctionFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(256)
titleBar:SetHeight(64)
titleBar:SetPoint("TOP", OrctionFrame, "TOP", 0, 12)

local titleText = OrctionFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
titleText:SetPoint("TOP", OrctionFrame, "TOP", 0, -14)
titleText:SetText("Orction Debug Output")

local closeBtn = CreateFrame("Button", nil, OrctionFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", OrctionFrame, "TOPRIGHT", -3, -3)

-- ScrollFrame containing the copyable EditBox
local scrollFrame = CreateFrame("ScrollFrame", "OrctionDebugScroll", OrctionFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     OrctionFrame, "TOPLEFT",     14, -40)
scrollFrame:SetPoint("BOTTOMRIGHT", OrctionFrame, "BOTTOMRIGHT", -30, 40)

OrctionDebugEditBox = CreateFrame("EditBox", "OrctionDebugEditBox", scrollFrame)
OrctionDebugEditBox:SetWidth(390)
OrctionDebugEditBox:SetHeight(2000)
OrctionDebugEditBox:SetMultiLine(true)
OrctionDebugEditBox:SetAutoFocus(false)
OrctionDebugEditBox:SetMaxLetters(0)
OrctionDebugEditBox:SetFontObject(GameFontHighlightSmall)
OrctionDebugEditBox:SetText("")
scrollFrame:SetScrollChild(OrctionDebugEditBox)

local clearBtn = CreateFrame("Button", nil, OrctionFrame, "UIPanelButtonTemplate")
clearBtn:SetWidth(80)
clearBtn:SetHeight(22)
clearBtn:SetPoint("BOTTOMLEFT", OrctionFrame, "BOTTOMLEFT", 14, 12)
clearBtn:SetText("Clear")
clearBtn:SetScript("OnClick", function()
    orctionChatLines = {}
    OrctionDebugEditBox:SetText("")
end)

-- ── Slash command ─────────────────────────────────────────────────────────

SLASH_ORCTION1 = "/orction"
SlashCmdList["ORCTION"] = function()
    if OrctionFrame:IsShown() then
        OrctionFrame:Hide()
    else
        OrctionFrame:Show()
    end
end

-- ── Events ────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_NAME .. " initialised")
            Orction_HookChat()
        elseif string.lower(arg1) == "blizzard_auctionui" then
            Orction_SetupAH()
            eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        AuctionFrameAuctions:Hide()
    end
end)
