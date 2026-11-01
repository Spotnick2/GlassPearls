-- Pearls/TrainAllFrame.lua: train all's button (#39). Our own compact button
-- (80 px, "Train all"), parented to Blizzard's ClassTrainerFrame and anchored
-- left of its Train button (read for position, never written): the footer
-- leaves about 91 px there (SharedUIPanelTemplates.xml:571,
-- Blizzard_TrainerUI.xml:150), so the count and the cost are in its tooltip,
-- shown while disabled too. Made once, after Blizzard_TrainerUI loads.

GlassPearls = GlassPearls or {}
local GP = GlassPearls
local Frame = {}
GP.TrainAllFrame = Frame

Frame.WIDTH = 80
local button

local function TA() return GP.TrainAll end

local function tooltip(self)
    local list = TA().List()
    local total = 0
    for _, s in ipairs(list) do total = total + s.cost end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Train all")
    GameTooltip:AddLine(("Available now: %d spell%s, %s"):format(#list, #list == 1 and "" or "s",
        GP.TrainingFrame.Money(total)), 1, 1, 1)
    for _, s in ipairs(list) do GameTooltip:AddLine(s.name or ("spell " .. s.id), 0.8, 0.8, 0.8) end
    local m = GetMoney()
    if #list > 0 and type(m) == "number" and total > m then
        GameTooltip:AddLine("Not all affordable: the cheapest first, while your money lasts.", 1, 0.5, 0.3)
    end
    GameTooltip:Show()
end

-- Make the button once Blizzard's trainer frame exists; idempotent.
function Frame.Ensure()
    if button then return button end
    local parent = rawget(_G, "ClassTrainerFrame")
    local train = rawget(_G, "ClassTrainerTrainButton")
    if not (parent and train) then return nil end
    button = CreateFrame("Button", "GlassPearlsTrainAllButton", parent, "UIPanelButtonTemplate")
    button:SetSize(Frame.WIDTH, 22)
    button:SetText("Train all")
    button:SetPoint("RIGHT", train, "LEFT", -4, 0)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", function() TA().Start() end)
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Frame.Refresh()
    return button
end

-- Shown only while on; enabled with something affordable to train.
function Frame.Refresh()
    if not button then return end
    button:SetShown(TA().enabled == true)
    if not TA().enabled then return end
    local list = TA().List()
    local m = GetMoney()
    button:SetEnabled(#list > 0 and type(m) == "number" and list[1].cost <= m and TA().state.run == nil)
end

function Frame.Button() return button end
