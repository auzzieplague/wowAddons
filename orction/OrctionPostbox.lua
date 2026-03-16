local postboxFrame = CreateFrame("Frame", "OrctionPostalFrame", UIParent)
postboxFrame:SetWidth(360)
postboxFrame:SetHeight(220)
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
titleText:SetText("Postal Settings")

local closeBtn = CreateFrame("Button", nil, postboxFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", postboxFrame, "TOPRIGHT", -3, -3)

SLASH_ORCTION_POSTAL1 = "/postal"
SlashCmdList["ORCTION_POSTAL"] = function()
    if postboxFrame:IsShown() then
        postboxFrame:Hide()
    else
        postboxFrame:Show()
    end
end

local postalEvents = CreateFrame("Frame")
postalEvents:RegisterEvent("MAIL_SHOW")
postalEvents:RegisterEvent("MAIL_INBOX_UPDATE")
postalEvents:RegisterEvent("INBOX_UPDATE")
postalEvents:SetScript("OnEvent", function()
    if event == "MAIL_SHOW" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Orction: user opened postbox")
        end
    end
end)

local function OrctionPostal_MailHasItemOrMoney(i)
    local _, _, _, _, money, COD, _, _, hasItem = GetInboxHeaderInfo(i)
    local hasMoney = (money and money > 0) or false
    if not hasItem and GetInboxItem then
        local itemName = GetInboxItem(i)
        if itemName then
            hasItem = true
        end
    end
    return hasItem or hasMoney, COD
end

local function OrctionPostal_PostEnabled()
    return OrctionDB and OrctionDB.settings and OrctionDB.settings.postEnabled == true
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
        if GetInboxItem then
            itemName = GetInboxItem(i)
        end
        -- Only delete mail we are confident is empty and already read.
        if not hasItem and not itemName and not hasMoney and (not COD or COD == 0) and wasRead == 1 then
            DeleteInboxItem(i)
        end
    end
end

local function OrctionPostal_UpdateButton(btn)
    if not btn then return end
    if not OrctionPostal_PostEnabled() then
        btn:Hide()
        return
    end
    if not btn:IsShown() then
        btn:Show()
    end
    if OrctionPostal_FindNextMail() then
        btn:SetText("Open Next")
        btn:Enable()
    else
        btn:SetText("Open All")
        btn:Disable()
    end
end

local function OrctionPostal_CreateButton()
    if OrctionPostalOpenBtn or not InboxFrame or not OrctionPostal_PostEnabled() then return end

    OrctionPostalOpenBtn = CreateFrame("Button", "OrctionPostalOpenBtn", InboxFrame, "UIPanelButtonTemplate")
    OrctionPostalOpenBtn:SetWidth(90)
    OrctionPostalOpenBtn:SetHeight(22)
    OrctionPostalOpenBtn:SetPoint("TOPLEFT", InboxFrame, "TOPLEFT", 75, -45)
    OrctionPostalOpenBtn:SetText("Open All")
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
    OrctionPostal_UpdateButton(OrctionPostalOpenBtn)
end

local origPostalOnEvent = postalEvents:GetScript("OnEvent")
local postalPoll = 0
local postalPollMax = 3.0
postalEvents:SetScript("OnEvent", function()
    if origPostalOnEvent then origPostalOnEvent() end
    if event == "MAIL_SHOW" then
        if CheckInbox then CheckInbox() end
        OrctionPostal_CreateButton()
        local delay = 0
        postalPoll = 0
        postalEvents:SetScript("OnUpdate", function()
            delay = delay + (arg1 or 0)
            postalPoll = postalPoll + (arg1 or 0)
            if delay >= 0.2 then
                OrctionPostal_UpdateButton(OrctionPostalOpenBtn)
                delay = 0
            end
            if postalPoll >= postalPollMax then
                postalEvents:SetScript("OnUpdate", nil)
            end
        end)
    elseif event == "MAIL_INBOX_UPDATE" or event == "INBOX_UPDATE" then
        OrctionPostal_DeleteEmptyMail()
        OrctionPostal_UpdateButton(OrctionPostalOpenBtn)
    end
end)

local postboxEventFrame = CreateFrame("Frame")
postboxEventFrame:RegisterEvent("ADDON_LOADED")
postboxEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        DEFAULT_CHAT_FRAME:AddMessage("OrctionPostbox: loaded")
    end
end)
