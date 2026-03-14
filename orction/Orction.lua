local ADDON_NAME = "Orction"
local ORCTION_TAB_INDEX = nil
local orig_AuctionFrameTab_OnClick = nil
local ORCTION_DURATION = 1440  -- 24 hours in minutes

-- ── Search state ───────────────────────────────────────────────────────────
local ORCTION_MAX_PAGES      = 3
local ORCTION_PAGE_SIZE      = 50
local orctionSearchName      = nil
local orctionSearchPage      = 0
local orctionSearchActive    = false
local orctionSearchResults   = {}
local orctionResultRows      = {}
local orctionBuyPending      = nil   -- { buyout = fullBuyoutCopper }
local orctionPageProcessed   = false -- true after first non-zero AUCTION_ITEM_LIST_UPDATE for current page
local orctionSearchRetry     = false -- true when waiting to query the next page
local orctionQueryDelay      = 0     -- seconds accumulated since retry was flagged
local orctionWaitTimeout     = 0     -- seconds waiting for non-zero batch on current page

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

-- ── Search logic ──────────────────────────────────────────────────────────

local function Orction_DisplayResults()
    local groups   = {}
    local groupMap = {}
    for _, item in ipairs(orctionSearchResults) do
        local k = item.costPerItem
        if not groupMap[k] then
            groupMap[k] = { costPerItem = k, totalCount = 0, numAuctions = 0,
                            firstBuyout = item.buyout, firstCount = item.count }
            table.insert(groups, groupMap[k])
        end
        groupMap[k].totalCount  = groupMap[k].totalCount  + item.count
        groupMap[k].numAuctions = groupMap[k].numAuctions + 1
    end
    table.sort(groups, function(a, b) return a.costPerItem < b.costPerItem end)

    -- Reset scroll to top
    local scroll = getglobal("OrctionResultScroll")
    if scroll then scroll:SetVerticalScroll(0) end

    for i = 1, table.getn(orctionResultRows) do
        local row = orctionResultRows[i]
        local g   = groups[i]
        if g then
            row.costPerItem = g.costPerItem
            row.firstBuyout = g.firstBuyout
            row.cost:SetText(CopperToString(g.costPerItem))
            row.qty:SetText(tostring(g.totalCount))
            row.auctions:SetText(tostring(g.numAuctions))
            row.buyBtn:SetText("Buy " .. tostring(g.firstCount))
            row.frame:Show()
        else
            row.costPerItem = nil
            row.firstBuyout = nil
            row.frame:Hide()
        end
    end
end

local function Orction_CollectPage()
    if not orctionSearchActive then return end

    local batch = GetNumAuctionItems("list")

    if batch == 0 then
        -- Blizzard fires a batch=0 event before large result sets are ready on ANY page.
        -- Always wait; the OnUpdate timeout will give up if no data ever arrives.
        return
    end

    if orctionPageProcessed then return end  -- ignore duplicate non-empty firings for this page
    orctionPageProcessed = true
    orctionWaitTimeout   = 0  -- got real data, reset the timeout
    for i = 1, batch do
        local name, texture, count, quality, canUse, level,
              minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
        if buyoutPrice and buyoutPrice > 0 and count and count > 0 then
            table.insert(orctionSearchResults, {
                buyout      = buyoutPrice,
                count       = count,
                costPerItem = math.floor(buyoutPrice / count),
            })
        end
    end

    local nextPage = orctionSearchPage + 1
    if nextPage < ORCTION_MAX_PAGES and batch >= ORCTION_PAGE_SIZE then
        orctionSearchPage  = nextPage
        orctionSearchRetry = true   -- OnUpdate will fire the next query after a short delay
        orctionQueryDelay  = 0
    else
        orctionSearchActive = false
        Orction_DisplayResults()
    end
end

local function Orction_StartSearch(name)
    orctionSearchName    = name
    orctionSearchPage    = 0
    orctionSearchActive  = true
    orctionPageProcessed = false
    orctionSearchRetry   = false
    orctionQueryDelay    = 0
    orctionWaitTimeout   = 0
    orctionSearchResults = {}
    for i = 1, table.getn(orctionResultRows) do
        orctionResultRows[i].frame:Hide()
    end
    QueryAuctionItems(name, nil, nil, nil, nil, nil, 0, nil, nil)
end

local function Orction_TryBuy()
    if not orctionBuyPending then return end
    local batch, total = GetNumAuctionItems("list")
    for i = 1, batch do
        local name, texture, count, quality, canUse, level,
              minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
        if buyoutPrice == orctionBuyPending.buyout then
            PlaceAuctionBid("list", i, buyoutPrice)
            orctionBuyPending = nil
            return
        end
    end
    orctionBuyPending = nil
    DEFAULT_CHAT_FRAME:AddMessage("Orction: Auction not found - it may have sold.")
end

-- ── AH panel state ────────────────────────────────────────────────────────

local function Orction_UpdateDeposit()
    local deposit = CalculateAuctionDeposit(ORCTION_DURATION) or 0
    OrctionDepositValue:SetText(CopperToString(deposit))
end

local function Orction_UpdateItemSlot()
    local name, texture, count = GetAuctionSellItemInfo()
    if name then
        OrctionItemTexture:SetTexture(texture)
        OrctionItemTexture:Show()
        OrctionItemNameText:SetText(name)
        OrctionItemCountBadge:SetText(count and count > 1 and tostring(count) or "")
        Orction_UpdateDeposit()
        Orction_StartSearch(name)
    else
        OrctionItemTexture:Hide()
        OrctionItemNameText:SetText("")
        OrctionItemCountBadge:SetText("")
        OrctionDepositValue:SetText("--")
        for i = 1, table.getn(orctionResultRows) do
            orctionResultRows[i].frame:Hide()
        end
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

    OrctionItemNameText = OrctionAHPanel:CreateFontString("OrctionItemNameText", "ARTWORK", "GameFontHighlight")
    OrctionItemNameText:SetPoint("TOPLEFT", itemSlot, "TOPRIGHT", 8, -4)
    OrctionItemNameText:SetWidth(120)
    OrctionItemNameText:SetText("")

    OrctionItemCountBadge = OrctionAHPanel:CreateFontString("OrctionItemCountBadge", "OVERLAY", "NumberFontNormal")
    OrctionItemCountBadge:SetPoint("BOTTOMRIGHT", itemSlot, "BOTTOMRIGHT", -2, 2)
    OrctionItemCountBadge:SetText("")

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
        ORCTION_DURATION = 360
        OrctionMediumBtn:SetChecked(false)
        OrctionLongBtn:SetChecked(false)
        AuctionsShortAuctionButton:SetChecked(true)
        AuctionsMediumAuctionButton:SetChecked(false)
        AuctionsLongAuctionButton:SetChecked(false)
        Orction_UpdateDeposit()
    end)
    local shortLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    shortLabel:SetPoint("LEFT", OrctionShortBtn, "RIGHT", 4, 0)
    shortLabel:SetText("6h")

    OrctionMediumBtn = CreateFrame("CheckButton", "OrctionMediumBtn", OrctionAHPanel, "UIRadioButtonTemplate")
    OrctionMediumBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -230)
    OrctionMediumBtn:SetScript("OnClick", function()
        ORCTION_DURATION = 1440
        OrctionShortBtn:SetChecked(false)
        OrctionLongBtn:SetChecked(false)
        AuctionsShortAuctionButton:SetChecked(false)
        AuctionsMediumAuctionButton:SetChecked(true)
        AuctionsLongAuctionButton:SetChecked(false)
        Orction_UpdateDeposit()
    end)
    local mediumLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    mediumLabel:SetPoint("LEFT", OrctionMediumBtn, "RIGHT", 4, 0)
    mediumLabel:SetText("24h")

    OrctionLongBtn = CreateFrame("CheckButton", "OrctionLongBtn", OrctionAHPanel, "UIRadioButtonTemplate")
    OrctionLongBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -245)
    OrctionLongBtn:SetScript("OnClick", function()
        ORCTION_DURATION = 4320
        OrctionShortBtn:SetChecked(false)
        OrctionMediumBtn:SetChecked(false)
        AuctionsShortAuctionButton:SetChecked(false)
        AuctionsMediumAuctionButton:SetChecked(false)
        AuctionsLongAuctionButton:SetChecked(true)
        Orction_UpdateDeposit()
    end)
    local longLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    longLabel:SetPoint("LEFT", OrctionLongBtn, "RIGHT", 4, 0)
    longLabel:SetText("72h")

    OrctionMediumBtn:SetChecked(true)  -- default 24h; Blizzard's medium is also checked by default

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

    -- ── Results table (right panel, scrollable) ────────────────────────────
    -- Right panel footprint from dump: x=219, y=76, w=576, h=37 per row
    -- Column offsets are relative to the scroll child (x=0 = panel x=219)

    local COL1_X   = 11    -- cost per item
    local COL2_X   = 261   -- total available
    local COL3_X   = 371   -- # auctions
    local COL4_X   = 456   -- buy button x (left edge within row)
    local HEADER_Y = -51
    local ROW_H    = 37
    local MAX_ROWS = 50
    local ROW_W    = 543   -- 576 - 33 for scrollbar

    local hCost = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCost:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL1_X, HEADER_Y)
    hCost:SetText("Cost / Item")

    local hQty = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hQty:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL2_X, HEADER_Y)
    hQty:SetText("Available")

    local hAuc = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAuc:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL3_X, HEADER_Y)
    hAuc:SetText("Auctions")

    local scrollFrame = CreateFrame("ScrollFrame", "OrctionResultScroll", OrctionAHPanel,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219, -76)
    scrollFrame:SetWidth(ROW_W)
    scrollFrame:SetHeight(316)   -- ~8.5 visible rows

    local scrollChild = CreateFrame("Frame", "OrctionResultScrollChild", scrollFrame)
    scrollChild:SetWidth(ROW_W)
    scrollChild:SetHeight(MAX_ROWS * ROW_H)
    scrollFrame:SetScrollChild(scrollChild)

    for i = 1, MAX_ROWS do
        local idx  = i
        local yOff = -((i - 1) * ROW_H)

        local rowBtn = CreateFrame("Button", nil, scrollChild)
        rowBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOff)
        rowBtn:SetWidth(ROW_W)
        rowBtn:SetHeight(ROW_H)

        local bg = rowBtn:CreateTexture(nil, "BACKGROUND")
        if math.mod(i, 2) == 0 then
            bg:SetTexture(0.09, 0.09, 0.19, 0.5)
        else
            bg:SetTexture(0, 0, 0.09, 0.3)
        end
        bg:SetAllPoints()

        local hl = rowBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture(0.3, 0.3, 0.6, 0.4)
        hl:SetAllPoints()

        local costFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        costFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", COL1_X, -13)

        local qtyFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        qtyFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", COL2_X, -13)

        local aucFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        aucFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", COL3_X, -13)

        local buyBtn = CreateFrame("Button", nil, rowBtn, "UIPanelButtonTemplate")
        buyBtn:SetWidth(80)
        buyBtn:SetHeight(22)
        buyBtn:SetPoint("LEFT", rowBtn, "LEFT", COL4_X, 0)
        buyBtn:SetText("Buy")
        buyBtn:SetScript("OnClick", function()
            local row = orctionResultRows[idx]
            if row and row.firstBuyout and orctionSearchName then
                orctionBuyPending = { buyout = row.firstBuyout }
                QueryAuctionItems(orctionSearchName, nil, nil, nil, nil, nil, 0, nil, nil)
            end
        end)

        -- Prevent row click when clicking the buy button
        buyBtn:SetScript("OnMouseDown", function() this:GetParent():SetScript("OnClick", nil) end)
        buyBtn:SetScript("OnMouseUp",   function()
            this:GetParent():SetScript("OnClick", function()
                local row = orctionResultRows[idx]
                if row and row.costPerItem then
                    MoneyInputFrame_SetCopper(OrctionStartBid, row.costPerItem)
                    MoneyInputFrame_SetCopper(OrctionBuyout,   row.costPerItem)
                end
            end)
        end)

        rowBtn:SetScript("OnClick", function()
            local row = orctionResultRows[idx]
            if row and row.costPerItem then
                MoneyInputFrame_SetCopper(OrctionStartBid, row.costPerItem)
                MoneyInputFrame_SetCopper(OrctionBuyout,   row.costPerItem)
            end
        end)

        orctionResultRows[i] = { frame = rowBtn, cost = costFS, qty = qtyFS,
                                  auctions = aucFS, buyBtn = buyBtn,
                                  costPerItem = nil, firstBuyout = nil }
        rowBtn:Hide()
    end

    -- ── Listen for item slot and search result changes ─────────────────────

    OrctionAHPanel:RegisterEvent("NEW_AUCTION_UPDATE")
    OrctionAHPanel:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    OrctionAHPanel:SetScript("OnEvent", function()
        if event == "NEW_AUCTION_UPDATE" then
            Orction_UpdateItemSlot()
        elseif event == "AUCTION_ITEM_LIST_UPDATE" then
            if orctionBuyPending then
                Orction_TryBuy()
            else
                Orction_CollectPage()
            end
        end
    end)

    -- Pace multi-page queries and time out if a page never returns data
    OrctionAHPanel:SetScript("OnUpdate", function()
        if orctionSearchRetry then
            orctionQueryDelay = orctionQueryDelay + arg1
            if orctionQueryDelay >= 0.3 then
                orctionSearchRetry   = false
                orctionPageProcessed = false
                orctionWaitTimeout   = 0
                orctionQueryDelay    = 0
                QueryAuctionItems(orctionSearchName, nil, nil, nil, nil, nil,
                                  orctionSearchPage, nil, nil)
            end
        elseif orctionSearchActive then
            -- Waiting for AUCTION_ITEM_LIST_UPDATE with non-zero batch.
            -- If nothing arrives in 3 seconds, display whatever we collected so far.
            orctionWaitTimeout = orctionWaitTimeout + arg1
            if orctionWaitTimeout >= 3.0 then
                orctionSearchActive = false
                Orction_DisplayResults()
            end
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
