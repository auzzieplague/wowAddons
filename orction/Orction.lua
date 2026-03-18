local ADDON_NAME = "Orction"
local ORCTION_TAB_INDEX = nil
local orig_AuctionFrameTab_OnClick = nil
local ORCTION_DURATION = 1440  -- 24 hours in minutes
ORCTION_AUCTION_DURATION  = 2    -- 1=6h, 2=24h, 3=72h (synced from settings)
ORCTION_VENDOR_MULTIPLIER = 5.0  -- multiply vendor price when no AH results found

-- ── Search state ───────────────────────────────────────────────────────────
ORCTION_MAX_PAGES            = 10  -- overwritten by settings on ADDON_LOADED
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
local orctionResponseReceived = false -- true once AUCTION_ITEM_LIST_UPDATE has fired for this query
local orctionPendingPost     = nil   -- { name, startBid, buyout, count, stacksLeft, totalStacks }
local orctionPriceBarGraph   = nil   -- bar-graph widget for item price history
local orctionPendingDrop     = nil   -- { name, texture, count } while confirm dialog is open
local orctionVendorPrice     = nil   -- vendor sell price (copper) for the current search item
local orctionSellName        = nil   -- name of the item currently in the sell slot (for Create Auction)
local orctionPendingSellRead = false -- true when waiting for sell slot info after a swap
local orctionSellPollElapsed = 0     -- seconds spent polling for sell slot info
local orctionSearchClassIndex = 0    -- selected class index for search (0 = none)
local orctionSearchSubIndex   = 0    -- selected subclass index for search (0 = none)
local orctionUsableOnly       = false -- filter AH results to usable-by-player items
local ORCTION_TOOLTIP_HOOKED = false
local orctionLastTooltipLink = nil
local orctionLastTooltipName = nil
local orctionWatchlistRows   = {}
local WL_ROW_H               = 16
local WL_MAX_ROWS            = 13
local orctionSimilarResults   = {}   -- all AH results regardless of name match
local orctionShowingSimilar   = false -- true when showing similar after exact match found nothing
local orctionVendorCache      = {}   -- name -> vendor copper, reset each search
local orctionScanQueue         = nil  -- list of names to scan; nil when not scanning
local orctionScanIndex         = 0    -- current position in scan queue
local orctionScanMode          = false -- true while showing accumulated scan results
local orctionScanNextPending   = false -- waiting for inter-item delay before next query
local orctionScanNextDelay     = 0    -- seconds accumulated toward next scan item
local orctionScanItemStartCount = 0   -- orctionSimilarResults count at start of current scan item
local orctionScanCancel        = false -- user requested scan cancel
local orctionScanResultsShowing = false -- scan finished; keep showing all results without exact-match re-filtering
local orctionFullScanActive         = false  -- category full-scan is fetching pages
local orctionFullScanResultsShowing = false  -- category full-scan done; showing vendor-below results
local orctionFullScanPagesProcessed = 0      -- pages collected since full scan started
local FULL_SCAN_UPDATE_INTERVAL     = 3      -- redraw results every N pages during a full scan
local orctionQueryRetryCount   = 0    -- retries fired for the current query (rate-limit recovery)
local ORCTION_RETRY_DELAY      = 5.0  -- seconds to wait before retrying an empty query (synced from DB)
local ORCTION_MAX_RETRIES      = 2    -- maximum retries per query before giving up (synced from DB)
local orctionSearchStartPage   = 0    -- first page of the current fetch batch
local orctionNextStartPage     = 0    -- page to start from when "Next Page" is clicked
local orctionHasMorePages      = false -- true when pagination stopped at ORCTION_MAX_PAGES, not at exhaustion
local orctionBuyBidPlaced      = false -- PlaceAuctionBid was called; waiting for confirmation
local orctionBuyBidTimeout     = 0     -- seconds since bid was placed with no AUCTION_ITEM_LIST_UPDATE
local orctionBuyBidRechecked   = false -- true after one fallback re-query was fired
local orctionPriceWriteQueue   = {}    -- {itemId, name, price} items waiting for async DB write
local orctionSearchRecorded    = {}    -- key→true: items already queued for recording this search

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

-- Colourised money string.
-- With gold: show Xg [Ys], omit copper.
-- Without gold: show [Ys] [Zc], omit zero-value parts.
local function FormatMoneyColour(copper)
    if not copper or copper <= 0 then
        return "|cFFB87333" .. "0c|r"
    end
    local g = math.floor(copper / 10000)
    local s = math.floor(math.mod(copper, 10000) / 100)
    local c = math.mod(copper, 100)
    if g > 0 then
        local str = "|cFFFFD700" .. g .. "g |r"
        if s > 0 then str = str .. "|cFFC0C0C0" .. s .. "s|r" end
        return str
    elseif s > 0 then
        local str = "|cFFC0C0C0" .. s .. "s|r"
        if c > 0 then str = str .. "|cFFB87333" .. c .. "c|r" end
        return str
    else
        return "|cFFB87333" .. c .. "c|r"
    end
end

local function Orction_TitleCaseWords(text)
    if not text then return text end
    return string.gsub(text, "(%a)([%w']*)", function(a, b)
        return string.upper(a) .. b
    end)
end

-- Recalculates and displays the auction deposit for the current sell slot item.
-- Must be called after the item is placed in the sell slot and after duration changes.
function Orction_UpdateDeposit()
    if not OrctionDepositValue then return end
    if not GetAuctionSellItemInfo() then
        OrctionDepositValue:SetText("--")
        return
    end
    local durIdx = ORCTION_AUCTION_DURATION or 2
    -- TurtleWoW tripled vanilla durations (2h→6h, 8h→24h, 24h→72h) but kept the original
    -- vanilla runTime values in the deposit formula: Short=120min, Medium=480min, Long=1440min
    local durMinutes = durIdx == 1 and 120 or durIdx == 3 and 1440 or 480
    -- Sync Blizzard duration buttons for visual consistency
    if AuctionsShortAuctionButton  then AuctionsShortAuctionButton:SetChecked( durIdx == 1 and 1 or nil) end
    if AuctionsMediumAuctionButton then AuctionsMediumAuctionButton:SetChecked(durIdx == 2 and 1 or nil) end
    if AuctionsLongAuctionButton   then AuctionsLongAuctionButton:SetChecked(  durIdx == 3 and 1 or nil) end
    local dep = CalculateAuctionDeposit and CalculateAuctionDeposit(durMinutes)
    local count  = math.max(1, tonumber(OrctionCountBox  and OrctionCountBox:GetText())  or 1)
    local stacks = math.max(1, tonumber(OrctionStacksBox and OrctionStacksBox:GetText()) or 1)
    if dep and dep > 0 then
        OrctionDepositValue:SetText(FormatMoneyColour(dep))
        if OrctionTotalFeeValue then
            OrctionTotalFeeValue:SetText("(" .. FormatMoneyColour(dep * count * stacks) .. ")")
        end
        -- Profit per item: buyout minus the larger of deposit or 5% AH cut
        if OrctionProfitValue and OrctionBuyout then
            local totalBuyout = MoneyInputFrame_GetCopper(OrctionBuyout)
            if totalBuyout and totalBuyout > 0 then
                local ahCut    = math.floor(totalBuyout * 0.05)
                local deduct   = math.max(dep, ahCut)
                local profit   = totalBuyout - deduct
                local profitPI = math.floor(profit / count)
                local vp       = orctionVendorPrice or 0
                if profitPI <= vp and vp > 0 then
                    OrctionProfitValue:SetText(FormatMoneyColour(profitPI) .. " |cFFFF4444— Vendor It!|r")
                else
                    OrctionProfitValue:SetText(FormatMoneyColour(profitPI))
                end
            else
                OrctionProfitValue:SetText("--")
            end
        end
    else
        OrctionDepositValue:SetText("--")
        if OrctionTotalFeeValue then OrctionTotalFeeValue:SetText("") end
        if OrctionProfitValue   then OrctionProfitValue:SetText("") end
    end
end

local function Orction_UpdateSearchingText()
    if not OrctionSearchingText then return end
    local page = (orctionSearchPage or 0) + 1
    if orctionFullScanActive then
        OrctionSearchingText:SetText("Scanning page " .. page .. "...")
    else
        OrctionSearchingText:SetText("Searching page " .. page .. "...")
    end
end

local function Orction_GetClassName(index)
    if not index or index <= 0 then return "None" end
    local classes = { GetAuctionItemClasses() }
    return classes[index] or "None"
end

local function Orction_GetSubClassName(classIndex, subIndex)
    if not classIndex or classIndex <= 0 or not subIndex or subIndex <= 0 then
        return "None"
    end
    local subs = { GetAuctionItemSubClasses(classIndex) }
    return subs[subIndex] or "None"
end

local function Orction_GetCategoryLabel()
    local catName = Orction_GetClassName(orctionSearchClassIndex)
    local catLabel = (catName ~= "None") and catName or "All"
    if orctionSearchSubIndex and orctionSearchSubIndex > 0 then
        local sub = Orction_GetSubClassName(orctionSearchClassIndex, orctionSearchSubIndex)
        if sub and sub ~= "None" then catLabel = catLabel .. " > " .. sub end
    end
    return catLabel
end

local function Orction_SetSearchCategory(classIndex, subIndex)
    orctionSearchClassIndex = classIndex or 0
    orctionSearchSubIndex   = subIndex or 0
    if OrctionCategoryDropDown then
        UIDropDownMenu_SetSelectedValue(OrctionCategoryDropDown, orctionSearchClassIndex)
        UIDropDownMenu_SetText(Orction_GetClassName(orctionSearchClassIndex), OrctionCategoryDropDown)
    end
    if OrctionSubcategoryDropDown then
        if not classIndex or classIndex <= 0 then
            UIDropDownMenu_SetText("None", OrctionSubcategoryDropDown)
            if UIDropDownMenu_DisableDropDown then
                UIDropDownMenu_DisableDropDown(OrctionSubcategoryDropDown)
            else
                local btn = getglobal(OrctionSubcategoryDropDown:GetName() .. "Button")
                if btn then btn:Disable() end
            end
        else
            UIDropDownMenu_SetSelectedValue(OrctionSubcategoryDropDown, orctionSearchSubIndex)
            UIDropDownMenu_SetText(Orction_GetSubClassName(orctionSearchClassIndex, orctionSearchSubIndex), OrctionSubcategoryDropDown)
            if UIDropDownMenu_EnableDropDown then
                UIDropDownMenu_EnableDropDown(OrctionSubcategoryDropDown)
            else
                local btn = getglobal(OrctionSubcategoryDropDown:GetName() .. "Button")
                if btn then btn:Enable() end
            end
        end
    end
end

local function Orction_InitCategoryDropDown()
    if not OrctionCategoryDropDown then return end
    UIDropDownMenu_Initialize(OrctionCategoryDropDown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "None"
        info.value = 0
        info.func = function()
            UIDropDownMenu_SetSelectedValue(OrctionCategoryDropDown, 0)
            Orction_SetSearchCategory(0, 0)
            if OrctionSubcategoryDropDown then
                UIDropDownMenu_SetText("None", OrctionSubcategoryDropDown)
            end
            Orction_InitSubcategoryDropDown()
        end
        info.checked = (orctionSearchClassIndex == 0)
        UIDropDownMenu_AddButton(info)

        local classes = { GetAuctionItemClasses() }
        for i = 1, table.getn(classes) do
            local idx = i
            local name = classes[i]
            info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = idx
            info.func = function()
                UIDropDownMenu_SetSelectedValue(OrctionCategoryDropDown, idx)
                Orction_SetSearchCategory(idx, 0)
                Orction_InitSubcategoryDropDown()
            end
            info.checked = (orctionSearchClassIndex == idx)
            UIDropDownMenu_AddButton(info)
        end
    end)
end

function Orction_InitSubcategoryDropDown()
    if not OrctionSubcategoryDropDown then return end
    UIDropDownMenu_Initialize(OrctionSubcategoryDropDown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "None"
        info.value = 0
        info.func = function()
            UIDropDownMenu_SetSelectedValue(OrctionSubcategoryDropDown, 0)
            Orction_SetSearchCategory(orctionSearchClassIndex, 0)
        end
        info.checked = (orctionSearchSubIndex == 0)
        UIDropDownMenu_AddButton(info)

        if not orctionSearchClassIndex or orctionSearchClassIndex <= 0 then
            return
        end
        local subs = { GetAuctionItemSubClasses(orctionSearchClassIndex) }
        for i = 1, table.getn(subs) do
            local idx = i
            local name = subs[i]
            info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = idx
            info.func = function()
                UIDropDownMenu_SetSelectedValue(OrctionSubcategoryDropDown, idx)
                Orction_SetSearchCategory(orctionSearchClassIndex, idx)
            end
            info.checked = (orctionSearchSubIndex == idx)
            UIDropDownMenu_AddButton(info)
        end
    end)
end

local function Orction_Query(name, page)
    local classIdx = orctionSearchClassIndex
    local subIdx   = orctionSearchSubIndex
    local p        = page or 0
    local usable   = orctionUsableOnly and 1 or nil
    local qname    = (name and string.len(name) > 0) and name or ""
    if classIdx and classIdx > 0 and subIdx and subIdx > 0 then
        QueryAuctionItems(qname, nil, nil, nil, classIdx, subIdx, p, usable, nil)
    elseif classIdx and classIdx > 0 then
        QueryAuctionItems(qname, nil, nil, nil, classIdx, nil, p, usable, nil)
    else
        QueryAuctionItems(qname, nil, nil, nil, nil, nil, p, usable, nil)
    end
end

-- ── Vendor price cache (tooltip hook) ─────────────────────────────────────

local function Orction_NameFromLink(link)
    if not link then return nil end
    return string.gsub(link, ".*%[(.-)%].*", "%1")
end

local function Orction_ReadTooltipMoney()
    if GameTooltipMoneyFrame1 and GameTooltipMoneyFrame1.money then
        return GameTooltipMoneyFrame1.money
    end
    if GameTooltip and GameTooltip.money then
        return GameTooltip.money
    end
    return nil
end

local function Orction_CacheVendorPrice(link, name)
    if not OrctionDB then return end
    OrctionDB.vendorPrices = OrctionDB.vendorPrices or {}
    local itemName = name or Orction_NameFromLink(link)
    if not itemName then return end
    local money = Orction_ReadTooltipMoney()
    if money and money > 0 then
        OrctionDB.vendorPrices[itemName] = money
    end
end

local function Orction_HookTooltipMethod(methodName, getter)
    local orig = GameTooltip[methodName]
    if not orig then return end
    GameTooltip[methodName] = function(...)
        local args = arg
        local ret = orig(unpack(args))
        local link, name = getter(unpack(args))
        if link or name then
            orctionLastTooltipLink = link
            orctionLastTooltipName = name
        end
        Orction_CacheVendorPrice(link, name)
        return ret
    end
end

local function Orction_HookVendorPriceTooltip()
    if ORCTION_TOOLTIP_HOOKED then return end
    ORCTION_TOOLTIP_HOOKED = true

    local orig_SetTooltipMoney = SetTooltipMoney
    SetTooltipMoney = function(frame, money)
        if arg then
            orig_SetTooltipMoney(frame, money, unpack(arg))
        else
            orig_SetTooltipMoney(frame, money)
        end
        if frame == GameTooltip and money and money > 0 then
            Orction_CacheVendorPrice(orctionLastTooltipLink, orctionLastTooltipName)
        end
    end

    Orction_HookTooltipMethod("SetBagItem", function(self, bag, slot)
        if not bag or not slot then return nil end
        return GetContainerItemLink(bag, slot), nil
    end)

    Orction_HookTooltipMethod("SetInventoryItem", function(self, unit, slot)
        return GetInventoryItemLink(unit, slot), nil
    end)

    Orction_HookTooltipMethod("SetLootItem", function(self, slot)
        return GetLootSlotLink(slot), nil
    end)

    Orction_HookTooltipMethod("SetQuestItem", function(self, qtype, index)
        if GetQuestItemLink then
            return GetQuestItemLink(qtype, index), nil
        end
        return nil
    end)

    Orction_HookTooltipMethod("SetMerchantItem", function(self, index)
        if GetMerchantItemLink then
            return GetMerchantItemLink(index), nil
        end
        return nil
    end)

    Orction_HookTooltipMethod("SetTradeSkillItem", function(self, index)
        if GetTradeSkillItemLink then
            return GetTradeSkillItemLink(index), nil
        end
        return nil
    end)

    Orction_HookTooltipMethod("SetTradePlayerItem", function(self, index)
        if GetTradePlayerItemLink then
            return GetTradePlayerItemLink(index), nil
        end
        return nil
    end)

    Orction_HookTooltipMethod("SetTradeTargetItem", function(self, index)
        if GetTradeTargetItemLink then
            return GetTradeTargetItemLink(index), nil
        end
        return nil
    end)

    Orction_HookTooltipMethod("SetAuctionItem", function(self, atype, index)
        if GetAuctionItemLink then
            return GetAuctionItemLink(atype, index), nil
        end
        return nil
    end)
end

local Orction_AddToWatchlist  -- forward declaration; defined below
local Orction_PreviewItem     -- forward declaration; defined below

-- ── Result row factory (called lazily from Orction_DisplayResults) ────────
-- Column constants mirror those in Orction_BuildAHPanel.
local RC_COL_ICON = 6
local RC_COL_NAME = 34
local RC_COL_WL   = 138  -- WL+ button column
local RC_COL1     = 174  -- cost / item
local RC_COL2     = 278  -- available
local RC_COL3     = 356  -- auctions
local RC_COL4     = 420  -- buy button
local RC_ROW_H    = 37
local RC_ROW_W    = 578

local function Orction_CreateResultRow(i)
    local scrollChild = getglobal("OrctionResultScrollChild")
    if not scrollChild then return end

    local yOff   = -((i - 1) * RC_ROW_H)
    local rowBtn = CreateFrame("Button", nil, scrollChild)
    rowBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOff)
    rowBtn:SetWidth(RC_ROW_W)
    rowBtn:SetHeight(RC_ROW_H)

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

    local iconTex = rowBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetWidth(26)
    iconTex:SetHeight(26)
    iconTex:SetPoint("LEFT", rowBtn, "LEFT", RC_COL_ICON, 0)
    iconTex:Hide()

    local nameFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    nameFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", RC_COL_NAME, -13)
    nameFS:SetWidth(100)
    nameFS:SetJustifyH("LEFT")

    local costFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    costFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", RC_COL1, -13)

    local qtyFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    qtyFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", RC_COL2, -13)

    local aucFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    aucFS:SetPoint("TOPLEFT", rowBtn, "TOPLEFT", RC_COL3, -13)

    local buyBtn = CreateFrame("Button", nil, rowBtn, "UIPanelButtonTemplate")
    buyBtn:SetWidth(80)
    buyBtn:SetHeight(22)
    buyBtn:SetPoint("LEFT", rowBtn, "LEFT", RC_COL4, 0)
    buyBtn:SetText("Buy")
    local buyBtnFS = buyBtn:GetFontString()
    if buyBtnFS then
        local fontFile, _, flags = buyBtnFS:GetFont()
        buyBtnFS:SetFont(fontFile or STANDARD_TEXT_FONT, 9, flags or "")
    end

    local wlBtn = CreateFrame("Button", nil, rowBtn, "UIPanelButtonTemplate")
    wlBtn:SetWidth(32)
    wlBtn:SetHeight(22)
    wlBtn:SetPoint("LEFT", rowBtn, "LEFT", RC_COL_WL, 0)
    wlBtn:SetText("WL+")
    local wlBtnFS = wlBtn:GetFontString()
    if wlBtnFS then
        local fontFile, _, flags = wlBtnFS:GetFont()
        wlBtnFS:SetFont(fontFile or STANDARD_TEXT_FONT, 8, flags or "")
    end

    -- Vendor profit label: shown to the right of the buy button on green (below-vendor-cost) rows
    local profitFS = rowBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profitFS:SetPoint("LEFT", buyBtn, "RIGHT", 6, 0)
    profitFS:Hide()

    local idx = i
    buyBtn:SetScript("OnClick", function()
        local row = orctionResultRows[idx]
        if row and row.firstBuyout and row.itemName then
            orctionBuyPending = { buyout = row.firstBuyout, name = row.itemName }
            Orction_Query(row.itemName, 0)
        end
    end)

    buyBtn:SetScript("OnMouseDown", function() this:GetParent():SetScript("OnClick", nil) end)
    buyBtn:SetScript("OnMouseUp", function()
        this:GetParent():SetScript("OnClick", function()
            local row = orctionResultRows[idx]
            if row and row.costPerItem then
                local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
                MoneyInputFrame_SetCopper(OrctionBuyout, row.costPerItem * count)
            end
        end)
    end)

    wlBtn:SetScript("OnMouseDown", function() this:GetParent():SetScript("OnClick", nil) end)
    wlBtn:SetScript("OnMouseUp", function()
        this:GetParent():SetScript("OnClick", function()
            local row = orctionResultRows[idx]
            if row and row.itemName then
                Orction_AddToWatchlist(row.itemName, 0, 0)
            end
        end)
    end)
    wlBtn:SetScript("OnClick", function()
        local row = orctionResultRows[idx]
        if row and row.itemName then
            Orction_AddToWatchlist(row.itemName, 0, 0)
        end
    end)

    rowBtn:SetScript("OnClick", function()
        local row = orctionResultRows[idx]
        if not row then return end
        if not orctionSellName then
            -- No item in sell slot: preview the clicked item in the post panel
            if row.itemName then
                Orction_PreviewItem(row.itemName, row.texture, row.vendorPrice)
            end
        else
            -- Item dropped: fill buyout price
            if row.costPerItem then
                local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
                MoneyInputFrame_SetCopper(OrctionBuyout, row.costPerItem * count)
            end
        end
    end)

    orctionResultRows[i] = { frame = rowBtn, cost = costFS, qty = qtyFS,
                              auctions = aucFS, buyBtn = buyBtn, wlBtn = wlBtn, bg = bg,
                              nameFS = nameFS, iconTex = iconTex, profitFS = profitFS,
                              isEven = (math.mod(i, 2) == 0),
                              costPerItem = nil, firstBuyout = nil, itemName = nil, itemId = nil,
                              texture = nil, vendorPrice = nil }

    rowBtn:SetScript("OnEnter", function()
        local row = orctionResultRows[idx]
        if row and row.itemId then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. row.itemId)
            GameTooltip:Show()
        end
    end)
    rowBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    rowBtn:Hide()
end

-- ── Search logic ──────────────────────────────────────────────────────────

local function Orction_DisplayResults()
    local nextPageBtn = getglobal("OrctionNextPageBtn")
    if nextPageBtn then
        if orctionHasMorePages and not orctionSearchActive then nextPageBtn:Enable()
        else                                                   nextPageBtn:Disable() end
    end
    local exactMode = not (OrctionExactMatchCheck and OrctionExactMatchCheck:GetChecked() == nil)

    -- Choose result set
    local results
    orctionShowingSimilar = false
    if orctionScanMode or orctionScanResultsShowing then
        -- Scan in progress or scan results being displayed: show all accumulated items,
        -- flag as "showing similar" if the similar set is larger than the exact set
        -- (i.e. non-exact-match results are present).
        results = orctionSimilarResults
        orctionShowingSimilar = table.getn(orctionSimilarResults) > table.getn(orctionSearchResults)
    elseif exactMode then
        if table.getn(orctionSearchResults) > 0 then
            results = orctionSearchResults
        elseif table.getn(orctionSimilarResults) > 0 then
            results = orctionSimilarResults
            orctionShowingSimilar = true
        else
            results = {}
        end
    else
        results = orctionSimilarResults
    end

    -- Decide grouping strategy:
    --   multiple item types → one row per name (cheapest price, total count)
    --   single item type    → one row per price tier (existing behaviour)
    local firstName = results[1] and results[1].name or nil
    local multiItem = false
    for i = 2, table.getn(results) do
        if results[i].name ~= firstName then multiItem = true ; break end
    end

    local groups   = {}
    local groupMap = {}
    for _, item in ipairs(results) do
        local k = multiItem and (item.name or "") or ((item.name or "") .. "::" .. item.costPerItem)
        if not groupMap[k] then
            groupMap[k] = { name        = item.name,
                            texture     = item.texture,
                            itemId      = item.itemId,
                            costPerItem = item.costPerItem,
                            vendorPrice = item.vendorPrice or 0,
                            totalCount  = 0, numAuctions = 0,
                            firstBuyout = item.buyout,
                            firstCount  = item.count }
            table.insert(groups, groupMap[k])
        end
        groupMap[k].totalCount  = groupMap[k].totalCount  + item.count
        groupMap[k].numAuctions = groupMap[k].numAuctions + 1
        -- Keep the cheapest price point for this name
        if multiItem and item.costPerItem < groupMap[k].costPerItem then
            groupMap[k].costPerItem = item.costPerItem
            groupMap[k].firstBuyout = item.buyout
            groupMap[k].firstCount  = item.count
            groupMap[k].texture     = item.texture
            groupMap[k].vendorPrice = item.vendorPrice or 0
        end
    end
    table.sort(groups, function(a, b) return a.costPerItem < b.costPerItem end)

    -- Full category scan: only retain items whose price is below their vendor sell value
    if orctionFullScanActive or orctionFullScanResultsShowing then
        local filtered = {}
        for _, g in ipairs(groups) do
            if g.vendorPrice and g.vendorPrice > 0 and g.costPerItem < g.vendorPrice then
                table.insert(filtered, g)
            end
        end
        groups = filtered
    end

    -- Update progress text only while actively searching/scanning.
    -- On completion the caller sets the text directly; we leave it alone.
    if OrctionSearchingText then
        if orctionFullScanActive or orctionSearchActive then
            OrctionSearchingText:Show()
            Orction_UpdateSearchingText()
        end
    end

    -- Hide "couldn't exact match" banner while a search is in progress or during scans.
    if OrctionSimilarResultsText then
        if orctionShowingSimilar and not orctionSearchActive
                and not orctionFullScanActive and not orctionFullScanResultsShowing then
            OrctionSimilarResultsText:Show()
        else
            OrctionSimilarResultsText:Hide()
        end
    end

    local hasResults = table.getn(groups) > 0
    if OrctionNoResultsText then
        if hasResults then OrctionNoResultsText:Hide() else OrctionNoResultsText:Show() end
    end

    if OrctionVendorSellValue then
        if orctionVendorPrice and orctionVendorPrice > 0 then
            OrctionVendorSellValue:SetText(FormatMoneyColour(orctionVendorPrice))
        else
            OrctionVendorSellValue:SetText("--")
        end
    end

    -- Auto-set buyout: cheapest exact match, or vendor × multiplier when no results
    if hasResults and not orctionShowingSimilar and OrctionCountBox then
        local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
        MoneyInputFrame_SetCopper(OrctionBuyout, groups[1].costPerItem * count)
    elseif not hasResults and orctionSellName and orctionVendorPrice and orctionVendorPrice > 0 and OrctionCountBox and OrctionBuyout then
        local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
        MoneyInputFrame_SetCopper(OrctionBuyout, math.floor(orctionVendorPrice * (ORCTION_VENDOR_MULTIPLIER or 5.0)) * count)
    end

    -- Grow the row pool on demand — frames are permanent so this only fires when new rows are needed.
    local needed = table.getn(groups)
    while table.getn(orctionResultRows) < needed do
        Orction_CreateResultRow(table.getn(orctionResultRows) + 1)
    end

    -- Size both the scroll child and the scroll frame to fit content exactly,
    -- capped at the maximum viewport height (~8.5 rows).
    local visibleCount = needed
    local MAX_H    = 316
    local contentH = visibleCount * RC_ROW_H
    if contentH < 1 then contentH = RC_ROW_H end
    if OrctionResultScrollChild then
        OrctionResultScrollChild:SetHeight(contentH)
    end
    local scroll = getglobal("OrctionResultScroll")
    if scroll then
        local viewH = math.min(contentH, MAX_H)
        scroll:SetHeight(viewH)
        scroll:SetVerticalScroll(0)
        local scrollBar = getglobal("OrctionResultScrollScrollBar")
        if scrollBar then
            scrollBar:SetMinMaxValues(0, math.max(0, contentH - viewH))
            scrollBar:SetValue(0)
        end
    end

    local rowsRendered = 0
    for i = 1, table.getn(orctionResultRows) do
        local row = orctionResultRows[i]
        local g   = groups[i]
        if g then
            row.costPerItem = g.costPerItem
            row.firstBuyout = g.firstBuyout
            row.itemName    = g.name
            row.itemId      = g.itemId
            row.texture     = g.texture
            row.vendorPrice = g.vendorPrice
            row.cost:SetText(FormatMoneyColour(g.costPerItem))
            row.qty:SetText(tostring(g.totalCount))
            row.auctions:SetText(tostring(g.numAuctions))
            if row.nameFS  then row.nameFS:SetText(g.name or "") end
            if row.iconTex then
                if g.texture then row.iconTex:SetTexture(g.texture) ; row.iconTex:Show()
                else               row.iconTex:Hide() end
            end
            local btnLabel = "|cFFFFFFFF" .. tostring(g.firstCount) .. " for |r" .. FormatMoneyColour(g.costPerItem * g.firstCount)
            if g.vendorPrice and g.vendorPrice > 0 and g.costPerItem < g.vendorPrice then
                row.bg:SetTexture(0, 0.35, 0, 0.55)
                if row.profitFS then
                    local profit = g.vendorPrice - g.costPerItem
                    row.profitFS:SetText("|cFF00FF00+" .. FormatMoneyColour(profit) .. "|r")
                    row.profitFS:Show()
                end
            else
                if row.isEven then row.bg:SetTexture(0.09, 0.09, 0.19, 0.5)
                else                row.bg:SetTexture(0, 0, 0.09, 0.3) end
                if row.profitFS then row.profitFS:Hide() end
            end
            row.buyBtn:SetText(btnLabel)
            if row.wlBtn then
                if multiItem then row.wlBtn:Show() else row.wlBtn:Hide() end
            end
            row.frame:Show()
            rowsRendered = rowsRendered + 1
        else
            row.costPerItem = nil
            row.firstBuyout = nil
            row.itemName    = nil
            row.itemId      = nil
            row.texture     = nil
            row.vendorPrice = nil
            if row.wlBtn    then row.wlBtn:Hide()    end
            if row.profitFS then row.profitFS:Hide() end
            row.frame:Hide()
        end
    end
    Orction_UpdateDeposit()
end

local function Orction_CollectPage()
    if not orctionSearchActive then return end

    local batch = GetNumAuctionItems("list")

    orctionResponseReceived = true  -- server acknowledged this query (even if empty)

    if batch == 0 then
        -- Blizzard fires a batch=0 event before large result sets are ready on ANY page.
        -- orctionResponseReceived is now set, so the timeout will treat a persistent
        -- batch=0 as "genuine no results" rather than rate-limiting.
        return
    end

    if orctionPageProcessed then return end  -- ignore duplicate non-empty firings for this page
    orctionPageProcessed   = true
    orctionWaitTimeout     = 0  -- got real data, reset the timeout
    orctionQueryRetryCount = 0  -- successful response, clear retry counter
    Orction_UpdateSearchingText()
    local pageAdded = 0
    for i = 1, batch do
        local name, texture, count, quality, canUse, level,
              minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)

        -- Per-item vendor price: session cache → AH link → bag scan fallback
        local vPrice = orctionVendorCache[name]
        if vPrice == nil then
            -- Try AH link → SellValues first (fast, works during AUCTION_ITEM_LIST_UPDATE)
            if SellValues then
                local link = GetAuctionItemLink("list", i)
                if link then
                    local _, _, itemID = string.find(link, "item:(%d+)")
                    if itemID then
                        vPrice = SellValues["item:" .. itemID] or 0
                    end
                end
            end
            vPrice = vPrice or 0
            -- Fallback: persistent cache or bag scan (handles non-exact queries where link may be nil)
            if vPrice == 0 then
                vPrice = OrctionVendor_GetPrice(name)
            end
            -- Persist to DB so future searches (and non-exact mode) can reuse it
            if vPrice > 0 and OrctionDB and OrctionDB.vendorPrices then
                OrctionDB.vendorPrices[name] = vPrice
            end
            orctionVendorCache[name] = vPrice
        end
        -- Keep the single-item vendor price for the sell-slot UI
        if name == orctionSearchName and (not orctionVendorPrice or orctionVendorPrice == 0) then
            orctionVendorPrice = vPrice
        end

        if buyoutPrice and buyoutPrice > 0 and count and count > 0 then
            local itemId = nil
            local link = GetAuctionItemLink("list", i)
            if link then
                local _, _, id = string.find(link, "item:(%d+)")
                if id then itemId = tonumber(id) end
            end
            local entry = {
                name        = name,
                itemId      = itemId,
                texture     = texture,
                buyout      = buyoutPrice,
                count       = count,
                costPerItem = math.floor(buyoutPrice / count),
                vendorPrice = vPrice,
            }
            -- Always collect into similar (all results)
            table.insert(orctionSimilarResults, entry)
            pageAdded = pageAdded + 1
            -- Exact results only for name matches
            if name == orctionSearchName then
                table.insert(orctionSearchResults, entry)
            end
            -- Enqueue for async price recording: AH results are price-sorted so first
            -- occurrence is the cheapest; skip items already queued this search.
            local rKey = entry.itemId or ("name:" .. (name or ""))
            if not orctionSearchRecorded[rKey] then
                orctionSearchRecorded[rKey] = true
                table.insert(orctionPriceWriteQueue, {
                    itemId = entry.itemId,
                    name   = name,
                    price  = entry.costPerItem,
                })
            end
        end
    end

    local nextPage  = orctionSearchPage + 1
    local pageLimit = orctionSearchStartPage + ORCTION_MAX_PAGES
    local underLimit = orctionFullScanActive or (nextPage < pageLimit)
    if underLimit and batch > 0 then
        orctionSearchPage  = nextPage
        orctionSearchRetry = true   -- OnUpdate will fire the next query after a short delay
        orctionQueryDelay  = 0
        if orctionFullScanActive then
            orctionFullScanPagesProcessed = orctionFullScanPagesProcessed + 1
            if math.mod(orctionFullScanPagesProcessed, FULL_SCAN_UPDATE_INTERVAL) == 0 then
                Orction_DisplayResults()
                if OrctionSearchingText then
                    OrctionSearchingText:Show()
                    Orction_UpdateSearchingText()
                end
            end
        elseif not orctionScanMode then
            -- Regular search: refresh results after every page so user sees progress
            Orction_DisplayResults()
            if OrctionSearchingText then
                OrctionSearchingText:Show()
                Orction_UpdateSearchingText()
            end
        end
    else
        -- Stopped because we hit the page limit, ran out of results, or full scan exhausted
        orctionHasMorePages  = (batch > 0) and not orctionFullScanActive
        orctionNextStartPage = nextPage
        orctionSearchActive  = false
        if orctionScanMode then
            orctionScanNextPending = true
            orctionScanNextDelay   = 0
        elseif orctionFullScanActive then
            orctionFullScanActive         = false
            orctionFullScanResultsShowing = true
            Orction_DisplayResults()
            if OrctionSearchingText then OrctionSearchingText:SetText("Scan complete") ; OrctionSearchingText:Show() end
            -- Build category label
            local catLabel = Orction_GetCategoryLabel()
            -- Count unique items queued for recording (datapoints)
            local datapoints = 0
            for _ in pairs(orctionSearchRecorded) do datapoints = datapoints + 1 end
            -- Count unique item names below vendor price
            local belowNames = {}
            for _, r in ipairs(orctionSimilarResults) do
                if r.vendorPrice and r.vendorPrice > 0 and r.costPerItem < r.vendorPrice then
                    belowNames[r.name or "?"] = true
                end
            end
            local below = 0
            for _ in pairs(belowNames) do below = below + 1 end
            DEFAULT_CHAT_FRAME:AddMessage(
                "Orction: Scanned [" .. catLabel .. "] - recorded " .. datapoints ..
                " new datapoints, found " .. below .. " items under vendor cost - see above")
        else
            Orction_DisplayResults()
            if OrctionSearchingText then OrctionSearchingText:SetText("Search complete") ; OrctionSearchingText:Show() end
        end
    end
end

local function Orction_StartSearch(name, classIndex, subIndex)
    -- Cancel any active scan / clear scan results display
    orctionScanMode               = false
    orctionScanResultsShowing     = false
    orctionScanQueue              = nil
    orctionScanNextPending        = false
    orctionFullScanActive         = false
    orctionFullScanResultsShowing = false
    orctionQueryRetryCount    = 0
    orctionSearchName    = name
    orctionSearchPage    = 0
    orctionSearchActive      = true
    orctionPageProcessed     = false
    orctionSearchRetry       = false
    orctionQueryDelay        = 0
    orctionWaitTimeout       = 0
    orctionResponseReceived  = false
    orctionSearchStartPage   = 0
    orctionNextStartPage     = 0
    orctionHasMorePages      = false
    orctionSearchResults     = {}
    orctionSimilarResults    = {}
    orctionShowingSimilar    = false
    orctionVendorCache       = {}
    orctionPriceWriteQueue   = {}
    orctionSearchRecorded    = {}
    orctionVendorPrice   = (OrctionDB and OrctionDB.vendorPrices and OrctionDB.vendorPrices[name]) or 0
    Orction_SetSearchCategory(classIndex or orctionSearchClassIndex, subIndex or orctionSearchSubIndex)
    if OrctionVendorSellValue   then OrctionVendorSellValue:SetText("--") end
    if OrctionSimilarResultsText then OrctionSimilarResultsText:Hide() end
    for i = 1, table.getn(orctionResultRows) do
        orctionResultRows[i].frame:Hide()
    end
    if OrctionSearchingText then OrctionSearchingText:Show() end
    Orction_UpdateSearchingText()
    if OrctionNoResultsText  then OrctionNoResultsText:Hide()  end
    Orction_Query(name, 0)
end

function Orction_FetchNextPages()
    if not orctionHasMorePages then return end
    orctionHasMorePages     = false
    orctionSearchActive     = true
    orctionPageProcessed    = false
    orctionSearchRetry      = false
    orctionQueryDelay       = 0
    orctionWaitTimeout      = 0
    orctionResponseReceived = false
    orctionSearchStartPage  = orctionNextStartPage
    orctionSearchPage       = orctionNextStartPage
    local btn = getglobal("OrctionNextPageBtn")
    if btn then btn:Disable() end
    if OrctionSearchingText then OrctionSearchingText:Show() end
    Orction_UpdateSearchingText()
    Orction_Query(orctionSearchName, orctionNextStartPage)
end

local function Orction_TryBuy()
    if not orctionBuyPending then return end
    local batch = GetNumAuctionItems("list")
    if batch == 0 then return end  -- loading event; wait for real data

    local buyName   = orctionBuyPending.name or orctionSearchName
    local buyBuyout = orctionBuyPending.buyout

    -- Reset the bid confirmation timer — we got a real response.
    orctionBuyBidTimeout = 0

    local function removeFirst(t)
        for j = 1, table.getn(t) do
            if t[j].buyout == buyBuyout and (t[j].name or "") == (buyName or "") then
                table.remove(t, j) return
            end
        end
    end

    if orctionBuyBidPlaced then
        -- A bid was placed; check whether the item is now gone (success) or still present (cooldown).
        for i = 1, batch do
            local name, _, _, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo("list", i)
            if name == buyName and buyoutPrice == buyBuyout then
                -- Item still there — bid on cooldown. Clear state so user can retry manually.
                orctionBuyPending      = nil
                orctionBuyBidPlaced    = false
                orctionBuyBidRechecked = false
                DEFAULT_CHAT_FRAME:AddMessage("Orction: bid on cooldown — click Buy to try again.")
                return
            end
        end
        -- Item gone — purchase confirmed.
        removeFirst(orctionSearchResults)
        removeFirst(orctionSimilarResults)
        orctionBuyPending      = nil
        orctionBuyBidPlaced    = false
        orctionBuyBidRechecked = false
        Orction_DisplayResults()
        return
    end

    -- First attempt: find and bid on the item.
    for i = 1, batch do
        local name, _, _, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo("list", i)
        if name == buyName and buyoutPrice == buyBuyout then
            PlaceAuctionBid("list", i, buyoutPrice)
            orctionBuyBidPlaced    = true
            orctionBuyBidTimeout   = 0
            orctionBuyBidRechecked = false
            return
        end
    end

    -- Auction not found — it sold or expired.
    removeFirst(orctionSearchResults)
    removeFirst(orctionSimilarResults)
    orctionBuyPending   = nil
    orctionBuyBidPlaced = false
    DEFAULT_CHAT_FRAME:AddMessage("Orction: auction not found (sold/expired) — removed.")
    Orction_DisplayResults()
end

-- ── AH panel state ────────────────────────────────────────────────────────
-- Deposit and item slot display are driven by Orction_OnItemDrop / Orction_ClearItemSlot
-- (defined after the inventory helpers so they can use Orction_FindBagSlot).

-- ── Inventory helpers ─────────────────────────────────────────────────────

local function Orction_GetInventoryCount(itemName)
    local total = 0
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = string.gsub(link, ".*%[(.-)%].*", "%1")
                if name == itemName then
                    local _, count = GetContainerItemInfo(bag, slot)
                    total = total + (count or 1)
                end
            end
        end
    end
    return total
end

local function Orction_GetMaxStacks(itemName, stackSize)
    if not stackSize or stackSize <= 0 then return 0 end
    return math.floor(Orction_GetInventoryCount(itemName) / stackSize)
end

-- Returns vendor sell price in copper for itemName, or 0 if not determinable.
local function Orction_GetVendorPrice(itemName)
    return OrctionVendor_GetPrice(itemName)
end

-- First bag slot holding >= needed items of itemName.
-- excludeSlots: optional set keyed by (bag*1000+slot) of slots to skip
-- (used to avoid stale data on slots we just emptied this session).
local function Orction_FindBagSlot(itemName, needed, excludeSlots)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local k = bag * 1000 + slot
            if not (excludeSlots and excludeSlots[k]) then
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local name = string.gsub(link, ".*%[(.-)%].*", "%1")
                    if name == itemName then
                        local _, count = GetContainerItemInfo(bag, slot)
                        if (count or 0) >= needed then
                            return bag, slot, (count or 0)
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Loads 7-day price history for the given item name and refreshes the bar graph.
local function Orction_UpdatePriceGraph(name)
    if not orctionPriceBarGraph then return end
    local entry = OrctionData_GetItemHistory and OrctionData_GetItemHistory(nil, name)
    if not entry then
        orctionPriceBarGraph:Hide()
        return
    end
    -- Compute day labels relative to today's rolling slot
    local todaySlot = math.mod((tonumber(date("%j")) or 1) + (ORCTION_DAY_OFFSET or 0), 7) + 1
    local values   = {}
    local counts   = {}
    local colNames = {}
    for i = 1, 7 do
        values[i] = entry["day" .. i .. "Price"] or 0
        counts[i] = entry["day" .. i .. "Count"] or 0
        local daysAgo = math.mod(todaySlot - i + 7, 7)
        if daysAgo == 0 then
            colNames[i] = "Today"
        elseif daysAgo == 1 then
            colNames[i] = "Yesterday"
        else
            colNames[i] = daysAgo .. "d ago"
        end
    end
    orctionPriceBarGraph:SetData(values, colNames, "positive", counts)
end

-- Populates the post panel with item info from a result row click (no sell-slot item).
-- Disables Create Auction since nothing is actually queued to sell.
Orction_PreviewItem = function(name, texture, vendorPrice)
    if OrctionItemTexture then
        if texture then
            OrctionItemTexture:SetTexture(texture)
            OrctionItemTexture:Show()
        else
            OrctionItemTexture:Hide()
        end
    end
    if OrctionItemNameText then OrctionItemNameText:SetText(name) end
    if OrctionVendorSellValue then
        local vp = vendorPrice or 0
        if vp > 0 then
            OrctionVendorSellValue:SetText(FormatMoneyColour(vp))
        else
            OrctionVendorSellValue:SetText("--")
        end
    end
    if OrctionCreateBtn then OrctionCreateBtn:Disable() end
    Orction_UpdatePriceGraph(name)
end

-- Called when user drops an item onto the slot.
-- ClearCursor is reliable when cursor item came from a bag (returns to source bag slot).
-- We scan empty slots before + after to identify which slot the item returned to,
-- then read name/texture/count from that bag slot.
-- The sell slot is NEVER touched here — only during the actual StartAuction call.
-- Finalises a confirmed drop: updates display, saves stack count preference, starts search.
local function Orction_CompleteItemDrop(name, texture, count)
    OrctionItemTexture:SetTexture(texture)
    OrctionItemTexture:Show()
    OrctionItemNameText:SetText(name)
    if OrctionCountBox then OrctionCountBox:SetText(tostring(count)) end
    if OrctionStacksBox then
        OrctionStacksBox:SetText(tostring(Orction_GetMaxStacks(name, count)))
    end
    if OrctionDB then OrctionDB.stackCounts[name] = count end
    orctionSellName = name
    if OrctionCreateBtn then OrctionCreateBtn:Enable() end
    if OrctionSearchBox then OrctionSearchBox:SetText(name) end
    orctionVendorPrice = Orction_GetVendorPrice(name)
    Orction_UpdateDeposit()
    Orction_StartSearch(name, 0, 0)
    Orction_UpdatePriceGraph(name)
end

local function Orction_HandleSellSlotItem(name, texture, count)
    if not name then return end
    local lastCount = OrctionDB and OrctionDB.stackCounts and OrctionDB.stackCounts[name]
    if lastCount and lastCount ~= count then
        -- Count differs from last used — ask before committing
        orctionPendingDrop = { name = name, texture = texture, count = count }
        StaticPopup_Show("ORCTION_STACK_CONFIRM", name, count)
    else
        Orction_CompleteItemDrop(name, texture, count)
    end
end

-- Called when the user drops an item onto the slot.
local function Orction_OnItemDrop()
    local hadSellItem = GetAuctionSellItemInfo() and true or false
    ClickAuctionSellItemButton()  -- cursor → sell slot
    local name, texture, count = GetAuctionSellItemInfo()
    if hadSellItem then
        orctionPendingSellRead = true
        orctionSellPollElapsed = 0
        return
    end
    if not name then
        if CursorHasItem() then
            ClearCursor()
            DEFAULT_CHAT_FRAME:AddMessage("Orction: This item cannot be auctioned.")
            return
        end
        orctionPendingSellRead = true
        orctionSellPollElapsed = 0
        return
    end
    Orction_HandleSellSlotItem(name, texture, count)
end

local function Orction_ClearItemSlot(keepCursor)
    StaticPopup_Hide("ORCTION_STACK_CONFIRM")
    orctionPendingDrop = nil
    orctionPendingSellRead = false
    orctionSellPollElapsed = 0
    if GetAuctionSellItemInfo() then
        ClickAuctionSellItemButton()
        if not keepCursor then
            ClearCursor()
        end
    end
    OrctionItemTexture:Hide()
    OrctionItemNameText:SetText("")
    if OrctionDepositValue  then OrctionDepositValue:SetText("--") end
    if OrctionTotalFeeValue then OrctionTotalFeeValue:SetText("") end
    if OrctionProfitValue   then OrctionProfitValue:SetText("") end
    orctionSearchName  = nil
    orctionSellName    = nil
    orctionVendorPrice = nil
    if OrctionVendorSellValue then OrctionVendorSellValue:SetText("--") end
    orctionPendingPost = nil
    if OrctionCreateBtn then OrctionCreateBtn:SetText("Create Auction") end
    for i = 1, table.getn(orctionResultRows) do
        orctionResultRows[i].frame:Hide()
    end
    if OrctionSearchingText then OrctionSearchingText:Hide() end
    if OrctionNoResultsText  then OrctionNoResultsText:Hide() end
end

-- Returns the first empty bag slot (bag, slot), or nil if bags are full.
local function Orction_FindEmptyBagSlot()
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            if not GetContainerItemLink(bag, slot) then
                return bag, slot
            end
        end
    end
    return nil
end

-- ── Posting logic ─────────────────────────────────────────────────────────
--
-- TurtleWoW hard limits discovered through testing:
--   1. SplitContainerItem picks up the ENTIRE source stack (or ClickAuctionSellItemButton
--      reads the SOURCE bag slot, not the cursor count).  Either way, calling
--      ClickAuctionSellItemButton immediately after SplitContainerItem posts the
--      full source stack, not the split count.
--   2. The fix: split → stage in a fresh empty bag slot (PickupContainerItem to
--      place — this DOES work for empty slots).  That fresh slot now contains
--      exactly `count` items and has no "source" pointing back to a larger stack.
--      On the NEXT hardware-event click, PickupContainerItem that staged slot →
--      ClickAuctionSellItemButton → StartAuction.
--   3. One bag operation per hardware event; SplitContainerItem + PickupContainerItem
--      (place) is exactly two bag ops and works.  PickupContainerItem (pickup) alone
--      is one bag op and works.
--
-- Per-stack flow (two button clicks):
--   Click "Stage k/N"  → SplitContainerItem(src,count) + PickupContainerItem(temp)
--                         Button becomes "Post k/N"
--   Click "Post k/N"   → SellSlotClear check + PickupContainerItem(temp)
--                         + ClickAuctionSellItemButton + StartAuction
--                         Button becomes "Stage (k+1)/N" or "Create Auction"
--
-- pendingPost fields:
--   name, startBid, buyout, count, totalStacks, stacksLeft
--   staged = false|true   (whether temp slot is ready to post)
--   tempBag, tempSlot     (location of staged items, valid when staged=true)

local function Orction_SellSlotClear()
    if CursorHasItem() then ClearCursor() end
    ClickAuctionSellItemButton()
    if not CursorHasItem() then return true end
    ClearCursor()
    return false
end

-- Resets the sell-side UI without touching search results.
-- Clears the AH sell slot, resets count/stacks to 1, clears all value displays.
local function Orction_ResetPostUI()
    if GetAuctionSellItemInfo() then
        ClickAuctionSellItemButton()
        ClearCursor()
    end
    if OrctionItemTexture   then OrctionItemTexture:Hide() end
    if OrctionItemNameText  then OrctionItemNameText:SetText("") end
    if OrctionCountBox      then OrctionCountBox:SetText("1") end
    if OrctionStacksBox     then OrctionStacksBox:SetText("1") end
    if OrctionDepositValue  then OrctionDepositValue:SetText("--") end
    if OrctionTotalFeeValue then OrctionTotalFeeValue:SetText("") end
    if OrctionProfitValue   then OrctionProfitValue:SetText("") end
    if OrctionVendorSellValue then OrctionVendorSellValue:SetText("--") end
    if OrctionCreateBtn     then OrctionCreateBtn:SetText("Create Auction") ; OrctionCreateBtn:Disable() end
    if orctionPriceBarGraph then orctionPriceBarGraph:Hide() end
    orctionSellName    = nil
    orctionVendorPrice = nil
    orctionPendingPost = nil
end

local function Orction_CreateAuction()
    -- ── Pending post: stage or post depending on phase ─────────────────────
    if orctionPendingPost then
        local p = orctionPendingPost

        if p.staged then
            -- ── Phase 2: sell slot clear check + pick up staged slot + post ──
            if not Orction_SellSlotClear() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Previous auction processing — click again.")
                return   -- keep pendingPost, user retries
            end

            p.excludeSlots[p.tempBag * 1000 + p.tempSlot] = true
            PickupContainerItem(p.tempBag, p.tempSlot)
            if not CursorHasItem() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Staged slot empty — aborting.")
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            ClickAuctionSellItemButton()
            local _, _, fc = GetAuctionSellItemInfo()
            if not fc then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Item not in sell slot.")
                if CursorHasItem() then ClearCursor() end
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            local durIdx = ORCTION_AUCTION_DURATION or 2
            local postDuration = durIdx == 1 and 120 or durIdx == 3 and 1440 or 480
            StartAuction(p.startBid, p.buyout, postDuration)

            p.stacksLeft = p.stacksLeft - 1
            p.staged     = false
            p.tempBag    = nil
            p.tempSlot   = nil

            if p.stacksLeft <= 0 then
                Orction_ResetPostUI()
            else
                local next = p.totalStacks - p.stacksLeft + 1
                OrctionCreateBtn:SetText("Stage " .. next .. "/" .. p.totalStacks)
            end

        else
            -- ── Phase 1: split count items → stage in empty bag slot ─────────
            local bag, slot, bagCount = Orction_FindBagSlot(p.name, p.count, p.excludeSlots)
            if not bag then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: No source items — aborting.")
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            local eb, es = Orction_FindEmptyBagSlot()
            if not eb then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: No empty bag slot for staging — aborting.")
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            if bagCount > p.count then
                SplitContainerItem(bag, slot, p.count)
            else
                PickupContainerItem(bag, slot)
                -- Whole slot picked up — mark as emptied so stale data won't resurface it
                p.excludeSlots[bag * 1000 + slot] = true
            end

            if not CursorHasItem() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Failed to pick up items — aborting.")
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            PickupContainerItem(eb, es)
            if CursorHasItem() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Failed to place in staging slot — aborting.")
                ClearCursor()
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            p.staged   = true
            p.tempBag  = eb
            p.tempSlot = es
            local cur = p.totalStacks - p.stacksLeft + 1
            OrctionCreateBtn:SetText("Post " .. cur .. "/" .. p.totalStacks)
        end
        return
    end

    -- ── First click: validate + park sell slot (1 bag op) ─────────────────
    local name = orctionSellName
    if not name then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: Drop an item in the slot first.")
        return
    end

    local count    = math.max(1, tonumber(OrctionCountBox:GetText())  or 1)
    local stacks   = math.max(1, tonumber(OrctionStacksBox:GetText()) or 1)
    local buyout   = MoneyInputFrame_GetCopper(OrctionBuyout)
    local startBid = buyout

    local have = Orction_GetInventoryCount(name)
    local sn, _, sc = GetAuctionSellItemInfo()
    if sn == name then have = have + (sc or 0) end
    local need = count * stacks
    if have < need then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: Need " .. need .. " " .. name .. ", have " .. have .. ".")
        return
    end

    -- Fast path: single stack and sell slot already has exactly the right count
    if stacks == 1 then
        local sn2, _, sc2 = GetAuctionSellItemInfo()
        if sn2 == name and sc2 == count then
            local durIdx = ORCTION_AUCTION_DURATION or 2
            local postDuration = durIdx == 1 and 120 or durIdx == 3 and 1440 or 480
            StartAuction(startBid, buyout, postDuration)
            Orction_ResetPostUI()
            return
        end
    end

    -- Park the dragged sell slot item into bags so it can be split correctly.
    if CursorHasItem() then ClearCursor() end
    ClickAuctionSellItemButton()
    if CursorHasItem() then
        local eb, es = Orction_FindEmptyBagSlot()
        if not eb then
            DEFAULT_CHAT_FRAME:AddMessage("Orction: Bags full — cannot park item.")
            ClearCursor()
            return
        end
        PickupContainerItem(eb, es)
        if CursorHasItem() then
            DEFAULT_CHAT_FRAME:AddMessage("Orction: Could not park sell slot item.")
            ClearCursor()
            return
        end
    end

    orctionPendingPost = {
        name = name, startBid = startBid, buyout = buyout, count = count,
        totalStacks = stacks, stacksLeft = stacks,
        staged = false, tempBag = nil, tempSlot = nil,
        excludeSlots = {},
    }
    OrctionCreateBtn:SetText("Stage 1/" .. stacks)
end

-- ── Stack size confirmation dialog ────────────────────────────────────────

StaticPopupDialogs["ORCTION_STACK_CONFIRM"] = {
    text         = "Sell %s in stacks of %d?",
    button1      = "Yes",
    button2      = "No",
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    OnAccept = function()
        if orctionPendingDrop then
            local p = orctionPendingDrop
            orctionPendingDrop = nil
            Orction_CompleteItemDrop(p.name, p.texture, p.count)
        end
    end,
    OnCancel = function()
        orctionPendingDrop = nil
        -- Return sell slot item to cursor so user can place it in bags and split
        if GetAuctionSellItemInfo() then
            ClickAuctionSellItemButton()
        end
        DEFAULT_CHAT_FRAME:AddMessage("Orction: Stack returned. Shift+click your bag stack to split, then re-drag.")
    end,
}

-- ── Build the AH panel ────────────────────────────────────────────────────

local function Orction_DoTextSearch()
    if not OrctionSearchBox then return end
    local text = OrctionSearchBox:GetText()
    if text and string.len(text) > 0 then
        if OrctionDB and OrctionDB.settings and OrctionDB.settings.titleCaseSearch then
            local corrected = Orction_TitleCaseWords(text)
            if corrected ~= text then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Corrected to " .. corrected)
            end
            text = corrected
            OrctionSearchBox:SetText(corrected)
        end
    else
        text = ""  -- empty search: browse by category / usable filter only
    end
    Orction_ResetPostUI()
    orctionVendorPrice = Orction_GetVendorPrice(text)
    Orction_StartSearch(text, orctionSearchClassIndex, orctionSearchSubIndex)
end

-- ── Watchlist helpers ─────────────────────────────────────────────────────

local function Orction_GetWatchlist()
    if not OrctionDB then OrctionDB = {} end
    if not OrctionDB.watchlist then OrctionDB.watchlist = {} end
    return OrctionDB.watchlist
end

local function Orction_NormalizeWatchEntry(entry)
    if type(entry) == "string" then
        return { name = entry, classIndex = 0, subIndex = 0 }
    end
    if type(entry) == "table" and entry.name then
        if not entry.classIndex then entry.classIndex = 0 end
        if not entry.subIndex then entry.subIndex = 0 end
        return entry
    end
    return nil
end

local function Orction_RefreshWatchlist()
    if not OrctionWatchlistScroll then return end
    local list   = Orction_GetWatchlist()
    local count  = table.getn(list)
    local offset = FauxScrollFrame_GetOffset(OrctionWatchlistScroll)
    FauxScrollFrame_Update(OrctionWatchlistScroll, count, WL_MAX_ROWS, WL_ROW_H)
    for i = 1, WL_MAX_ROWS do
        local idx = i + offset
        local row = orctionWatchlistRows[i]
        if not row then break end
        if idx <= count then
            local entry = Orction_NormalizeWatchEntry(list[idx])
            if entry then
                row.nameLabel:SetText(entry.name)
                row.nameBtn._entry = entry
                row.detailsBtn._entry = entry
                row.removeBtn._index  = idx
                row:Show()
            else
                row:Hide()
            end
        else
            row:Hide()
        end
    end
end

Orction_AddToWatchlist = function(name, classIndex, subIndex)
    if not name or string.len(name) == 0 then return end
    local list = Orction_GetWatchlist()
    for i = 1, table.getn(list) do
        local entry = Orction_NormalizeWatchEntry(list[i])
        if entry and entry.name == name and (entry.classIndex or 0) == (classIndex or 0)
           and (entry.subIndex or 0) == (subIndex or 0) then
            DEFAULT_CHAT_FRAME:AddMessage("Orction: '" .. name .. "' already in watchlist")
            return
        end
    end
    table.insert(list, { name = name, classIndex = classIndex or 0, subIndex = subIndex or 0 })
    DEFAULT_CHAT_FRAME:AddMessage("Orction: added '" .. name .. "' to watchlist (" .. table.getn(list) .. " items)")
    Orction_RefreshWatchlist()
end

local function Orction_RemoveFromWatchlist(idx)
    local list = Orction_GetWatchlist()
    table.remove(list, idx)
    Orction_RefreshWatchlist()
end

-- ── Scan helpers ──────────────────────────────────────────────────────────

local function Orction_ScanNext()
    if not orctionScanQueue then return end
    orctionScanIndex = orctionScanIndex + 1
    local total = table.getn(orctionScanQueue)
    if orctionScanIndex > total then
        -- All items scanned — display accumulated results
        orctionScanResultsShowing = true
        Orction_DisplayResults()
        orctionScanMode  = false
        orctionScanQueue = nil
        if OrctionSearchingText then OrctionSearchingText:SetText("Scan complete") ; OrctionSearchingText:Show() end
        DEFAULT_CHAT_FRAME:AddMessage(
            "Orction: scan complete — " .. table.getn(orctionSimilarResults) .. " results")
        return
    end
    local entry = Orction_NormalizeWatchEntry(orctionScanQueue[orctionScanIndex])
    if not entry then
        Orction_ScanNext()
        return
    end
    local name = entry.name
    orctionSearchName        = name
    orctionSearchPage        = 0
    orctionSearchActive      = true
    orctionPageProcessed     = false
    orctionSearchRetry       = false
    orctionQueryDelay        = 0
    orctionWaitTimeout       = 0
    orctionResponseReceived  = false
    orctionQueryRetryCount   = 0
    orctionScanItemStartCount = table.getn(orctionSimilarResults)
    if OrctionSearchingText then
        OrctionSearchingText:SetText(
            "Scanning " .. orctionScanIndex .. "/" .. total .. ": " .. name)
        OrctionSearchingText:Show()
    end
    Orction_SetSearchCategory(entry.classIndex or 0, entry.subIndex or 0)
    Orction_Query(name, 0)
end

local function Orction_StartScan()
    local list = Orction_GetWatchlist()
    if table.getn(list) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: watchlist is empty")
        return
    end
    orctionScanCancel          = false
    orctionScanResultsShowing  = false
    orctionSearchResults  = {}
    orctionSimilarResults = {}
    orctionVendorCache    = {}
    orctionScanMode       = true
    orctionScanQueue      = list
    orctionScanIndex      = 0
    for i = 1, table.getn(orctionResultRows) do
        orctionResultRows[i].frame:Hide()
    end
    if OrctionNoResultsText      then OrctionNoResultsText:Hide()      end
    if OrctionSimilarResultsText then OrctionSimilarResultsText:Hide() end
    Orction_ScanNext()
end

-- Extracted to keep Orction_StartFullScan under Lua 5.0's 32-upvalue limit.
local function Orction_ResetFullScanState()
    orctionScanCancel             = false
    orctionScanMode               = false
    orctionScanResultsShowing     = false
    orctionScanQueue              = nil
    orctionScanNextPending        = false
    orctionFullScanActive         = true
    orctionFullScanResultsShowing = false
    orctionFullScanPagesProcessed = 0
    orctionSearchName             = ""
    orctionSearchPage             = 0
    orctionSearchActive           = true
    orctionPageProcessed          = false
    orctionSearchRetry            = false
    orctionQueryDelay             = 0
    orctionWaitTimeout            = 0
    orctionResponseReceived       = false
    orctionSearchStartPage        = 0
    orctionNextStartPage          = 0
    orctionHasMorePages           = false
    orctionQueryRetryCount        = 0
    orctionSearchResults          = {}
    orctionSimilarResults         = {}
    orctionVendorCache            = {}
    orctionPriceWriteQueue        = {}
    orctionSearchRecorded         = {}
    for i = 1, table.getn(orctionResultRows) do
        orctionResultRows[i].frame:Hide()
    end
    if OrctionNoResultsText      then OrctionNoResultsText:Hide()      end
    if OrctionSimilarResultsText then OrctionSimilarResultsText:Hide() end
    if OrctionSearchingText      then OrctionSearchingText:Show()      end
end

local function Orction_StartFullScan()
    Orction_ResetFullScanState()
    Orction_ResetPostUI()
    local catLabel = Orction_GetCategoryLabel()
    DEFAULT_CHAT_FRAME:AddMessage("Orction: scanning [" .. catLabel .. "]...")
    Orction_UpdateSearchingText()
    Orction_SetSearchCategory(orctionSearchClassIndex, orctionSearchSubIndex)
    Orction_Query("", 0)
end

-- ── OnUpdate handler (module-level to avoid adding upvalues to BuildAHPanel) ──

local function Orction_AHPanel_OnUpdate()
    if orctionScanCancel then
        orctionScanCancel             = false
        orctionScanMode               = false
        orctionScanResultsShowing     = false
        orctionScanQueue              = nil
        orctionScanNextPending        = false
        orctionScanNextDelay          = 0
        orctionFullScanActive         = false
        orctionFullScanResultsShowing = false
        orctionSearchActive           = false
        orctionSearchRetry            = false
        orctionQueryRetryCount        = 0
        orctionQueryDelay             = 0
        orctionWaitTimeout            = 0
        if OrctionSearchingText then OrctionSearchingText:Hide() end
        DEFAULT_CHAT_FRAME:AddMessage("Orction: scan cancelled")
        Orction_DisplayResults()
        return
    end
    if orctionPendingSellRead then
        orctionSellPollElapsed = orctionSellPollElapsed + arg1
        local name, texture, count = GetAuctionSellItemInfo()
        if name then
            orctionPendingSellRead = false
            orctionSellPollElapsed = 0
            Orction_HandleSellSlotItem(name, texture, count)
        elseif orctionSellPollElapsed >= 1.0 then
            orctionPendingSellRead = false
            orctionSellPollElapsed = 0
            DEFAULT_CHAT_FRAME:AddMessage("Orction: sell slot read timed out")
        end
    end
    if orctionBuyBidPlaced then
        orctionBuyBidTimeout = orctionBuyBidTimeout + arg1
        if orctionBuyBidTimeout >= 3.0 then
            if not orctionBuyBidRechecked and orctionBuyPending then
                orctionBuyBidRechecked = true
                orctionBuyBidTimeout   = 0
                Orction_Query(orctionBuyPending.name, 0)
            else
                orctionBuyPending      = nil
                orctionBuyBidPlaced    = false
                orctionBuyBidRechecked = false
                orctionBuyBidTimeout   = 0
                DEFAULT_CHAT_FRAME:AddMessage("Orction: buy confirmation timed out.")
            end
        end
    end
    -- Drain the async price-write queue: process up to 10 items per tick.
    -- Runs during inter-page delays and after search completes.
    if table.getn(orctionPriceWriteQueue) > 0 and OrctionData_RecordScanPrice then
        for _ = 1, 10 do
            if table.getn(orctionPriceWriteQueue) == 0 then break end
            local item = table.remove(orctionPriceWriteQueue, 1)
            if not OrctionData_ShouldRecord or OrctionData_ShouldRecord(item.itemId, item.name) then
                OrctionData_RecordScanPrice(item.itemId, item.name, item.price, 1)
            end
        end
    end
    if orctionScanNextPending then
        orctionScanNextDelay = orctionScanNextDelay + arg1
        if orctionScanNextDelay >= 0.5 then
            orctionScanNextPending = false
            orctionScanNextDelay   = 0
            Orction_ScanNext()
        end
    elseif orctionSearchRetry then
        orctionQueryDelay = orctionQueryDelay + arg1
        -- Rate-limit retries use ORCTION_RETRY_DELAY; page pagination uses 0.3s
        local threshold = (orctionQueryRetryCount > 0) and ORCTION_RETRY_DELAY or 0.3
        if orctionQueryDelay >= threshold then
            orctionSearchRetry      = false
            orctionPageProcessed    = false
            orctionResponseReceived = false
            orctionWaitTimeout      = 0
            orctionQueryDelay       = 0
            Orction_Query(orctionSearchName, orctionSearchPage)
        end
    elseif orctionSearchActive then
        orctionWaitTimeout = orctionWaitTimeout + arg1
        -- Use a short window if the server already responded with batch=0 (genuine no results).
        -- Use the full 3s only when no response has arrived at all (rate limited / queued).
        local waitLimit = orctionResponseReceived and 0.8 or 3.0
        if orctionWaitTimeout >= waitLimit then
            if not orctionResponseReceived and orctionQueryRetryCount < ORCTION_MAX_RETRIES then
                -- No response at all → likely rate limited, retry
                orctionQueryRetryCount = orctionQueryRetryCount + 1
                orctionPageProcessed   = false
                orctionWaitTimeout     = 0
                orctionSearchRetry = true   -- OnUpdate will re-fire QueryAuctionItems
                orctionQueryDelay  = 0      -- rate-limit path uses ORCTION_RETRY_DELAY threshold
            else
                -- Either server replied with 0 results, or retries exhausted → advance
                orctionSearchActive      = false
                orctionQueryRetryCount   = 0
                orctionResponseReceived  = false
                if orctionScanMode then
                    orctionScanNextPending = true
                    orctionScanNextDelay   = 0
                else
                    Orction_DisplayResults()
                end
            end
        end
    end
end

local function Orction_AHPanel_OnEvent()
    if event == "AUCTION_ITEM_LIST_UPDATE" then
        if orctionBuyPending then
            Orction_TryBuy()
        else
            Orction_CollectPage()
        end
    elseif event == "NEW_AUCTION_UPDATE" then
        if orctionPendingSellRead then
            local name, texture, count = GetAuctionSellItemInfo()
            if name then
                orctionPendingSellRead = false
                Orction_HandleSellSlotItem(name, texture, count)
            end
        end
    end
end

-- ── Build the AH panel ────────────────────────────────────────────────────

local function Orction_BuildAHPanel()
    OrctionAHPanel = CreateFrame("Frame", "OrctionAHPanel", AuctionFrame)
    OrctionAHPanel:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 0, 0)
    OrctionAHPanel:SetWidth(AuctionFrame:GetWidth())
    OrctionAHPanel:SetHeight(AuctionFrame:GetHeight())
    OrctionAHPanel:SetFrameLevel(AuctionFrameAuctions:GetFrameLevel() + 20)

    OrctionAHPanel:Hide()

    -- ── Search bar (top, full width) ──────────────────────────────────────────
    OrctionSearchBox = CreateFrame("EditBox", "OrctionSearchBox", OrctionAHPanel, "InputBoxTemplate")
    OrctionSearchBox:SetWidth(100)
    OrctionSearchBox:SetHeight(25)
    OrctionSearchBox:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 76, -50)
    OrctionSearchBox:SetAutoFocus(false)
    OrctionSearchBox:SetMaxLetters(64)
    OrctionSearchBox:SetScript("OnEnterPressed", function()
        this:ClearFocus()
        Orction_DoTextSearch()
    end)
    OrctionSearchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    local searchBtn = CreateFrame("Button", "OrctionSearchBtn", OrctionAHPanel)
    searchBtn:SetWidth(22)
    searchBtn:SetHeight(22)
    searchBtn:SetPoint("LEFT", OrctionSearchBox, "RIGHT", -14, 0)
    searchBtn:SetNormalTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchBtn:SetHighlightTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchBtn:GetHighlightTexture():SetBlendMode("ADD")
    searchBtn:SetScript("OnClick", Orction_DoTextSearch)

    local addWatchBtn = CreateFrame("Button", nil, OrctionAHPanel, "UIPanelButtonTemplate")
    addWatchBtn:SetWidth(36)
    addWatchBtn:SetHeight(22)
    addWatchBtn:SetPoint("LEFT", searchBtn, "RIGHT", 4, 0)
    addWatchBtn:SetText("WL+")
    addWatchBtn:SetScript("OnClick", function()
        local text = OrctionSearchBox:GetText()
        if text and string.len(text) > 0 then
            Orction_AddToWatchlist(text, orctionSearchClassIndex, orctionSearchSubIndex)
        end
    end)

    OrctionExactMatchCheck = CreateFrame("CheckButton", "OrctionExactMatchCheck", OrctionAHPanel, "OptionsCheckButtonTemplate")
    OrctionExactMatchCheck:SetPoint("LEFT", addWatchBtn, "RIGHT", 8, 0)
    getglobal("OrctionExactMatchCheckText"):SetText("Exact")
    OrctionExactMatchCheck:SetHitRectInsets(0, 5, 0, 0)
    OrctionExactMatchCheck:SetWidth(30)
    OrctionExactMatchCheck:SetChecked(1)
    OrctionExactMatchCheck:SetScript("OnClick", function()
        if OrctionDB and OrctionDB.settings then
            OrctionDB.settings.exactMatch = not (this:GetChecked() == nil)
        end
    end)

    OrctionCategoryDropDown = CreateFrame("Frame", "OrctionCategoryDropDown", OrctionAHPanel, "UIDropDownMenuTemplate")
    OrctionCategoryDropDown:SetPoint("LEFT", OrctionExactMatchCheck, "RIGHT", 20, 2)
    UIDropDownMenu_SetWidth(60, OrctionCategoryDropDown)
    UIDropDownMenu_SetText("None", OrctionCategoryDropDown)

    OrctionSubcategoryDropDown = CreateFrame("Frame", "OrctionSubcategoryDropDown", OrctionAHPanel, "UIDropDownMenuTemplate")
    OrctionSubcategoryDropDown:SetPoint("LEFT", OrctionCategoryDropDown, "RIGHT", -15, 0)
    UIDropDownMenu_SetWidth(60, OrctionSubcategoryDropDown)
    UIDropDownMenu_SetText("None", OrctionSubcategoryDropDown)
    if UIDropDownMenu_DisableDropDown then
        UIDropDownMenu_DisableDropDown(OrctionSubcategoryDropDown)
    else
        local btn = getglobal("OrctionSubcategoryDropDownButton")
        if btn then btn:Disable() end
    end

    Orction_InitCategoryDropDown()
    Orction_InitSubcategoryDropDown()

    local OrctionUsableCheck = CreateFrame("CheckButton", "OrctionUsableCheck", OrctionAHPanel, "OptionsCheckButtonTemplate")
    OrctionUsableCheck:SetPoint("LEFT", OrctionSubcategoryDropDown, "RIGHT", 0, -2)
    getglobal("OrctionUsableCheckText"):SetText("Usable")
    OrctionUsableCheck:SetWidth(30)
    OrctionUsableCheck:SetHitRectInsets(0, 5, 0, 0)
    OrctionUsableCheck:SetChecked(nil)
    OrctionUsableCheck:SetScript("OnClick", function()
        orctionUsableOnly = not (this:GetChecked() == nil)
    end)

    -- ── Left panel: absolute positions cloned from AuctionFrameAuctions children ─
    -- All SetPoint anchors are relative to OrctionAHPanel TOPLEFT (= AuctionFrame TOPLEFT).
    -- x/y values match the dump output so elements land on the same background areas.

    -- Item slot (60x60, anchored at x=27 y=-95)
    --local itemLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    --itemLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 27, -78)
    --itemLabel:SetText("Auction Item")

    -- drag drop area
    local itemSlot = CreateFrame("Button", "OrctionItemSlot", OrctionAHPanel)
    itemSlot:SetWidth(65)
    itemSlot:SetHeight(65)
    itemSlot:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 27, -96)
    itemSlot:RegisterForDrag("LeftButton")
    itemSlot:EnableMouse(true)

    -- drag dropped item texture
    OrctionItemTexture = itemSlot:CreateTexture("OrctionItemTexture", "ARTWORK")
    OrctionItemTexture:SetWidth(38)
    OrctionItemTexture:SetHeight(38)
    OrctionItemTexture:SetPoint("TOPLEFT", itemSlot, "TOPLEFT", 0, 0)
    OrctionItemTexture:Hide()

    itemSlot:SetScript("OnReceiveDrag", Orction_OnItemDrop)
    itemSlot:SetScript("OnClick", function()
        if CursorHasItem() then
            Orction_OnItemDrop()
        else
            Orction_ClearItemSlot()
        end
    end)
    itemSlot:SetScript("OnDragStart", function()
        if GetAuctionSellItemInfo() then
            ClickAuctionSellItemButton()
            Orction_ClearItemSlot(true)
        end
    end)
    itemSlot:SetScript("OnEnter", function()
        if orctionSellName then
            local b, s = Orction_FindBagSlot(orctionSellName, 1)
            if b then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetBagItem(b, s)
                GameTooltip:Show()
            end
        end
    end)
    itemSlot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    OrctionItemNameText = OrctionAHPanel:CreateFontString("OrctionItemNameText", "ARTWORK", "GameFontHighlight")
    OrctionItemNameText:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 68, -105)
    OrctionItemNameText:SetWidth(120)
    OrctionItemNameText:SetText("")

    -- Vendor Sell (below item slot)
    local vendorSellLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    vendorSellLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 73, -132)
    vendorSellLabel:SetText("vendor:")

    OrctionVendorSellValue = OrctionAHPanel:CreateFontString("OrctionVendorSellValue", "ARTWORK", "GameFontHighlightSmall")
    OrctionVendorSellValue:SetPoint("LEFT", vendorSellLabel, "RIGHT", 4, 0)
    OrctionVendorSellValue:SetText("--")

    -- Duration selector  ──────────────────────────────────────────────────────
    local durLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    durLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 30, -79)
    durLabel:SetText("Duration:")

    local durOptions = {"6h", "24h", "72h"}
    for i = 1, 3 do
        local b = CreateFrame("Button", "OrctionDurBtn"..i, OrctionAHPanel, "UIPanelButtonTemplate")
        b:SetWidth(38)
        b:SetHeight(18)
        if i == 1 then
            b:SetPoint("LEFT", durLabel, "RIGHT", 4, 0)
        else
            b:SetPoint("LEFT", getglobal("OrctionDurBtn"..(i-1)), "RIGHT", 2, 0)
        end
        b:SetText(durOptions[i])
        local idx = i
        b:SetScript("OnClick", function()
            ORCTION_AUCTION_DURATION = idx
            if OrctionDB and OrctionDB.settings then
                OrctionDB.settings.auctionDuration = idx
            end
            -- Highlight selected button with gold text, others normal
            for j = 1, 3 do
                local bj = getglobal("OrctionDurBtn"..j)
                if bj then
                    if j == idx then
                        bj:GetFontString():SetTextColor(1, 0.82, 0)
                    else
                        bj:GetFontString():SetTextColor(1, 1, 1)
                    end
                end
            end
            Orction_UpdateDeposit()
        end)
    end
    -- Apply initial highlight
    do
        local initDur = ORCTION_AUCTION_DURATION or 2
        for j = 1, 3 do
            local bj = getglobal("OrctionDurBtn"..j)
            if bj then
                if j == initDur then bj:GetFontString():SetTextColor(1, 0.82, 0)
                else                  bj:GetFontString():SetTextColor(1, 1, 1) end
            end
        end
    end

    -- Count / Stacks on the same row  ─────────────────────────────────────────
    local countLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    countLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 25, -168)
    countLabel:SetText("Count")

    local stacksLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    stacksLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 120, -152)
    stacksLabel:SetText("Stacks")

    OrctionCountBox = CreateFrame("EditBox", "OrctionCountBox", OrctionAHPanel, "InputBoxTemplate")
    OrctionCountBox:SetWidth(34)
    OrctionCountBox:SetHeight(18)
    OrctionCountBox:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 64, -165)
    OrctionCountBox:SetMaxLetters(4)
    OrctionCountBox:SetAutoFocus(false)
    OrctionCountBox:SetText("1")
    OrctionCountBox:SetScript("OnTextChanged", function() Orction_UpdateDeposit() end)

    OrctionStacksBox = CreateFrame("EditBox", "OrctionStacksBox", OrctionAHPanel, "InputBoxTemplate")
    OrctionStacksBox:SetWidth(15)
    OrctionStacksBox:SetHeight(18)
    OrctionStacksBox:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 123, -165)
    OrctionStacksBox:SetMaxLetters(3)
    OrctionStacksBox:SetAutoFocus(false)
    OrctionStacksBox:SetText("1")
    OrctionStacksBox:SetScript("OnTextChanged", function() Orction_UpdateDeposit() end)

    local maxStacksBtn = CreateFrame("Button", nil, OrctionAHPanel, "UIPanelButtonTemplate")
    maxStacksBtn:SetWidth(50)
    maxStacksBtn:SetHeight(18)
    maxStacksBtn:SetPoint("LEFT", OrctionStacksBox, "RIGHT", 4, 0)
    maxStacksBtn:SetText("Max")
    maxStacksBtn:SetScript("OnClick", function()
        if not orctionSellName then return end
        local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
        OrctionStacksBox:SetText(tostring(Orction_GetMaxStacks(orctionSellName, count)))
    end)

    -- Buyout Price  ────────────────────────────────────────────────────────────
    local buyoutLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    buyoutLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 30, -190)
    buyoutLabel:SetText("Price")

    OrctionBuyout = CreateFrame("Frame", "OrctionBuyout", OrctionAHPanel, "MoneyInputFrameTemplate")
    OrctionBuyout:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 65, -186)
    ResizeMoneyInputFrame("OrctionBuyout")
    -- Trigger recalculation when sell price changes
    for _, suffix in ipairs({"Gold", "Silver", "Copper"}) do
        local eb = getglobal("OrctionBuyout" .. suffix)
        if eb then eb:SetScript("OnTextChanged", function() Orction_UpdateDeposit() end) end
    end

    -- Cost / Earn row  ──────────────────────────────────────────────────────────
    local costLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    costLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 30, -230)
    costLabel:SetText("Cost:")

    OrctionDepositValue = OrctionAHPanel:CreateFontString("OrctionDepositValue", "ARTWORK", "GameFontNormalSmall")
    OrctionDepositValue:SetPoint("LEFT", costLabel, "RIGHT", 4, 0)
    OrctionDepositValue:SetText("--")

    OrctionTotalFeeValue = OrctionAHPanel:CreateFontString("OrctionTotalFeeValue", "ARTWORK", "GameFontNormalSmall")
    OrctionTotalFeeValue:SetPoint("LEFT", OrctionDepositValue, "RIGHT", 4, 0)
    OrctionTotalFeeValue:SetText("")

    local earnLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    earnLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 30, -210)
    earnLabel:SetText("Earn:")

    OrctionProfitValue = OrctionAHPanel:CreateFontString("OrctionProfitValue", "ARTWORK", "GameFontNormalSmall")
    OrctionProfitValue:SetPoint("LEFT", earnLabel, "RIGHT", 4, 0)
    OrctionProfitValue:SetText("")

    -- Create Auction button  ───────────────────────────────────────────────────
    OrctionCreateBtn = CreateFrame("Button", "OrctionCreateBtn", OrctionAHPanel, "UIPanelButtonTemplate")
    OrctionCreateBtn:SetWidth(150)
    OrctionCreateBtn:SetHeight(23)
    OrctionCreateBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 35, -248)
    OrctionCreateBtn:SetText("Create Auction")
    OrctionCreateBtn:SetScript("OnClick", Orction_CreateAuction)
    OrctionCreateBtn:Disable()

    -- Price history bar graph (positioned below the Create Auction button)
    orctionPriceBarGraph = OrctionBarGraph_Create(OrctionAHPanel, 196, 64)
    orctionPriceBarGraph.frame:SetPoint("TOPLEFT", OrctionCreateBtn, "BOTTOMLEFT", -12, -8)

    local watchlistToggleBtn = CreateFrame("Button", nil, OrctionAHPanel, "UIPanelButtonTemplate")
    watchlistToggleBtn:SetWidth(80)
    watchlistToggleBtn:SetHeight(23)
    watchlistToggleBtn:SetPoint("BOTTOMLEFT", OrctionAHPanel, "BOTTOMLEFT", 22, 66)
    watchlistToggleBtn:SetText("Watchlist")
    watchlistToggleBtn:SetScript("OnClick", function()
        local wl = getglobal("OrctionWatchlistFrame")
        if wl then
            if wl:IsShown() then wl:Hide() else wl:Show() ; Orction_RefreshWatchlist() end
        end
    end)

    local fullScanBtn = CreateFrame("Button", nil, OrctionAHPanel, "UIPanelButtonTemplate")
    fullScanBtn:SetWidth(100)
    fullScanBtn:SetHeight(23)
    fullScanBtn:SetPoint("LEFT", watchlistToggleBtn, "RIGHT", 4, 0)
    fullScanBtn:SetText("Category Scan")
    fullScanBtn:SetScript("OnClick", Orction_StartFullScan)

    local cancelScanBtn = CreateFrame("Button", nil, OrctionAHPanel, "UIPanelButtonTemplate")
    cancelScanBtn:SetWidth(78)
    cancelScanBtn:SetHeight(23)
    cancelScanBtn:SetPoint("BOTTOMRIGHT", OrctionAHPanel, "BOTTOMRIGHT", -8, 14)
    cancelScanBtn:SetText("Stop Scan")
    cancelScanBtn:SetScript("OnClick", function()
        if orctionScanMode or orctionSearchActive or orctionScanNextPending or orctionSearchRetry then
            orctionScanCancel = true
        end
    end)

    -- ── Watchlist overlay panel ───────────────────────────────────────────────
    local wlFrame = CreateFrame("Frame", "OrctionWatchlistFrame", OrctionAHPanel)
    wlFrame:SetWidth(195)
    wlFrame:SetHeight(280)
    wlFrame:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 15, -75)
    wlFrame:SetFrameLevel(OrctionAHPanel:GetFrameLevel() + 15)
    wlFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    wlFrame:SetBackdropColor(0.06, 0.06, 0.1, 1)
    wlFrame:Hide()

    local wlTitle = wlFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wlTitle:SetPoint("TOPLEFT", wlFrame, "TOPLEFT", 8, -6)
    wlTitle:SetText("Watchlist")

    local wlCloseBtn = CreateFrame("Button", nil, wlFrame, "UIPanelCloseButton")
    wlCloseBtn:SetWidth(20)
    wlCloseBtn:SetHeight(20)
    wlCloseBtn:SetPoint("TOPRIGHT", wlFrame, "TOPRIGHT", 2, 2)
    wlCloseBtn:SetScript("OnClick", function() wlFrame:Hide() end)

    OrctionWatchlistDetailsFrame = CreateFrame("Frame", "OrctionWatchlistDetailsFrame", wlFrame)
    OrctionWatchlistDetailsFrame:SetWidth(180)
    OrctionWatchlistDetailsFrame:SetHeight(70)
    OrctionWatchlistDetailsFrame:SetPoint("TOPLEFT", wlFrame, "TOPLEFT", 6, -24)
    OrctionWatchlistDetailsFrame:SetFrameLevel(wlFrame:GetFrameLevel() + 2)
    OrctionWatchlistDetailsFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    OrctionWatchlistDetailsFrame:SetBackdropColor(0.02, 0.02, 0.06, 0.95)
    OrctionWatchlistDetailsFrame:Hide()

    OrctionWatchlistDetailsName = OrctionWatchlistDetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    OrctionWatchlistDetailsName:SetPoint("TOPLEFT", OrctionWatchlistDetailsFrame, "TOPLEFT", 6, -6)
    OrctionWatchlistDetailsName:SetText("")

    OrctionWatchlistDetailsCat = OrctionWatchlistDetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    OrctionWatchlistDetailsCat:SetPoint("TOPLEFT", OrctionWatchlistDetailsName, "BOTTOMLEFT", 0, -4)
    OrctionWatchlistDetailsCat:SetText("")

    OrctionWatchlistDetailsSub = OrctionWatchlistDetailsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    OrctionWatchlistDetailsSub:SetPoint("TOPLEFT", OrctionWatchlistDetailsCat, "BOTTOMLEFT", 0, -2)
    OrctionWatchlistDetailsSub:SetText("")

    local wlDetailsCloseBtn = CreateFrame("Button", nil, OrctionWatchlistDetailsFrame, "UIPanelCloseButton")
    wlDetailsCloseBtn:SetWidth(18)
    wlDetailsCloseBtn:SetHeight(18)
    wlDetailsCloseBtn:SetPoint("TOPRIGHT", OrctionWatchlistDetailsFrame, "TOPRIGHT", 2, 2)
    wlDetailsCloseBtn:SetScript("OnClick", function() OrctionWatchlistDetailsFrame:Hide() end)

    -- FauxScrollFrame provides only the scrollbar widget — rows must NOT be its children
    -- (ScrollFrame clips its children; rows go in a plain sibling frame instead)
    OrctionWatchlistScroll = CreateFrame("ScrollFrame", "OrctionWatchlistScroll", wlFrame, "FauxScrollFrameTemplate")
    OrctionWatchlistScroll:SetWidth(167)
    OrctionWatchlistScroll:SetHeight(WL_MAX_ROWS * WL_ROW_H)
    OrctionWatchlistScroll:SetPoint("TOPLEFT", wlFrame, "TOPLEFT", 4, -22)
    OrctionWatchlistScroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(arg1, WL_ROW_H, Orction_RefreshWatchlist)
    end)

    local wlRowsFrame = CreateFrame("Frame", nil, wlFrame)
    wlRowsFrame:SetWidth(163)
    wlRowsFrame:SetHeight(WL_MAX_ROWS * WL_ROW_H)
    wlRowsFrame:SetPoint("TOPLEFT", wlFrame, "TOPLEFT", 4, -22)

    for i = 1, WL_MAX_ROWS do
        local row = CreateFrame("Frame", nil, wlRowsFrame)
        row:SetWidth(163)
        row:SetHeight(WL_ROW_H)
        row:SetPoint("TOPLEFT", wlRowsFrame, "TOPLEFT", 0, -(i - 1) * WL_ROW_H)

        local nameBtn = CreateFrame("Button", nil, row)
        nameBtn:SetWidth(118)
        nameBtn:SetHeight(WL_ROW_H)
        nameBtn:SetPoint("LEFT", row, "LEFT", 2, 0)
        nameBtn:SetScript("OnClick", function()
            if this._entry and this._entry.name then
                OrctionSearchBox:SetText(this._entry.name)
                Orction_SetSearchCategory(this._entry.classIndex or 0, this._entry.subIndex or 0)
                UIDropDownMenu_SetSelectedValue(OrctionCategoryDropDown, orctionSearchClassIndex)
                UIDropDownMenu_SetSelectedValue(OrctionSubcategoryDropDown, orctionSearchSubIndex)
                UIDropDownMenu_SetText(Orction_GetClassName(orctionSearchClassIndex), OrctionCategoryDropDown)
                UIDropDownMenu_SetText(Orction_GetSubClassName(orctionSearchClassIndex, orctionSearchSubIndex), OrctionSubcategoryDropDown)
                Orction_DoTextSearch()
            end
        end)

        local nameLabel = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLabel:SetAllPoints()
        nameLabel:SetJustifyH("LEFT")

        local detailsBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        detailsBtn:SetWidth(18)
        detailsBtn:SetHeight(WL_ROW_H - 2)
        detailsBtn:SetPoint("RIGHT", row, "RIGHT", -22, 0)
        detailsBtn:SetText("...")
        detailsBtn:SetScript("OnClick", function()
            if OrctionWatchlistDetailsFrame and this._entry then
                OrctionWatchlistDetailsName:SetText(this._entry.name or "")
                OrctionWatchlistDetailsCat:SetText("Category: " .. Orction_GetClassName(this._entry.classIndex or 0))
                OrctionWatchlistDetailsSub:SetText("Subcategory: " .. Orction_GetSubClassName(this._entry.classIndex or 0, this._entry.subIndex or 0))
                OrctionWatchlistDetailsFrame:Show()
            end
        end)

        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetWidth(18)
        removeBtn:SetHeight(WL_ROW_H - 2)
        removeBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        removeBtn:SetText("-")
        removeBtn:SetScript("OnClick", function()
            if this._index then
                Orction_RemoveFromWatchlist(this._index)
            end
        end)

        row.nameBtn   = nameBtn
        row.nameLabel = nameLabel
        row.detailsBtn = detailsBtn
        row.removeBtn = removeBtn
        row:Hide()
        orctionWatchlistRows[i] = row
    end

    -- Scan placeholder buttons
    local wlVendorBtn = CreateFrame("Button", nil, wlFrame, "UIPanelButtonTemplate")
    wlVendorBtn:SetWidth(56)
    wlVendorBtn:SetHeight(20)
    wlVendorBtn:SetPoint("BOTTOMLEFT", wlFrame, "BOTTOMLEFT", 6, 6)
    wlVendorBtn:SetText("Vendor")

    local wScanBtn = CreateFrame("Button", nil, wlFrame, "UIPanelButtonTemplate")
    wScanBtn:SetWidth(44)
    wScanBtn:SetHeight(20)
    wScanBtn:SetPoint("LEFT", wlVendorBtn, "RIGHT", 4, 0)
    wScanBtn:SetText("First")

    local wlFullBtn = CreateFrame("Button", nil, wlFrame, "UIPanelButtonTemplate")
    wlFullBtn:SetWidth(40)
    wlFullBtn:SetHeight(20)
    wlFullBtn:SetPoint("LEFT", wScanBtn, "RIGHT", 4, 0)
    wlFullBtn:SetText("Scan")
    wlFullBtn:SetScript("OnClick", Orction_StartScan)

    -- ── Results table (right panel, scrollable) ────────────────────────────
    -- Right panel footprint from dump: x=219, y=76, w=576, h=37 per row
    -- Column offsets are relative to the scroll child (x=0 = panel x=219)

    local COL_ICON_X = 6    -- item icon
    local COL_NAME_X = 34   -- item name
    local COL_WL_X   = 138  -- WL+ button
    local COL1_X     = 174  -- cost per item
    local COL2_X     = 278  -- total available
    local COL3_X     = 356  -- # auctions
    local COL4_X     = 420  -- buy button x
    local HEADER_Y   = -81
    local ROW_H      = 37
    local ROW_W      = 578

    local hName = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL_NAME_X, HEADER_Y)
    hName:SetText("Item")

    local hCost = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hCost:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL1_X, HEADER_Y)
    hCost:SetText("Cost / Item")

    local hQty = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hQty:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL2_X, HEADER_Y)
    hQty:SetText("Available")

    local hAuc = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAuc:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL3_X, HEADER_Y)
    hAuc:SetText("Auctions")

    local hBuy = OrctionAHPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hBuy:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219 + COL4_X, HEADER_Y)
    hBuy:SetText("Buy")

    local scrollFrame = CreateFrame("ScrollFrame", "OrctionResultScroll", OrctionAHPanel,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 219, -94)
    scrollFrame:SetWidth(ROW_W)
    scrollFrame:SetHeight(316)   -- ~8.5 visible rows

    local scrollChild = CreateFrame("Frame", "OrctionResultScrollChild", scrollFrame)
    scrollChild:SetWidth(ROW_W)
    scrollChild:SetHeight(ROW_H)   -- grows dynamically as rows are created
    scrollFrame:SetScrollChild(scrollChild)

    -- Status labels shown in place of the results table
    OrctionNoResultsText = scrollChild:CreateFontString("OrctionNoResultsText", "OVERLAY", "GameFontHighlight")
    OrctionNoResultsText:SetPoint("TOP", scrollChild, "TOP", 0, -60)
    OrctionNoResultsText:SetText("No items available for buyout.")
    OrctionNoResultsText:Hide()

    -- Searching/scanning progress — top-right of results area, same region as similar-results text
    OrctionSearchingText = OrctionAHPanel:CreateFontString("OrctionSearchingText", "OVERLAY", "GameFontHighlight")
    OrctionSearchingText:SetPoint("TOP", scrollFrame, "TOP", 140, 38)
    OrctionSearchingText:SetText("Searching...")
    OrctionSearchingText:Hide()

    OrctionSimilarResultsText = OrctionAHPanel:CreateFontString("OrctionSimilarResultsText", "OVERLAY", "GameFontHighlight")
    OrctionSimilarResultsText:SetPoint("BOTTOM", scrollFrame, "TOP", 180, 28)
    OrctionSimilarResultsText:SetText("|cFFFF9900 couldn't exact match everything |r")
    OrctionSimilarResultsText:Hide()

    -- ── Next Page button (bottom-right of results area) ────────────────────

    local nextPageBtn = CreateFrame("Button", "OrctionNextPageBtn", OrctionAHPanel, "UIPanelButtonTemplate")
    nextPageBtn:SetWidth(124)
    nextPageBtn:SetHeight(22)
    nextPageBtn:SetPoint("BOTTOMRIGHT", OrctionAHPanel, "BOTTOMRIGHT", -88, 14)
    nextPageBtn:SetText("More Results")
    nextPageBtn:Disable()
    nextPageBtn:SetScript("OnClick", Orction_FetchNextPages)

    -- ── Listen for item slot and search result changes ─────────────────────

    OrctionAHPanel:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    OrctionAHPanel:RegisterEvent("NEW_AUCTION_UPDATE")
    OrctionAHPanel:SetScript("OnEvent", Orction_AHPanel_OnEvent)

    -- Pace multi-page queries and time out if a page never returns data
    OrctionAHPanel:SetScript("OnUpdate", Orction_AHPanel_OnUpdate)
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
        if OrctionWatchlistFrame and OrctionWatchlistFrame:IsShown() then
            Orction_RefreshWatchlist()
        end
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

-- ── Events ────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            OrctionDB = OrctionDB or {}
            OrctionDB.stackCounts   = OrctionDB.stackCounts   or {}
            OrctionDB.vendorPrices  = OrctionDB.vendorPrices  or {}
            OrctionDB.vendorPricesById = OrctionDB.vendorPricesById or {}
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_NAME .. " initialised")
            Orction_HookVendorPriceTooltip()
            if not Orction_ErrorHandlerInstalled and seterrorhandler then
                Orction_ErrorHandlerInstalled = true
                local prevHandler = geterrorhandler and geterrorhandler() or nil
                seterrorhandler(function(err)
                    local msg = tostring(err or "")
                    local isOrction = string.find(msg, "Interface\\\\AddOns\\\\Orction") or
                                      string.find(msg, "Orction%.lua") or
                                      string.find(msg, "OrctionPostbox%.lua") or
                                      string.find(msg, "OrctionSettings%.lua") or
                                      string.find(msg, "OrctionTooltip%.lua")
                    if isOrction then
                        DEFAULT_CHAT_FRAME:AddMessage("Orction: " .. msg)
                        return
                    end
                    if prevHandler then
                        prevHandler(err)
                    end
                end)
            end
        elseif string.lower(arg1) == "blizzard_auctionui" then
            Orction_SetupAH()
            eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        AuctionFrameAuctions:Hide()
        if OrctionDB and OrctionDB.settings and OrctionDB.settings.autoOpenTab then
            Orction_OnTabClick(ORCTION_TAB_INDEX)
        end
    end
end)
