local postboxFrame = CreateFrame("Frame")
postboxFrame:RegisterEvent("ADDON_LOADED")
postboxFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Orction" then
        postboxFrame:UnregisterEvent("ADDON_LOADED")
        local elapsed = 0
        postboxFrame:SetScript("OnUpdate", function()
            elapsed = elapsed + (arg1 or 0)
            if elapsed >= 0.1 then
                if ChatFrame1 then
                    ChatFrame1:AddMessage("Orction: Postbox module loaded")
                end
                if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME ~= ChatFrame1 then
                    DEFAULT_CHAT_FRAME:AddMessage("Orction: Postbox module loaded")
                end
                postboxFrame:SetScript("OnUpdate", nil)
            end
        end)
    end
end)
