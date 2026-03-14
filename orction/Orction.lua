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
        Orction_UpdateDeposit()
    else
        OrctionItemTexture:Hide()
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

    -- ── Left panel: absolute positions cloned from AuctionFrameAuctions children ─
    -- All SetPoint anchors are relative to OrctionAHPanel TOPLEFT (= AuctionFrame TOPLEFT).
    -- x/y values match the dump output so elements land on the same background areas.

    -- Item slot  (Blizzard AuctionsItemButton: x=27 y=98 w=37 h=37)
    -- We use 52x52; shift left by 8px so the slot is centred over the same spot.
    local itemLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    itemLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 27, -78)
    itemLabel:SetText("Auction Item")

    local itemSlot = CreateFrame("Button", "OrctionItemSlot", OrctionAHPanel)
    itemSlot:SetWidth(60)
    itemSlot:SetHeight(60)
    itemSlot:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 27, -95)
    itemSlot:RegisterForDrag("LeftButton")
    itemSlot:EnableMouse(true)

    local slotBg = itemSlot:CreateTexture(nil, "BACKGROUND")
    slotBg:SetTexture("Interface\\Buttons\\UI-Slot-Background")
    slotBg:SetAllPoints()

    OrctionItemTexture = itemSlot:CreateTexture("OrctionItemTexture", "ARTWORK")
    OrctionItemTexture:SetWidth(38)
    OrctionItemTexture:SetHeight(38)
    OrctionItemTexture:SetPoint("TOPLEFT", itemSlot, "TOPLEFT", 0, 0)
    OrctionItemTexture:Hide()


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

    -- Starting Price  (Blizzard StartPrice: x=34 y=183)
    local startLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    startLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -148)
    startLabel:SetText("Starting Price")

    OrctionStartBid = CreateFrame("Frame", "OrctionStartBid", OrctionAHPanel, "MoneyInputFrameTemplate")
    OrctionStartBid:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -163)
    ResizeMoneyInputFrame("OrctionStartBid")

    -- Duration  (Blizzard: Short x=34 y=238, Medium y=254, Long y=270, all w=16 h=16)
    local durationLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    durationLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -200)
    durationLabel:SetText("Duration")

    local OrctionShortBtn, OrctionMediumBtn, OrctionLongBtn

    OrctionShortBtn = CreateFrame("CheckButton", "OrctionShortBtn", OrctionAHPanel, "UIRadioButtonTemplate")
    OrctionShortBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -215)
    OrctionShortBtn:SetScript("OnClick", function()
        ORCTION_DURATION = 720
        OrctionMediumBtn:SetChecked(false)
        OrctionLongBtn:SetChecked(false)
        Orction_UpdateDeposit()
    end)
    local shortLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    shortLabel:SetPoint("LEFT", OrctionShortBtn, "RIGHT", 4, 0)
    shortLabel:SetText("12h")

    OrctionMediumBtn = CreateFrame("CheckButton", "OrctionMediumBtn", OrctionAHPanel, "UIRadioButtonTemplate")
    OrctionMediumBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -230)
    OrctionMediumBtn:SetScript("OnClick", function()
        ORCTION_DURATION = 1440
        OrctionShortBtn:SetChecked(false)
        OrctionLongBtn:SetChecked(false)
        Orction_UpdateDeposit()
    end)
    local mediumLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    mediumLabel:SetPoint("LEFT", OrctionMediumBtn, "RIGHT", 4, 0)
    mediumLabel:SetText("24h")

    OrctionLongBtn = CreateFrame("CheckButton", "OrctionLongBtn", OrctionAHPanel, "UIRadioButtonTemplate")
    OrctionLongBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -245)
    OrctionLongBtn:SetScript("OnClick", function()
        ORCTION_DURATION = 2880
        OrctionShortBtn:SetChecked(false)
        OrctionMediumBtn:SetChecked(false)
        Orction_UpdateDeposit()
    end)
    local longLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    longLabel:SetPoint("LEFT", OrctionLongBtn, "RIGHT", 4, 0)
    longLabel:SetText("48h")

    OrctionMediumBtn:SetChecked(true)  -- default 24h

    -- Buyout Price  (Blizzard BuyoutPrice: x=33 y=343)
    local buyoutLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    buyoutLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 33, -308)
    buyoutLabel:SetText("Buyout Price")

    OrctionBuyout = CreateFrame("Frame", "OrctionBuyout", OrctionAHPanel, "MoneyInputFrameTemplate")
    OrctionBuyout:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 33, -323)
    ResizeMoneyInputFrame("OrctionBuyout")

    -- Create Auction button  (Blizzard AuctionsCreateAuctionButton: x=18 y=388 w=191 h=20)
    local createBtn = CreateFrame("Button", "OrctionCreateBtn", OrctionAHPanel, "UIPanelButtonTemplate")
    createBtn:SetWidth(191)
    createBtn:SetHeight(20)
    createBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 18, -388)
    createBtn:SetText("Create Auction")
    createBtn:SetScript("OnClick", Orction_CreateAuction)

    -- Deposit  (Blizzard AuctionsDepositMoneyFrame: x=92 y=404)
    local depositLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    depositLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 30, -362)
    depositLabel:SetText("Deposit:")

    OrctionDepositValue = OrctionAHPanel:CreateFontString("OrctionDepositValue", "ARTWORK", "GameFontHighlightSmall")
    OrctionDepositValue:SetPoint("LEFT", depositLabel, "RIGHT", 6, 0)
    OrctionDepositValue:SetText("--")

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

local function Orction_DumpAuctionsChildren()
    local af    = AuctionFrame
    local afL   = af:GetLeft()
    local afT   = af:GetTop()
    DEFAULT_CHAT_FRAME:AddMessage("ORCTION DUMP: AuctionFrameAuctions children")
    local children = {AuctionFrameAuctions:GetChildren()}
    for i = 1, table.getn(children) do
        local c = children[i]
        local name = c:GetName() or ("(unnamed#"..i..")")
        local l = c:GetLeft()
        local t = c:GetTop()
        local w = c:GetWidth()
        local h = c:GetHeight()
        local rx = l and afL and math.floor(l - afL) or "?"
        local ry = t and afT and math.floor(afT - t) or "?"
        DEFAULT_CHAT_FRAME:AddMessage(
            name .. " | x=" .. rx .. " y=" .. ry ..
            " w=" .. math.floor(w or 0) .. " h=" .. math.floor(h or 0)
        )
    end
end

local function Orction_SetupAH()
    Orction_BuildAHPanel()
    Orction_DumpAuctionsChildren()
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
