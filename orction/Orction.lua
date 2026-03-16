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
local orctionPendingPost     = nil   -- { name, startBid, buyout, count, stacksLeft, totalStacks }
local orctionPendingDrop     = nil   -- { name, texture, count } while confirm dialog is open
local orctionVendorPrice     = nil   -- vendor sell price (copper) for the current search item
local orctionSellName        = nil   -- name of the item currently in the sell slot (for Create Auction)
local ORCTION_TOOLTIP_HOOKED = false
local orctionLastTooltipLink = nil
local orctionLastTooltipName = nil

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

    if OrctionSearchingText then OrctionSearchingText:Hide() end

    local hasResults = table.getn(groups) > 0
    if OrctionNoResultsText then
        if hasResults then OrctionNoResultsText:Hide() else OrctionNoResultsText:Show() end
    end

    -- Update vendor sell display
    if OrctionVendorSellValue then
        if orctionVendorPrice and orctionVendorPrice > 0 then
            OrctionVendorSellValue:SetText(CopperToString(orctionVendorPrice))
        else
            OrctionVendorSellValue:SetText("--")
        end
    end

    -- Auto-set prices from the cheapest listing
    if hasResults and OrctionCountBox then
        local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
        local price = groups[1].costPerItem * count
        MoneyInputFrame_SetCopper(OrctionBuyout, price)
    end

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
            if orctionVendorPrice and orctionVendorPrice > 0 and g.costPerItem < orctionVendorPrice then
                row.bg:SetTexture(0, 0.35, 0, 0.55)
                row.buyBtn:SetText("Snatch " .. tostring(g.firstCount))
            else
                if row.isEven then
                    row.bg:SetTexture(0.09, 0.09, 0.19, 0.5)
                else
                    row.bg:SetTexture(0, 0, 0.09, 0.3)
                end
                row.buyBtn:SetText("Buy " .. tostring(g.firstCount))
            end
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
        if name == orctionSearchName then
            -- Try to resolve vendor price from the first matching AH row
            if (not orctionVendorPrice or orctionVendorPrice == 0) and SellValues then
                local link = GetAuctionItemLink("list", i)
                if link then
                    local _, _, itemID = string.find(link, "item:(%d+)")
                    if itemID then
                        local price = SellValues["item:" .. itemID]
                        if price and price > 0 then
                            orctionVendorPrice = price
                            if OrctionDB and OrctionDB.vendorPrices then
                                OrctionDB.vendorPrices[name] = price
                            end
                        end
                    end
                end
            end
            if buyoutPrice and buyoutPrice > 0 and count and count > 0 then
                table.insert(orctionSearchResults, {
                    buyout      = buyoutPrice,
                    count       = count,
                    costPerItem = math.floor(buyoutPrice / count),
                })
            end
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
    orctionVendorPrice   = (OrctionDB and OrctionDB.vendorPrices and OrctionDB.vendorPrices[name]) or 0
    if OrctionVendorSellValue then OrctionVendorSellValue:SetText("--") end
    for i = 1, table.getn(orctionResultRows) do
        orctionResultRows[i].frame:Hide()
    end
    if OrctionSearchingText then OrctionSearchingText:Show() end
    if OrctionNoResultsText  then OrctionNoResultsText:Hide()  end
    QueryAuctionItems(name, nil, nil, nil, nil, nil, 0, nil, nil)
end

local function Orction_TryBuy()
    if not orctionBuyPending then return end
    local batch = GetNumAuctionItems("list")
    for i = 1, batch do
        local name, texture, count, quality, canUse, level,
              minBid, minIncrement, buyoutPrice = GetAuctionItemInfo("list", i)
        if buyoutPrice == orctionBuyPending.buyout then
            local boughtBuyout = buyoutPrice
            PlaceAuctionBid("list", i, buyoutPrice)
            orctionBuyPending = nil
            -- Remove the bought auction from local results and refresh the table
            for j = 1, table.getn(orctionSearchResults) do
                if orctionSearchResults[j].buyout == boughtBuyout then
                    table.remove(orctionSearchResults, j)
                    break
                end
            end
            Orction_DisplayResults()
            return
        end
    end
    orctionBuyPending = nil
    DEFAULT_CHAT_FRAME:AddMessage("Orction: Auction not found - it may have sold.")
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
    if OrctionDepositValue then OrctionDepositValue:SetText("--") end
    if OrctionDB then OrctionDB.stackCounts[name] = count end
    orctionSellName = name
    orctionVendorPrice = Orction_GetVendorPrice(name)
    Orction_StartSearch(name)
end

-- Called when the user drops an item onto the slot.
local function Orction_OnItemDrop()
    ClickAuctionSellItemButton()  -- cursor → sell slot
    local name, texture, count = GetAuctionSellItemInfo()
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

local function Orction_ClearItemSlot()
    StaticPopup_Hide("ORCTION_STACK_CONFIRM")
    orctionPendingDrop = nil
    if GetAuctionSellItemInfo() then
        ClickAuctionSellItemButton()
        ClearCursor()
    end
    OrctionItemTexture:Hide()
    OrctionItemNameText:SetText("")
    if OrctionDepositValue then OrctionDepositValue:SetText("--") end
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

local function Orction_CreateAuction()
    DEFAULT_CHAT_FRAME:AddMessage("Orction [CA]: pendingPost=" .. tostring(orctionPendingPost ~= nil))

    -- ── Pending post: stage or post depending on phase ─────────────────────
    if orctionPendingPost then
        local p = orctionPendingPost

        if p.staged then
            -- ── Phase 2: sell slot clear check + pick up staged slot + post ──
            if not Orction_SellSlotClear() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Previous auction processing — click again.")
                return   -- keep pendingPost, user retries
            end

            local _, tc = GetContainerItemInfo(p.tempBag, p.tempSlot)
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Post]: staged slot " .. p.tempBag .. "/" .. p.tempSlot .. " count=" .. tostring(tc))

            p.excludeSlots[p.tempBag * 1000 + p.tempSlot] = true
            PickupContainerItem(p.tempBag, p.tempSlot)
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Post]: cursor=" .. tostring(CursorHasItem()))
            if not CursorHasItem() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Staged slot empty — aborting.")
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            ClickAuctionSellItemButton()
            local _, _, fc = GetAuctionSellItemInfo()
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Post]: sell slot=" .. tostring(fc))
            if not fc then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Item not in sell slot.")
                if CursorHasItem() then ClearCursor() end
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            StartAuction(p.startBid, p.buyout, ORCTION_DURATION)
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Post]: StartAuction done count=" .. fc)

            p.stacksLeft = p.stacksLeft - 1
            p.staged     = false
            p.tempBag    = nil
            p.tempSlot   = nil

            if p.stacksLeft <= 0 then
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
            else
                local next = p.totalStacks - p.stacksLeft + 1
                OrctionCreateBtn:SetText("Stage " .. next .. "/" .. p.totalStacks)
            end

        else
            -- ── Phase 1: split count items → stage in empty bag slot ─────────
            local bag, slot, bagCount = Orction_FindBagSlot(p.name, p.count, p.excludeSlots)
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Stage]: FindBagSlot bag=" .. tostring(bag) .. " slot=" .. tostring(slot) .. " bagCount=" .. tostring(bagCount))
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
                DEFAULT_CHAT_FRAME:AddMessage("Orction [Stage]: Split(" .. bag .. "," .. slot .. "," .. p.count .. ")")
                SplitContainerItem(bag, slot, p.count)
            else
                DEFAULT_CHAT_FRAME:AddMessage("Orction [Stage]: Pickup(" .. bag .. "," .. slot .. ")")
                PickupContainerItem(bag, slot)
                -- Whole slot picked up — mark as emptied so stale data won't resurface it
                p.excludeSlots[bag * 1000 + slot] = true
            end

            DEFAULT_CHAT_FRAME:AddMessage("Orction [Stage]: cursor=" .. tostring(CursorHasItem()))
            if not CursorHasItem() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Failed to pick up items — aborting.")
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            PickupContainerItem(eb, es)
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Stage]: placed " .. eb .. "/" .. es .. " cursor=" .. tostring(CursorHasItem()))
            if CursorHasItem() then
                DEFAULT_CHAT_FRAME:AddMessage("Orction: Failed to place in staging slot — aborting.")
                ClearCursor()
                orctionPendingPost = nil
                OrctionCreateBtn:SetText("Create Auction")
                return
            end

            local _, sc = GetContainerItemInfo(eb, es)
            DEFAULT_CHAT_FRAME:AddMessage("Orction [Stage]: staged slot count=" .. tostring(sc))

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
    DEFAULT_CHAT_FRAME:AddMessage("Orction [CA]: " .. name .. " x" .. count .. " stacks=" .. stacks)

    local have = Orction_GetInventoryCount(name)
    local sn, _, sc = GetAuctionSellItemInfo()
    if sn == name then have = have + (sc or 0) end
    local need = count * stacks
    DEFAULT_CHAT_FRAME:AddMessage("Orction [CA]: have=" .. have .. " need=" .. need)
    if have < need then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: Need " .. need .. " " .. name .. ", have " .. have .. ".")
        return
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
        DEFAULT_CHAT_FRAME:AddMessage("Orction [CA]: parked at " .. eb .. "/" .. es .. " cursor=" .. tostring(CursorHasItem()))
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
    if not text or string.len(text) == 0 then return end
    orctionVendorPrice = Orction_GetVendorPrice(text)
    Orction_StartSearch(text)
end

local function Orction_BuildAHPanel()
    OrctionAHPanel = CreateFrame("Frame", "OrctionAHPanel", AuctionFrame)
    OrctionAHPanel:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 0, 0)
    OrctionAHPanel:SetWidth(AuctionFrame:GetWidth())
    OrctionAHPanel:SetHeight(AuctionFrame:GetHeight())
    OrctionAHPanel:SetFrameLevel(AuctionFrameAuctions:GetFrameLevel() + 20)

    OrctionAHPanel:Hide()

    -- ── Search bar (top, full width) ──────────────────────────────────────────
    OrctionSearchBox = CreateFrame("EditBox", "OrctionSearchBox", OrctionAHPanel, "InputBoxTemplate")
    OrctionSearchBox:SetWidth(600)
    OrctionSearchBox:SetHeight(20)
    OrctionSearchBox:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 60, -72)
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
    searchBtn:SetPoint("LEFT", OrctionSearchBox, "RIGHT", 4, 0)
    searchBtn:SetNormalTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchBtn:SetHighlightTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchBtn:GetHighlightTexture():SetBlendMode("ADD")
    searchBtn:SetScript("OnClick", Orction_DoTextSearch)

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

    --local slotBg = itemSlot:CreateTexture(nil, "BACKGROUND")
    --slotBg:SetTexture("Interface\\Buttons\\UI-Slot-Background")
    --slotBg:SetAllPoints()

    itemSlot:SetScript("OnReceiveDrag", Orction_OnItemDrop)
    itemSlot:SetScript("OnClick", function()
        if CursorHasItem() then
            Orction_OnItemDrop()
        else
            Orction_ClearItemSlot()
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
    OrctionItemNameText:SetText("< Drag an item here to post an Auction")

    -- Vendor Sell (below item slot)
    local vendorSellLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    vendorSellLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 27, -148)
    vendorSellLabel:SetText("Vendor Sell:")

    OrctionVendorSellValue = OrctionAHPanel:CreateFontString("OrctionVendorSellValue", "ARTWORK", "GameFontHighlightSmall")
    OrctionVendorSellValue:SetPoint("LEFT", vendorSellLabel, "RIGHT", 4, 0)
    OrctionVendorSellValue:SetText("--")

    -- Duration is fixed at 24h — sync Blizzard's button so CalculateAuctionDeposit is accurate
    AuctionsMediumAuctionButton:SetChecked(true)

    -- Count  ──────────────────────────────────────────────────────────────────
    local countLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    countLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -225)
    countLabel:SetText("Count")

    OrctionCountBox = CreateFrame("EditBox", "OrctionCountBox", OrctionAHPanel, "InputBoxTemplate")
    OrctionCountBox:SetWidth(40)
    OrctionCountBox:SetHeight(18)
    OrctionCountBox:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -240)
    OrctionCountBox:SetMaxLetters(4)
    OrctionCountBox:SetAutoFocus(false)
    OrctionCountBox:SetText("1")

    -- Stacks  ─────────────────────────────────────────────────────────────────
    local stacksLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    stacksLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -263)
    stacksLabel:SetText("Stacks")

    OrctionStacksBox = CreateFrame("EditBox", "OrctionStacksBox", OrctionAHPanel, "InputBoxTemplate")
    OrctionStacksBox:SetWidth(40)
    OrctionStacksBox:SetHeight(18)
    OrctionStacksBox:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 34, -278)
    OrctionStacksBox:SetMaxLetters(3)
    OrctionStacksBox:SetAutoFocus(false)
    OrctionStacksBox:SetText("1")

    local maxStacksBtn = CreateFrame("Button", nil, OrctionAHPanel, "UIPanelButtonTemplate")
    maxStacksBtn:SetWidth(40)
    maxStacksBtn:SetHeight(18)
    maxStacksBtn:SetPoint("LEFT", OrctionStacksBox, "RIGHT", 4, 0)
    maxStacksBtn:SetText("Max")
    maxStacksBtn:SetScript("OnClick", function()
        if not orctionSellName then return end
        local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
        OrctionStacksBox:SetText(tostring(Orction_GetMaxStacks(orctionSellName, count)))
    end)

    -- Buyout Price  ────────────────────────────────────────────────────────────
    local buyoutLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    buyoutLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 33, -305)
    buyoutLabel:SetText("Buyout Price")

    OrctionBuyout = CreateFrame("Frame", "OrctionBuyout", OrctionAHPanel, "MoneyInputFrameTemplate")
    OrctionBuyout:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 33, -320)
    ResizeMoneyInputFrame("OrctionBuyout")

    -- Deposit  ────────────────────────────────────────────────────────────────
    local depositLabel = OrctionAHPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    depositLabel:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 30, -353)
    depositLabel:SetText("Deposit:")

    OrctionDepositValue = OrctionAHPanel:CreateFontString("OrctionDepositValue", "ARTWORK", "GameFontHighlightSmall")
    OrctionDepositValue:SetPoint("LEFT", depositLabel, "RIGHT", 6, 0)
    OrctionDepositValue:SetText("--")

    -- Create Auction button  ───────────────────────────────────────────────────
    OrctionCreateBtn = CreateFrame("Button", "OrctionCreateBtn", OrctionAHPanel, "UIPanelButtonTemplate")
    OrctionCreateBtn:SetWidth(191)
    OrctionCreateBtn:SetHeight(20)
    OrctionCreateBtn:SetPoint("TOPLEFT", OrctionAHPanel, "TOPLEFT", 18, -378)
    OrctionCreateBtn:SetText("Create Auction")
    OrctionCreateBtn:SetScript("OnClick", Orction_CreateAuction)

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
    local ROW_W    = 578   -- 543 + 50

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
                    local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
                    local price = row.costPerItem * count
                    MoneyInputFrame_SetCopper(OrctionBuyout, price)
                end
            end)
        end)

        rowBtn:SetScript("OnClick", function()
            local row = orctionResultRows[idx]
            if row and row.costPerItem then
                local count = math.max(1, tonumber(OrctionCountBox:GetText()) or 1)
                local price = row.costPerItem * count
                MoneyInputFrame_SetCopper(OrctionStartBid, price)
                MoneyInputFrame_SetCopper(OrctionBuyout,   price)
            end
        end)

        orctionResultRows[i] = { frame = rowBtn, cost = costFS, qty = qtyFS,
                                  auctions = aucFS, buyBtn = buyBtn, bg = bg,
                                  isEven = (math.mod(i, 2) == 0),
                                  costPerItem = nil, firstBuyout = nil }
        rowBtn:Hide()
    end

    -- Status labels shown in place of the results table
    OrctionSearchingText = scrollChild:CreateFontString("OrctionSearchingText", "OVERLAY", "GameFontHighlight")
    OrctionSearchingText:SetPoint("TOP", scrollChild, "TOP", 0, -60)
    OrctionSearchingText:SetText("Searching...")
    OrctionSearchingText:Hide()

    OrctionNoResultsText = scrollChild:CreateFontString("OrctionNoResultsText", "OVERLAY", "GameFontHighlight")
    OrctionNoResultsText:SetPoint("TOP", scrollChild, "TOP", 0, -60)
    OrctionNoResultsText:SetText("No items available for buyout.")
    OrctionNoResultsText:Hide()

    -- ── Listen for item slot and search result changes ─────────────────────

    OrctionAHPanel:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    OrctionAHPanel:SetScript("OnEvent", function()
        if event == "AUCTION_ITEM_LIST_UPDATE" then
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
            DEFAULT_CHAT_FRAME:AddMessage(ADDON_NAME .. " initialised")
            Orction_HookVendorPriceTooltip()
        elseif string.lower(arg1) == "blizzard_auctionui" then
            Orction_SetupAH()
            eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        AuctionFrameAuctions:Hide()
    end
end)
