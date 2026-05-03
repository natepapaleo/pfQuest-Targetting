local MACRO_NAME      = "pfQTarget"
local MACRO_ICON      = 1
local BUTTON_SIZE     = 25
local MOB_PLACEHOLDER = "Interface\\Icons\\INV_Sword_04"

local fmt = string.format
local tinsert, tremove = table.insert, table.remove

local pendingMacroUpdate = false
local announced          = false
local activeNames        = {}
local nameSet            = {}
local nearbyUnits        = {}
local lastSoundTime      = 0

local killPattern
if QUEST_MONSTERS_KILLED then
    killPattern = "^" .. QUEST_MONSTERS_KILLED
        :gsub("%%s", "(.+)")
        :gsub("%%d", "%%d+") .. "$"
end

local function ParseObjectiveName(text)
    if killPattern then
        local n = text:match(killPattern)
        if n then return n end
    end
    return text:match("^(.+): %d+/%d+$")
end

-- ─── Settings ────────────────────────────────────────────────────────────────

local DEFAULTS = {
    showPortraits       = true,
    autoTarget          = true,
    autoTargetInCombat  = false,
    autoMark            = true,
    markOnMouseover     = true,
    markIndex           = 8,
    soundAlert          = true,
    includeDropQuests   = true,
    enableMacro         = true,
    frameLock           = false,
    bgOpacity           = 0.88,
    buttonsPerRow       = 4,
    minimapButton       = true,
    scale               = 1.0,
}

local function DB()
    pfQuestTargetingDB = pfQuestTargetingDB or {}
    return pfQuestTargetingDB
end

local function GetSetting(key)
    local v = DB()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function SetSetting(key, value)
    DB()[key] = value
end

-- ─── Quest log ───────────────────────────────────────────────────────────────

local function AddName(names, seen, name)
    if name and name ~= "" and not seen[name] then
        seen[name] = true
        tinsert(names, name)
    end
end

local function GetDBUnitName(unitID)
    if not pfDB or not pfDB["units"] then return nil end
    return (pfDB["units"]["enUS-epoch"] and pfDB["units"]["enUS-epoch"][unitID])
        or (pfDB["units"]["enUS"]        and pfDB["units"]["enUS"][unitID])
end

local titleToID = nil
local function GetQuestIDByTitle(title)
    if not pfDB or not pfDB["quests"] then return nil end
    if not titleToID then
        titleToID = {}
        for _, key in ipairs({"enUS-epoch", "enUS", "enUS-tbc"}) do
            local db = pfDB["quests"][key]
            if db then
                for qid, qdata in pairs(db) do
                    if qdata["T"] and not titleToID[qdata["T"]] then
                        titleToID[qdata["T"]] = qid
                    end
                end
            end
        end
    end
    return titleToID[title]
end

local function GetQuestIDForIndex(i)
    if GetQuestLink then
        local link = GetQuestLink(i)
        if link then
            local id = link:match("|Hquest:(%d+):")
            if id then return tonumber(id) end
        end
    end
    local title = GetQuestLogTitle(i)
    return title and GetQuestIDByTitle(title)
end

local function GetDBKillUnits(questID)
    if not pfDB or not pfDB["quests"] then return nil end
    local qdata = (pfDB["quests"]["data-epoch"] and pfDB["quests"]["data-epoch"][questID])
               or (pfDB["quests"]["data"]        and pfDB["quests"]["data"][questID])
    if not qdata or not qdata["obj"] then return nil end

    -- Kill quest: obj.U is an array {unitID, unitID, ...}
    if qdata["obj"]["U"] then
        local unitIDs = {}
        for _, uid in ipairs(qdata["obj"]["U"]) do tinsert(unitIDs, uid) end
        if #unitIDs > 0 then return unitIDs end
    end

    -- Drop quest: obj.I is an array of item IDs
    -- items.data[itemID].U is {[unitID]=dropCount} — keys are unit IDs
    local rawItems = qdata["obj"]["I"]
    if rawItems and pfDB["items"] then
        local unitIDs, seen = {}, {}
        for _, itemID in ipairs(rawItems) do
            for _, idbKey in ipairs({"data-epoch", "data"}) do
                local idb = pfDB["items"][idbKey]
                local idata = idb and idb[itemID]
                if idata and idata["U"] then
                    for uid in pairs(idata["U"]) do
                        if type(uid) == "number" and not seen[uid] then
                            seen[uid] = true; tinsert(unitIDs, uid)
                        end
                    end
                end
            end
        end
        if #unitIDs > 0 then return unitIDs end
    end

    return nil
end

local function GetKillObjectiveNames()
    local names, seen = {}, {}
    local wantDrops = GetSetting("includeDropQuests")
    for i = 1, GetNumQuestLogEntries() do
        SelectQuestLogEntry(i)
        local numObj = GetNumQuestLeaderBoards()
        if numObj > 0 then
            local hasUnfinishedItem = false
            for j = 1, numObj do
                local text, objType, finished = GetQuestLogLeaderBoard(j)
                if not finished then
                    if objType == "monster" and text then
                        AddName(names, seen, ParseObjectiveName(text))
                    elseif objType == "item" then
                        hasUnfinishedItem = true
                    end
                end
            end
            if hasUnfinishedItem and wantDrops then
                local questID = GetQuestIDForIndex(i)
                if questID then
                    local unitIDs = GetDBKillUnits(questID)
                    if unitIDs then
                        for _, uid in ipairs(unitIDs) do
                            AddName(names, seen, GetDBUnitName(uid))
                        end
                    end
                end
            end
        end
    end
    return names
end

-- ─── Macro ───────────────────────────────────────────────────────────────────

local function UpdateMacro()
    if not GetSetting("enableMacro") then return end
    if InCombatLockdown() then pendingMacroUpdate = true; return end
    pendingMacroUpdate = false

    if not GetMacroInfo(MACRO_NAME) then
        if GetNumMacros() >= 119 then return end
        CreateMacro(MACRO_NAME, MACRO_ICON, "")
    end

    if #activeNames == 0 then
        EditMacro(MACRO_NAME, MACRO_NAME, nil, "// No active kill objectives")
        return
    end

    local lines = {}
    for _, name in ipairs(activeNames) do tinsert(lines, "/targetexact " .. name) end
    local content = table.concat(lines, "\n")
    while #content > 230 and #lines > 1 do tremove(lines, 1); content = table.concat(lines, "\n") end
    EditMacro(MACRO_NAME, MACRO_NAME, nil, content .. "\n/targetlasttarget [dead]")

    if not announced then
        announced = true
        print(fmt("|cFF00FF00pfQuestTargeting:|r Macro '%s' ready — drag it to your action bar.", MACRO_NAME))
    end
end

-- ─── Target window ───────────────────────────────────────────────────────────

local targetFrame
local optionsFrame
local minimapBtn
local lockBtn
local buttons = {}

local function PositionButton(btn, index)
    btn:ClearAllPoints()
    local bpr = GetSetting("buttonsPerRow")
    local col = (index - 1) % bpr
    local row = math.floor((index - 1) / bpr)
    btn:SetPoint("TOPLEFT", targetFrame, "TOPLEFT",
        5 + col * (BUTTON_SIZE + 2),
        -20 - row * (BUTTON_SIZE + 2))
end

local function ResizeFrame()
    local visible = 0
    for _, btn in ipairs(buttons) do if btn:IsShown() then visible = visible + 1 end end
    if visible == 0 then targetFrame:SetSize(96, 20); return end
    local bpr = GetSetting("buttonsPerRow")
    local cols = math.min(visible, bpr)
    local rows = math.ceil(visible / bpr)
    targetFrame:SetSize(
        math.max(96, cols * (BUTTON_SIZE + 2) + 8),
        20 + rows * (BUTTON_SIZE + 2) + 6
    )
end

local function UpdateButtonVisuals()
    for _, btn in ipairs(buttons) do
        if btn:IsShown() then
            if nearbyUnits[btn.mobName] then
                btn:SetAlpha(1); btn.rangeGlow:Show()
            else
                btn:SetAlpha(0.5); btn.rangeGlow:Hide()
            end
        end
    end
end

local function RefreshPortrait(btn)
    local unitToken = nearbyUnits[btn.mobName]
    if GetSetting("showPortraits") and unitToken and UnitExists(unitToken) and UnitName(unitToken) == btn.mobName then
        SetPortraitTexture(btn.icon, unitToken)
    else
        btn.icon:SetTexture(MOB_PLACEHOLDER)
    end
end

local function ShouldShowFrame()
    return #activeNames > 0
end

local function RebuildButtons()
    if InCombatLockdown() then return end
    targetFrame:SetScale(GetSetting("scale"))

    for i = #activeNames + 1, #buttons do buttons[i]:Hide() end

    for i, name in ipairs(activeNames) do
        local btn = buttons[i]
        if not btn then
            btn = CreateFrame("Button", fmt("pfQTBtn%d", i), targetFrame, "SecureActionButtonTemplate")
            btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
            btn:SetAttribute("type", "macro")
            if btn.RegisterForClicks then btn:RegisterForClicks("AnyUp", "AnyDown") end

            btn.icon = btn:CreateTexture(nil, "BACKGROUND")
            btn.icon:SetAllPoints(true)
            btn.icon:SetTexture(MOB_PLACEHOLDER)

            btn.rangeGlow = btn:CreateTexture(nil, "OVERLAY")
            btn.rangeGlow:SetAllPoints(true)
            btn.rangeGlow:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            btn.rangeGlow:SetBlendMode("ADD")
            btn.rangeGlow:SetVertexColor(0, 1, 0.2, 0.9)
            btn.rangeGlow:Hide()

            local ht = btn:CreateTexture(nil, "HIGHLIGHT")
            ht:SetAllPoints(true)
            ht:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            ht:SetBlendMode("ADD")

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, 0)
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.mobName, 1, 0.3, 0.3)
                GameTooltip:AddLine(
                    nearbyUnits[self.mobName] and "In range — click to target" or "Not nearby",
                    nearbyUnits[self.mobName] and 0   or 0.6,
                    nearbyUnits[self.mobName] and 1   or 0.6,
                    nearbyUnits[self.mobName] and 0   or 0.6)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tinsert(buttons, btn)
        end

        btn.mobName = name
        btn:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. name)
        PositionButton(btn, i)
        RefreshPortrait(btn)
        btn:Show()
    end

    UpdateButtonVisuals()
    ResizeFrame()
    targetFrame[ShouldShowFrame() and "Show" or "Hide"](targetFrame)
end

-- ─── Options helpers ──────────────────────────────────────────────────────────

local function MakeBackdrop(f, r, g, b, a)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(r or 0.08, g or 0.08, b or 0.08, a or 0.95)
        f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end
end

local function SectionLabel(parent, text, yOff)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    sep:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    sep:SetPoint("TOPLEFT",  parent, "TOPLEFT",  10, yOff)
    sep:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, yOff)
    sep:SetHeight(1)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOff - 4)
    lbl:SetTextColor(1, 0.82, 0, 1)
    lbl:SetText(text)
    return lbl
end

local FullUpdate  -- forward declaration

local function MakeCheckbox(parent, label, desc, key, yOff, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOff)
    cb:SetSize(22, 22)
    cb:SetChecked(GetSetting(key) and true or false)

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    lbl:SetText(label)

    if desc then
        local sub = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sub:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 24, 4)
        sub:SetTextColor(0.55, 0.55, 0.55, 1)
        sub:SetText(desc)
    end

    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        SetSetting(key, v)
        if onChange then onChange(v) end
    end)
    return cb
end

local function MakeSlider(parent, name, label, yOff, min, max, step, fmtFn, onChange)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOff)
    lbl:SetText(label)
    lbl:SetTextColor(0.9, 0.9, 0.9, 1)

    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOff - 14)
    sl:SetWidth(parent:GetWidth() - 32)
    sl:SetMinMaxValues(min, max)
    sl:SetValueStep(step)
    sl:SetValue(0)  -- set after scripts to avoid early fire

    local valLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valLbl:SetPoint("TOP", sl, "BOTTOM", 0, 2)
    valLbl:SetTextColor(0.9, 0.9, 0.9, 1)

    sl:SetScript("OnValueChanged", function(self, val)
        local snapped = math.floor(val / step + 0.5) * step
        valLbl:SetText(fmtFn(snapped))
        onChange(snapped)
    end)

    return sl, valLbl
end

local function CreateMarkSelector(parent, yOff)
    local MARK_NAMES = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}
    local bSize, gap = 22, 3
    local totalW = 8 * bSize + 7 * gap
    local startX = math.floor((parent:GetWidth() - totalW) / 2)
    local markBtns = {}

    local function UpdateHighlight()
        local cur = GetSetting("markIndex")
        for i, mb in ipairs(markBtns) do
            mb.sel[i == cur and "Show" or "Hide"](mb.sel)
        end
    end

    for i = 1, 8 do
        local mb = CreateFrame("Button", nil, parent)
        mb:SetSize(bSize, bSize)
        mb:SetPoint("TOPLEFT", parent, "TOPLEFT", startX + (i-1)*(bSize+gap), yOff)

        local tex = mb:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetTexture(fmt("Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d", i))

        local hl = mb:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")

        mb.sel = mb:CreateTexture(nil, "OVERLAY")
        mb.sel:SetPoint("TOPLEFT", mb, "TOPLEFT", -2, 2)
        mb.sel:SetPoint("BOTTOMRIGHT", mb, "BOTTOMRIGHT", 2, -2)
        mb.sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        mb.sel:SetBlendMode("ADD")
        mb.sel:SetVertexColor(1, 0.82, 0, 1)
        mb.sel:Hide()

        mb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine(MARK_NAMES[i], 1, 1, 1)
            GameTooltip:Show()
        end)
        mb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mb:SetScript("OnClick", function()
            SetSetting("markIndex", i)
            UpdateHighlight()
        end)
        markBtns[i] = mb
    end
    UpdateHighlight()
end

local function UpdateLockButton()
    if not lockBtn then return end
    local locked = GetSetting("frameLock")
    lockBtn.tex:SetTexture(locked
        and "Interface\\Buttons\\LockButton-Locked-Up"
        or  "Interface\\Buttons\\LockButton-Unlocked-Up")
    lockBtn.tex:SetVertexColor(locked and 1 or 0.5, locked and 0.6 or 0.5, locked and 0 or 0.5, 1)
end

-- ─── Options panel ────────────────────────────────────────────────────────────

local function CreateOptionsFrame()
    if optionsFrame then optionsFrame:Show(); return end

    local W, H = 260, 696
    optionsFrame = CreateFrame("Frame", "pfQuestTargetingOptions", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    optionsFrame:SetSize(W, H)
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:EnableMouse(true)
    optionsFrame:SetMovable(true)
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    MakeBackdrop(optionsFrame)

    local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 12, -10)
    title:SetText("|cFFFFD700pfQuest Targeting|r  |cFF888888Settings|r")

    local closeBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() optionsFrame:Hide() end)

    optionsFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" then self:StartMoving() end
    end)
    optionsFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    local y = -28

    -- ── Display ──────────────────────────────────────────────────────────────
    SectionLabel(optionsFrame, "Display", y); y = y - 18

    MakeCheckbox(optionsFrame, "Show portraits", "Mob face shown when in nameplate range",
        "showPortraits", y, function()
            for _, btn in ipairs(buttons) do RefreshPortrait(btn) end
        end)
    y = y - 36

    MakeCheckbox(optionsFrame, "Lock window position", nil, "frameLock", y, function()
        UpdateLockButton()
    end)
    y = y - 28

    MakeCheckbox(optionsFrame, "Show minimap button", nil, "minimapButton", y, function(v)
        if minimapBtn then minimapBtn[v and "Show" or "Hide"](minimapBtn) end
    end)
    y = y - 32

    -- Background opacity
    local opSlider, opVal = MakeSlider(optionsFrame, "pfQTOpSlider", "Background Opacity",
        y, 0.1, 1.0, 0.05,
        function(v) return fmt("%d%%", math.floor(v * 100)) end,
        function(v)
            SetSetting("bgOpacity", v)
            if targetFrame then MakeBackdrop(targetFrame, 0.08, 0.08, 0.08, v) end
        end)
    if _G["pfQTOpSliderLow"]  then _G["pfQTOpSliderLow"]:SetText("Dim")   end
    if _G["pfQTOpSliderHigh"] then _G["pfQTOpSliderHigh"]:SetText("Solid") end
    opSlider:SetValue(GetSetting("bgOpacity"))
    opVal:SetText(fmt("%d%%", math.floor(GetSetting("bgOpacity") * 100)))
    y = y - 52

    -- Buttons per row
    local bprSlider, bprVal = MakeSlider(optionsFrame, "pfQTBprSlider", "Buttons Per Row",
        y, 1, 8, 1,
        function(v) return fmt("%d", v) end,
        function(v)
            SetSetting("buttonsPerRow", v)
            RebuildButtons()
        end)
    if _G["pfQTBprSliderLow"]  then _G["pfQTBprSliderLow"]:SetText("1") end
    if _G["pfQTBprSliderHigh"] then _G["pfQTBprSliderHigh"]:SetText("8") end
    bprSlider:SetValue(GetSetting("buttonsPerRow"))
    bprVal:SetText(fmt("%d", GetSetting("buttonsPerRow")))
    y = y - 52

    -- ── Behavior ─────────────────────────────────────────────────────────────
    SectionLabel(optionsFrame, "Behavior", y); y = y - 18

    MakeCheckbox(optionsFrame, "Auto-target", "Target mobs when nameplate appears",
        "autoTarget", y)
    y = y - 36

    MakeCheckbox(optionsFrame, "  Auto-target in combat", nil, "autoTargetInCombat", y)
    y = y - 28

    MakeCheckbox(optionsFrame, "Auto-mark quest mobs", nil, "autoMark", y)
    y = y - 26
    MakeCheckbox(optionsFrame, "  Mark on mouseover", nil, "markOnMouseover", y)
    y = y - 26

    -- Mark type row
    local markLbl = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    markLbl:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 34, y)
    markLbl:SetText("Mark type:")
    markLbl:SetTextColor(0.65, 0.65, 0.65, 1)
    y = y - 16
    CreateMarkSelector(optionsFrame, y)
    y = y - 30

    MakeCheckbox(optionsFrame, "Sound alert", "Ping when a quest mob enters range",
        "soundAlert", y)
    y = y - 36

    MakeCheckbox(optionsFrame, "Include drop quests", "Show mobs for item drop objectives",
        "includeDropQuests", y, function() FullUpdate() end)
    y = y - 38

    -- ── Macro ────────────────────────────────────────────────────────────────
    SectionLabel(optionsFrame, "Macro", y); y = y - 18

    MakeCheckbox(optionsFrame, "Enable targeting macro", nil, "enableMacro", y, function(v)
        if v then UpdateMacro() end
    end)
    y = y - 36

    -- ── Window Scale ─────────────────────────────────────────────────────────
    SectionLabel(optionsFrame, "Window Scale", y); y = y - 22

    local scSlider, scVal = MakeSlider(optionsFrame, "pfQTScaleSlider", nil,
        y + 14, 0.5, 2.0, 0.05,
        function(v) return fmt("%.2fx", v) end,
        function(v)
            SetSetting("scale", v)
            if targetFrame then targetFrame:SetScale(v) end
        end)
    if _G["pfQTScaleSliderLow"]  then _G["pfQTScaleSliderLow"]:SetText("Small") end
    if _G["pfQTScaleSliderHigh"] then _G["pfQTScaleSliderHigh"]:SetText("Large") end
    scSlider:SetValue(GetSetting("scale"))
    scVal:SetText(fmt("%.2fx", GetSetting("scale")))

    -- ── Reset ─────────────────────────────────────────────────────────────────
    local resetBtn = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 22)
    resetBtn:SetPoint("BOTTOM", optionsFrame, "BOTTOM", 0, 12)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        for key, val in pairs(DEFAULTS) do DB()[key] = val end
        optionsFrame:Hide()
        optionsFrame = nil
        CreateOptionsFrame()
        FullUpdate()
        print("|cFF00FF00pfQuestTargeting:|r Settings reset to defaults.")
    end)
end

-- ─── Target frame ─────────────────────────────────────────────────────────────

local function CreateTargetFrame()
    if targetFrame then return end

    targetFrame = CreateFrame("Frame", "pfQuestTargetingWindow", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    targetFrame:SetSize(96, 20)
    targetFrame:SetClampedToScreen(true)
    targetFrame:EnableMouse(true)
    targetFrame:SetMovable(true)
    targetFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    targetFrame:Hide()
    MakeBackdrop(targetFrame, 0.08, 0.08, 0.08, GetSetting("bgOpacity"))

    targetFrame.title = targetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    targetFrame.title:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", 6, -4)
    targetFrame.title:SetText("|cFFFFD700Targets|r")

    -- Lock button
    lockBtn = CreateFrame("Button", nil, targetFrame)
    lockBtn:SetSize(14, 14)
    lockBtn:SetPoint("TOPRIGHT", targetFrame, "TOPRIGHT", -20, -3)
    lockBtn.tex = lockBtn:CreateTexture(nil, "OVERLAY")
    lockBtn.tex:SetAllPoints()
    lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(GetSetting("frameLock") and "Unlock position" or "Lock position", 1, 1, 1)
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lockBtn:SetScript("OnClick", function()
        SetSetting("frameLock", not GetSetting("frameLock"))
        UpdateLockButton()
    end)
    UpdateLockButton()

    -- Gear button
    local gear = CreateFrame("Button", nil, targetFrame)
    gear:SetSize(14, 14)
    gear:SetPoint("TOPRIGHT", targetFrame, "TOPRIGHT", -3, -3)
    local gearTex = gear:CreateTexture(nil, "OVERLAY")
    gearTex:SetAllPoints()
    gearTex:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearTex:SetAlpha(0.7)
    gear:SetScript("OnEnter", function(self)
        gearTex:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine("pfQuest Targeting Options", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function()
        gearTex:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
    gear:SetScript("OnClick", function()
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:Hide()
        else CreateOptionsFrame() end
    end)

    targetFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not GetSetting("frameLock") then self:StartMoving() end
    end)
    targetFrame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        DB().point = point; DB().relPoint = relPoint; DB().x = x; DB().y = y
    end)
end

local function RestoreFramePosition()
    local db = DB()
    if db.point then
        targetFrame:ClearAllPoints()
        targetFrame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    end
    targetFrame:SetScale(GetSetting("scale"))
end

-- ─── Minimap button ───────────────────────────────────────────────────────────

local function CreateMinimapButton()
    if minimapBtn then return end

    minimapBtn = CreateFrame("Button", "pfQTMinimapButton", Minimap)
    minimapBtn:SetSize(20, 20)
    minimapBtn:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    minimapBtn:RegisterForClicks("AnyUp")
    minimapBtn:RegisterForDrag("LeftButton")
    minimapBtn:SetMovable(true)

    local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\Trade_Engineering")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Border ring: 53x53 texture, ring center sits at ~(20.5,20.5) inside it.
    -- For a 20x20 button (center at screen 10,10): offset = 10 - 20.5 = -10.5 → -11
    local border = minimapBtn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", -6, 6)

    local hl = minimapBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    local radius = 79
    local function SnapToEdge(angle)
        minimapBtn:ClearAllPoints()
        minimapBtn:SetPoint("CENTER", Minimap, "CENTER",
            radius * math.cos(math.rad(angle)),
            radius * math.sin(math.rad(angle)))
        DB().minimapAngle = angle
    end
    SnapToEdge(DB().minimapAngle or 220)

    minimapBtn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    minimapBtn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = Minimap:GetCenter()
        local bx, by = self:GetCenter()
        SnapToEdge(math.deg(math.atan2(by - cy, bx - cx)))
    end)

    minimapBtn:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            SetSetting("minimapButton", false)
            minimapBtn:Hide()
            print("|cFF00FF00pfQuestTargeting:|r Minimap button hidden. Type |cFFFFD700/pfqt options|r to re-enable.")
        else
            if targetFrame:IsShown() then targetFrame:Hide()
            elseif ShouldShowFrame() then targetFrame:Show() end
        end
    end)

    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("pfQuest Targeting", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: toggle window",   0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: hide button",    0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag: reposition",            0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if not GetSetting("minimapButton") then minimapBtn:Hide() end
end

-- ─── Marking & sound ──────────────────────────────────────────────────────────

local function TryMark(unitToken)
    if not GetSetting("autoMark") then return end
    if InCombatLockdown() then return end
    local name = UnitName(unitToken)
    if not name or not nameSet[name] then return end
    local want = GetSetting("markIndex")
    if GetRaidTargetIndex(unitToken) == want then return end
    pcall(SetRaidTarget, unitToken, want)
end

local function PlayAlertSound()
    if not GetSetting("soundAlert") then return end
    local now = GetTime()
    if now - lastSoundTime < 2 then return end
    lastSoundTime = now
    pcall(PlaySound, "igQuestActivate")
end

-- ─── Nameplate detection ─────────────────────────────────────────────────────

local function OnNameplateAdded(unitToken)
    local name = UnitName(unitToken)
    if not name or not nameSet[name] then return end
    nearbyUnits[name] = unitToken
    for _, btn in ipairs(buttons) do
        if btn.mobName == name then RefreshPortrait(btn) end
    end
    UpdateButtonVisuals()
    if ShouldShowFrame() then targetFrame:Show() end
    PlayAlertSound()

    TryMark(unitToken)

    if GetSetting("autoTarget") then
        if not InCombatLockdown() or GetSetting("autoTargetInCombat") then
            if not UnitExists("target") then
                pcall(TargetUnit, unitToken)
            end
        end
    end
end

local function OnNameplateRemoved(unitToken)
    for name, uid in pairs(nearbyUnits) do
        if uid == unitToken then
            nearbyUnits[name] = nil
            for _, btn in ipairs(buttons) do
                if btn.mobName == name then btn.icon:SetTexture(MOB_PLACEHOLDER) end
            end
            break
        end
    end
    UpdateButtonVisuals()
    if not ShouldShowFrame() then targetFrame:Hide() end
end

local function OnUnitSeen(unitToken)
    local name = UnitName(unitToken)
    if not name or not nameSet[name] then return end
    if not nearbyUnits[name] then
        nearbyUnits[name] = unitToken
        for _, btn in ipairs(buttons) do
            if btn.mobName == name then RefreshPortrait(btn) end
        end
        UpdateButtonVisuals()
        if ShouldShowFrame() then targetFrame:Show() end
    end
    if unitToken ~= "mouseover" or GetSetting("markOnMouseover") then
        TryMark(unitToken)
    end
end

-- ─── Full refresh ─────────────────────────────────────────────────────────────

FullUpdate = function()
    local oldNameSet = {}
    for k in pairs(nameSet) do oldNameSet[k] = true end

    activeNames = GetKillObjectiveNames()
    wipe(nameSet)
    for _, name in ipairs(activeNames) do nameSet[name] = true end
    -- Clear marks on mobs that just left the list
    if GetSetting("autoMark") and not InCombatLockdown() then
        for name, unitToken in pairs(nearbyUnits) do
            if not nameSet[name] then
                local want = GetSetting("markIndex")
                if GetRaidTargetIndex(unitToken) == want then
                    pcall(SetRaidTarget, unitToken, 0)
                end
            end
        end
    end

    for name in pairs(nearbyUnits) do
        if not nameSet[name] then nearbyUnits[name] = nil end
    end

    -- Completion flash: a name vanished from the list
    if next(oldNameSet) ~= nil then
        for name in pairs(oldNameSet) do
            if not nameSet[name] then
                if targetFrame and targetFrame.IsShown and targetFrame:IsShown() then
                    pcall(FlashFrame, targetFrame)
                end
                pcall(PlaySound, "igQuestComplete")
                break
            end
        end
    end

    UpdateMacro()
    RebuildButtons()
end

-- ─── Events ──────────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame", "pfQuestTargetingEvents")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
eventFrame:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        CreateTargetFrame()
        RestoreFramePosition()
        CreateMinimapButton()
        FullUpdate()
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" then
        FullUpdate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingMacroUpdate then UpdateMacro() end
        RebuildButtons()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        OnNameplateAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        OnNameplateRemoved(arg1)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        OnUnitSeen("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnUnitSeen("target")
    end
end)

-- ─── Slash commands ───────────────────────────────────────────────────────────

SLASH_PFQT1 = "/pfqt"
SlashCmdList["PFQT"] = function(msg)
    if msg == "options" or msg == "opt" then
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:Hide()
        else CreateOptionsFrame() end
        return
    end
    if msg == "debug" then
        print("|cFF00FF00pfQuestTargeting debug:|r")
        print(fmt("  pfDB loaded: %s", tostring(pfDB ~= nil)))
        print(fmt("  active mobs: %d", #activeNames))
        for i, n in ipairs(activeNames) do
            local nearby = nearbyUnits[n] and " |cFF00FF00[nearby]|r" or ""
            print(fmt("    [%d] %s%s", i, n, nearby))
        end
        for i = 1, GetNumQuestLogEntries() do
            SelectQuestLogEntry(i)
            if GetNumQuestLeaderBoards() > 0 then
                local title = GetQuestLogTitle(i)
                local qid   = GetQuestIDForIndex(i)
                print(fmt("  quest: %s (id=%s)", tostring(title), tostring(qid)))
                for j = 1, GetNumQuestLeaderBoards() do
                    local text, objType, finished = GetQuestLogLeaderBoard(j)
                    if not finished and objType == "item" then
                        local units = qid and GetDBKillUnits(qid)
                        if units then
                            for _, uid in ipairs(units) do
                                print(fmt("    drop mob: %s (uid=%d)", tostring(GetDBUnitName(uid)), uid))
                            end
                        else
                            print(fmt("    drop item objective — no DB mobs found (qid=%s)", tostring(qid)))
                        end
                    end
                end
            end
        end
        return
    end
    FullUpdate()
    print("|cFF00FF00pfQuestTargeting:|r Refreshed.")
end
