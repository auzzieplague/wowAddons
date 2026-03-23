-- OrctionBarGraph.lua
-- Reusable bar-graph widget.
--
-- Usage:
--   local graph = OrctionBarGraph_Create(parent, width, height)
--   graph.frame:SetPoint(...)
--   graph:SetSize(width, height)
--   graph:SetData(values, columnNames, style)   -- style: "positive"
--   graph:Hide() / graph:Show()
--
-- "positive" style colours bars red→yellow→green by fraction of max value.
-- Zero-value bars render as a dim 2-px stub so the slot remains visible.
-- Tooltip on hover shows the column name and the copper value formatted with
-- Orction_FormatMoney (falls back to a plain number if unavailable).

local BAR_GAP   = 2   -- px between bars
local TOP_PAD   = 4   -- px reserved above the tallest bar
local LABEL_PAD = 10  -- px reserved for labels when enabled

-- ── Colour helpers ────────────────────────────────────────────────────────

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- Returns r, g, b for the "positive" palette at pct ∈ [0, 1].
-- 0 → red   0.5 → yellow   1 → green
local function PositiveColor(pct)
    if pct <= 0.5 then
        local t = pct * 2
        return 1, Lerp(0, 1, t), 0
    else
        local t = (pct - 0.5) * 2
        return Lerp(1, 0, t), 1, 0
    end
end

-- ── Factory ───────────────────────────────────────────────────────────────

function OrctionBarGraph_Create(parent, width, height)
    -- Root frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:Hide()

    -- Dark background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.05, 0.05, 0.08, 0.85)

    -- Thin border line across the bottom
    local baseline = frame:CreateTexture(nil, "ARTWORK")
    baseline:SetHeight(1)
    baseline:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    baseline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    baseline:SetTexture("Interface\\Buttons\\WHITE8X8")
    baseline:SetVertexColor(0.4, 0.4, 0.4, 0.6)

    local barFrames = {}   -- reusable bar frame pool
    local labelFrames = {} -- label pool
    local activeCount = 0

    -- ── graph table (public API) ──────────────────────────────────────────
    local graph = { frame = frame }
    graph._width = width
    graph._height = height

    function graph:Show() frame:Show() end
    function graph:Hide() frame:Hide() end
    function graph:IsShown() return frame:IsShown() end
    function graph:SetSize(w, h)
        graph._width = w or graph._width
        graph._height = h or graph._height
        frame:SetWidth(graph._width)
        frame:SetHeight(graph._height)
    end

    -- counts: optional array of observation counts per bar.
    -- Bars with fewer than CONFIDENCE_THRESHOLD observations have their colour
    -- pulled toward the low end: colourPct = valuePct * min(1, count / threshold).
    local CONFIDENCE_THRESHOLD = 20

    function graph:SetData(values, columnNames, style, counts, options)
        -- Hide any previously shown bars
        for i = 1, activeCount do
            if barFrames[i] then barFrames[i]:Hide() end
            if labelFrames[i] then labelFrames[i]:Hide() end
        end

        local n = table.getn(values)
        if n == 0 then
            frame:Hide()
            return
        end

        -- Max value (used as 100 %)
        local maxVal = 0
        for i = 1, n do
            local v = values[i] or 0
            if v > maxVal then maxVal = v end
        end

        local showLabels = options and options.showLabels
        local todayIndex = options and options.todayIndex
        local factor = (options and options.confidenceFactor) or ORCTION_CONFIDENCE_FACTOR or 1
        if factor <= 0 then factor = 1 end
        local labelPad = showLabels and LABEL_PAD or 0
        local drawH = (graph._height or height) - TOP_PAD - labelPad
        if drawH < 4 then drawH = 4 end
        local totalW = (graph._width or width) - BAR_GAP * (n + 1)
        local barW   = math.max(1, math.floor(totalW / n))

        for i = 1, n do
            local val        = values[i] or 0
            local pct        = maxVal > 0 and (val / maxVal) or 0
            local n_obs      = (counts and counts[i]) or CONFIDENCE_THRESHOLD
            local confidence = math.min(1, n_obs / (CONFIDENCE_THRESHOLD * factor))
            local colorPct   = pct * confidence
            local bh         = math.max(2, math.floor(colorPct * drawH))

            -- Allocate bar frame on first use
            if not barFrames[i] then
                local b = CreateFrame("Frame", nil, frame)
                b:SetFrameLevel(frame:GetFrameLevel() + 1)
                b:EnableMouse(true)

                local tex = b:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints(b)
                tex:SetTexture("Interface\\Buttons\\WHITE8X8")
                b.tex = tex

                local bt = b:CreateTexture(nil, "OVERLAY")
                bt:SetTexture("Interface\\Buttons\\WHITE8X8")
                bt:SetHeight(1)
                bt:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                bt:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
                bt:SetVertexColor(1, 1, 1, 0.9)
                b.borderTop = bt

                local bb = b:CreateTexture(nil, "OVERLAY")
                bb:SetTexture("Interface\\Buttons\\WHITE8X8")
                bb:SetHeight(1)
                bb:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
                bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
                bb:SetVertexColor(1, 1, 1, 0.9)
                b.borderBottom = bb

                local bl = b:CreateTexture(nil, "OVERLAY")
                bl:SetTexture("Interface\\Buttons\\WHITE8X8")
                bl:SetWidth(1)
                bl:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                bl:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
                bl:SetVertexColor(1, 1, 1, 0.9)
                b.borderLeft = bl

                local br = b:CreateTexture(nil, "OVERLAY")
                br:SetTexture("Interface\\Buttons\\WHITE8X8")
                br:SetWidth(1)
                br:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
                br:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
                br:SetVertexColor(1, 1, 1, 0.9)
                b.borderRight = br

                b:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(this._colName or "?", 1, 1, 1)
                    local v = this._val or 0
                    if v > 0 then
                        local valStr = Orction_FormatMoney and Orction_FormatMoney(v) or tostring(v)
                        GameTooltip:AddLine(valStr, 1, 0.82, 0)
                        if this._count then
                            GameTooltip:AddLine(this._count .. " observations", 0.6, 0.6, 0.6)
                        end
                    else
                        GameTooltip:AddLine("No data", 0.6, 0.6, 0.6)
                    end
                    GameTooltip:Show()
                end)

                b:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                barFrames[i] = b
            end

            local b = barFrames[i]
            b._val     = val
            b._count   = counts and (counts[i] or 0) or nil
            b._colName = (columnNames and columnNames[i]) or ("Day " .. i)

            b:ClearAllPoints()
            b:SetWidth(barW)
            b:SetHeight(bh)
            b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
                BAR_GAP + (i - 1) * (barW + BAR_GAP), 1 + labelPad)

            if val == 0 then
                b.tex:SetVertexColor(0.25, 0.25, 0.25, 0.5)
            else
                local r, g, bl
                if style == "positive" then
                    r, g, bl = PositiveColor(colorPct)
                else
                    r, g, bl = 0.4, 0.6, 1.0
                end
                b.tex:SetVertexColor(r, g, bl, 0.85)
            end

            if todayIndex and i == todayIndex then
                b.borderTop:Show()
                b.borderBottom:Show()
                b.borderLeft:Show()
                b.borderRight:Show()
            else
                b.borderTop:Hide()
                b.borderBottom:Hide()
                b.borderLeft:Hide()
                b.borderRight:Hide()
            end

            b:Show()

            if showLabels then
                if not labelFrames[i] then
                    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    if lbl.SetFont then
                        lbl:SetFont("Fonts\\FRIZQT__.TTF", 8)
                    end
                    labelFrames[i] = lbl
                end
                local lbl = labelFrames[i]
                lbl:SetText(b._colName or "")
                if options and options.labelColors and options.labelColors[i] then
                    local c = options.labelColors[i]
                    lbl:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1)
                else
                    lbl:SetTextColor(0.8, 0.8, 0.8)
                end
                lbl:SetPoint("TOP", b, "BOTTOM", 0, -1)
                lbl:Show()
            end
        end

        activeCount = n
        frame:Show()
    end

    return graph
end
