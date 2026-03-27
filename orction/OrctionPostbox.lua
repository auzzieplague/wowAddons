-- OrctionPostbox.lua
-- Adds "Open Next" and "Open All at Once" buttons to the mailbox.
-- "Open All at Once" loops through all mail with items/money,
-- waiting for MAIL_INBOX_UPDATE between each open and retrying on timeout.

-- ── Settings globals (defaults; overwritten by OrctionSettings ADDON_LOADED) ─
ORCTION_MAIL_OPEN_DELAY   = 0.5   -- seconds between successive opens
ORCTION_MAIL_OPEN_RETRIES = 2     -- max retries per mail on timeout

-- ── Open-all loop state ───────────────────────────────────────────────────
local openAllActive        = false  -- loop is running
local openAllWaiting       = false  -- waiting for MAIL_INBOX_UPDATE (or timeout)
local openAllWaitElapsed   = 0      -- seconds since last open action
local openAllRetryCount    = 0      -- retries fired for the current mail
local openAllDelayPending  = false  -- waiting inter-open delay before next open
local openAllDelayElapsed  = 0      -- seconds into the inter-open delay
local openAllOpened        = 0      -- total mails opened this session

-- ── Helpers ───────────────────────────────────────────────────────────────

local function OrctionPostal_PostEnabled()
    return OrctionDB and OrctionDB.settings and OrctionDB.settings.postEnabled == true
end

local function OrctionPostal_MailHasItemOrMoney(i)
    local _, _, _, _, money, COD, _, _, hasItem = GetInboxHeaderInfo(i)
    local hasMoney = (money and money > 0) or false
    if not hasItem and GetInboxItem then
        local itemName = GetInboxItem(i)
        if itemName then hasItem = true end
    end
    return hasItem or hasMoney, COD
end

local function OrctionPostal_FindInboxItemButton(i)
    local direct = _G["MailItem" .. i .. "Button"]
    if direct then return direct end
    local row = _G["InboxFrameItem" .. i] or _G["MailItem" .. i]
    if row then
        return row.ItemButton or row.Button or _G[row:GetName() .. "ItemButton"] or _G[row:GetName() .. "Button"]
    end
    return _G["InboxFrameItem" .. i .. "ItemButton"] or _G["InboxFrameItem" .. i .. "Button"] or
           _G["MailItem" .. i .. "ItemButton"] or _G["MailItem" .. i .. "Button"]
end

local function OrctionPostal_FindInboxRow(i)
    return _G["MailItem" .. i] or _G["InboxFrameItem" .. i]
end

local function OrctionPostal_FindExpireText(i)
    local row = OrctionPostal_FindInboxRow(i)
    if row then
        return row.ExpireTime or _G[row:GetName() .. "ExpireTime"]
    end
    return _G["MailItem" .. i .. "ExpireTime"] or _G["InboxFrameItem" .. i .. "ExpireTime"]
end

local function OrctionPostal_UpdateInboxCounts()
    local num = GetInboxNumItems()
    local perPage = INBOXITEMS_TO_DISPLAY or 7
    local page = (InboxFrame and InboxFrame.pageNum) or 1
    local startIndex = (page - 1) * perPage
    for i = 1, perPage do
        local mailIndex = startIndex + i
        local row = OrctionPostal_FindInboxRow(i)
        local btn = OrctionPostal_FindInboxItemButton(i)
        if btn then
            if not btn.orctionCountText then
                btn.orctionCountText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.orctionCountText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            end
            local _, _, count = GetInboxItem(mailIndex)
            if mailIndex <= num and count and count > 1 then
                btn.orctionCountText:SetText(count)
                btn.orctionCountText:Show()
            else
                btn.orctionCountText:Hide()
            end
        end
        if row then
            if not row.orctionMoneyText then
                local anchor = OrctionPostal_FindExpireText(i) or row
                row.orctionMoneyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.orctionMoneyText:SetJustifyH("RIGHT")
                row.orctionMoneyText:SetWidth(120)
                row.orctionMoneyText:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
            end
            local _, _, _, _, money = GetInboxHeaderInfo(mailIndex)
            if mailIndex <= num and money and money > 0 and Orction_FormatMoney then
                row.orctionMoneyText:SetText(Orction_FormatMoney(money))
                row.orctionMoneyText:Show()
            else
                row.orctionMoneyText:Hide()
            end
        end
    end
end

local function OrctionPostal_FindNextMail()
    local num = GetInboxNumItems()
    for i = 1, num do
        local hasStuff, COD = OrctionPostal_MailHasItemOrMoney(i)
        if hasStuff and (not COD or COD == 0) then
            return i
        end
    end
    return nil
end

local function OrctionPostal_DeleteEmptyMail()
    local num = GetInboxNumItems()
    for i = num, 1, -1 do
        local _, _, _, _, money, COD, _, _, hasItem, wasRead = GetInboxHeaderInfo(i)
        local hasMoney = (money and money > 0) or false
        local itemName = nil
        if GetInboxItem then itemName = GetInboxItem(i) end
        if not hasItem and not itemName and not hasMoney and (not COD or COD == 0) and wasRead == 1 then
            DeleteInboxItem(i)
        end
    end
end

local function OrctionPostal_UpdateButtons()
    local hasNext = OrctionPostal_FindNextMail() ~= nil
    if OrctionPostalOpenBtn then
        if not OrctionPostal_PostEnabled() then
            OrctionPostalOpenBtn:Hide()
        else
            OrctionPostalOpenBtn:Show()
            if hasNext then
                OrctionPostalOpenBtn:SetText("Open Next")
                OrctionPostalOpenBtn:Enable()
            else
                OrctionPostalOpenBtn:SetText("Open Next")
                OrctionPostalOpenBtn:Disable()
            end
        end
    end
    if OrctionPostalOpenAllBtn then
        if not OrctionPostal_PostEnabled() then
            OrctionPostalOpenAllBtn:Hide()
        else
            OrctionPostalOpenAllBtn:Show()
            if openAllActive then
                OrctionPostalOpenAllBtn:SetText("Stop")
                OrctionPostalOpenAllBtn:Enable()
            elseif hasNext then
                OrctionPostalOpenAllBtn:SetText("Open All")
                OrctionPostalOpenAllBtn:Enable()
            else
                OrctionPostalOpenAllBtn:SetText("Open All")
                OrctionPostalOpenAllBtn:Disable()
            end
        end
    end
    OrctionPostal_UpdateInboxCounts()
end

-- ── Open-all loop ─────────────────────────────────────────────────────────

local function OrctionPostal_OpenAllStop(reason)
    openAllActive       = false
    openAllWaiting      = false
    openAllDelayPending = false
    openAllRetryCount   = 0
    openAllWaitElapsed  = 0
    openAllDelayElapsed = 0
    if reason then
        DEFAULT_CHAT_FRAME:AddMessage("Orction: " .. reason)
    end
    OrctionPostal_UpdateButtons()
end

local function OrctionPostal_OpenAllNext()
    if not openAllActive then return end
    local idx = OrctionPostal_FindNextMail()
    if not idx then
        OrctionPostal_OpenAllStop("all mail opened (" .. openAllOpened .. " total)")
        if MiniMapMailFrame and MiniMapMailFrame.Hide and GetInboxNumItems and GetInboxNumItems() == 0 then
            MiniMapMailFrame:Hide()
        end
        return
    end
    TakeInboxItem(idx)
    TakeInboxMoney(idx)
    openAllWaiting     = true
    openAllWaitElapsed = 0
end

local function OrctionPostal_StartOpenAll()
    if openAllActive then
        -- Toggle: stop if already running
        OrctionPostal_OpenAllStop("open-all stopped by user")
        return
    end
    if not OrctionPostal_FindNextMail() then return end
    openAllActive       = true
    openAllWaiting      = false
    openAllDelayPending = false
    openAllRetryCount   = 0
    openAllOpened       = 0
    OrctionPostal_UpdateButtons()
    OrctionPostal_OpenAllNext()
end

-- ── Timer frame (persistent OnUpdate for open-all timing) ─────────────────

local openAllTimer = CreateFrame("Frame")
openAllTimer:SetScript("OnUpdate", function()
    if openAllDelayPending then
        openAllDelayElapsed = openAllDelayElapsed + arg1
        if openAllDelayElapsed >= ORCTION_MAIL_OPEN_DELAY then
            openAllDelayPending = false
            openAllDelayElapsed = 0
            OrctionPostal_OpenAllNext()
        end
    elseif openAllWaiting then
        openAllWaitElapsed = openAllWaitElapsed + arg1
        if openAllWaitElapsed >= 3.0 then
            -- Timeout waiting for MAIL_INBOX_UPDATE
            if openAllRetryCount < ORCTION_MAIL_OPEN_RETRIES then
                openAllRetryCount = openAllRetryCount + 1
                openAllWaiting    = false
                openAllWaitElapsed = 0
                DEFAULT_CHAT_FRAME:AddMessage(
                    "Orction: mail open timed out, retrying (" ..
                    openAllRetryCount .. "/" .. ORCTION_MAIL_OPEN_RETRIES .. ")")
                OrctionPostal_OpenAllNext()
            else
                OrctionPostal_OpenAllStop(
                    "mail open failed after " .. ORCTION_MAIL_OPEN_RETRIES .. " retries, stopping")
            end
        end
    end
end)

-- ── Button creation ───────────────────────────────────────────────────────

local function OrctionPostal_CreateButtons()
    if OrctionPostalOpenBtn then return end
    if not InboxFrame or not OrctionPostal_PostEnabled() then return end

    OrctionPostalOpenBtn = CreateFrame("Button", "OrctionPostalOpenBtn", InboxFrame, "UIPanelButtonTemplate")
    OrctionPostalOpenBtn:SetWidth(90)
    OrctionPostalOpenBtn:SetHeight(22)
    OrctionPostalOpenBtn:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 75, -45)
    OrctionPostalOpenBtn:SetText("Open Next")
    OrctionPostalOpenBtn:SetScript("OnClick", function()
        local idx = OrctionPostal_FindNextMail()
        if idx then
            TakeInboxItem(idx)
            TakeInboxMoney(idx)
            OrctionPostal_DeleteEmptyMail()
        else
            if CheckInbox then CheckInbox() end
        end
    end)

    OrctionPostalOpenAllBtn = CreateFrame("Button", "OrctionPostalOpenAllBtn", InboxFrame, "UIPanelButtonTemplate")
    OrctionPostalOpenAllBtn:SetWidth(90)
    OrctionPostalOpenAllBtn:SetHeight(22)
    OrctionPostalOpenAllBtn:SetPoint("LEFT", OrctionPostalOpenBtn, "RIGHT", 4, 0)
    OrctionPostalOpenAllBtn:SetText("Open All")
    OrctionPostalOpenAllBtn:SetScript("OnClick", OrctionPostal_StartOpenAll)

    OrctionPostal_UpdateButtons()
end

-- ── Events ────────────────────────────────────────────────────────────────

local postalEvents = CreateFrame("Frame")
postalEvents:RegisterEvent("MAIL_SHOW")
postalEvents:RegisterEvent("MAIL_CLOSED")
postalEvents:RegisterEvent("MAIL_INBOX_UPDATE")
postalEvents:RegisterEvent("INBOX_UPDATE")

if InboxFrame_Update then
    local orig_InboxFrame_Update = InboxFrame_Update
    InboxFrame_Update = function(...)
        local ret = orig_InboxFrame_Update(unpack(arg))
        OrctionPostal_UpdateInboxCounts()
        return ret
    end
end

local postalPoll    = 0
local postalPollMax = 3.0

postalEvents:SetScript("OnEvent", function()
    if event == "MAIL_SHOW" then
        if CheckInbox then CheckInbox() end
        OrctionPostal_CreateButtons()
        -- Poll briefly to update button state after the inbox loads
        postalPoll = 0
        postalEvents:SetScript("OnUpdate", function()
            postalPoll = postalPoll + (arg1 or 0)
            OrctionPostal_UpdateButtons()
            if postalPoll >= postalPollMax then
                postalEvents:SetScript("OnUpdate", nil)
            end
        end)

    elseif event == "MAIL_CLOSED" then
        if openAllActive then
            OrctionPostal_OpenAllStop("mailbox closed, stopping open-all")
        end

    elseif event == "MAIL_INBOX_UPDATE" or event == "INBOX_UPDATE" then
        OrctionPostal_DeleteEmptyMail()
        if openAllWaiting then
            openAllWaiting    = false
            openAllRetryCount = 0
            openAllOpened     = openAllOpened + 1
            -- Schedule next open after the configured inter-open delay
            openAllDelayPending = true
            openAllDelayElapsed = 0
        end
        if not OrctionPostal_FindNextMail() and MiniMapMailFrame and MiniMapMailFrame.Hide then
            MiniMapMailFrame:Hide()
        end
        OrctionPostal_UpdateButtons()
    end
end)

-- ── Settings window (stub, kept for /postal command) ─────────────────────

local postboxFrame = CreateFrame("Frame", "OrctionPostalFrame", UIParent)
postboxFrame:SetWidth(360)
postboxFrame:SetHeight(120)
postboxFrame:SetPoint("CENTER", UIParent, "CENTER")
postboxFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
postboxFrame:SetMovable(true)
postboxFrame:EnableMouse(true)
postboxFrame:RegisterForDrag("LeftButton")
postboxFrame:SetScript("OnDragStart", function() this:StartMoving() end)
postboxFrame:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
postboxFrame:Hide()

local titleBar = postboxFrame:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBar:SetWidth(256)
titleBar:SetHeight(64)
titleBar:SetPoint("TOP", postboxFrame, "TOP", 0, 12)

local titleText = postboxFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
titleText:SetPoint("TOP", postboxFrame, "TOP", 0, -14)
titleText:SetText("Orction: use /orction for settings")

local closeBtn = CreateFrame("Button", nil, postboxFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", postboxFrame, "TOPRIGHT", -3, -3)

SLASH_ORCTION_POSTAL1 = "/postal"
SlashCmdList["ORCTION_POSTAL"] = function()
    if postboxFrame:IsShown() then postboxFrame:Hide() else postboxFrame:Show() end
end

local postboxEventFrame = CreateFrame("Frame")
postboxEventFrame:RegisterEvent("ADDON_LOADED")
postboxEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        DEFAULT_CHAT_FRAME:AddMessage("OrctionPostbox: loaded")
    end
end)
