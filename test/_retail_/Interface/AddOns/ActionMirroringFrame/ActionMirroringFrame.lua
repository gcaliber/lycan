local addonName, addonTable = ...

_G[addonName] = addonTable

setmetatable(addonTable, {__index = getfenv() })
setfenv(1, addonTable)

ACTION_TYPE_NORMAL = 1
ACTION_TYPE_SPECIAL = 2
ACTION_TYPE_PET = 3

actions = {{},{},{}}
spells = {}

local eventHandler = CreateFrame("frame")
eventHandler:RegisterEvent("ADDON_LOADED")
eventHandler:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventHandler:RegisterEvent("UNIT_SPELLCAST_STOP")
eventHandler:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventHandler:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
eventHandler:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventHandler:RegisterEvent("UNIT_SPELLCAST_START")
eventHandler:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventHandler:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventHandler:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
eventHandler:RegisterEvent("UNIT_SPELLCAST_SENT")

local current = {}
local currentChannel = {}

defaultSettings = {
    scale = 1,
    timeout = 3,
    maxFrames = 4,
    vertical = false,
    direction = 1,
    powerAnchor = 0,
    noDoubles = true,
    posAnims = true,
    successAnim = 1,
    showRanks = true,
    rankStyle = 1,
    showHotkeys = true,
    stickyCD = 0
}

local defaultColors = {
    CURRENT = {0,1,0,.8},
    NOMANA = {0,0,1,1},
    NOTUSABLE = {0.5,0,0,.8},
    NOTINRANGE = {1,1,0,.8},
    EQUIPPED = {0,1,0,0.5},
}

function eventHandler.ADDON_LOADED(name)
    if name == addonName then
        if not ActionMirroringFrameProfile then
            _G.ActionMirroringFrameProfile = _G.ActionMirroringFrameProfile or {}
        end
        setmetatable(ActionMirroringFrameProfile, {__index = defaultSettings})
        
        if not ActionMirroringFrameProfile.x then
            anchor.marginLeft = EFrame.bind("(EFrame.root.width - self.width)/2")
            anchor.marginTop =  EFrame.bind("EFrame.root.height*0.6")
        else
            anchor.marginLeft = EFrame.normalizeBind(ActionMirroringFrameProfile.x)
            anchor.marginTop = EFrame.normalizeBind(ActionMirroringFrameProfile.y)
        end
        anchor.anchorTopLeft = EFrame.root.topLeft
        anchor:connect("marginLeftChanged", function(x) ActionMirroringFrameProfile.x = EFrame.normalized(x) end)
        anchor:connect("marginTopChanged", function(y) ActionMirroringFrameProfile.y = EFrame.normalized(y) end)
        
        ActionMirroringFrameHandler.scale = ActionMirroringFrameProfile.scale
        ActionMirroringFrameHandler:connect("scaleChanged", function(s) ActionMirroringFrameProfile.scale = s end)
        
        ActionMirroringFrameHandler.timeout = ActionMirroringFrameProfile.timeout
        ActionMirroringFrameHandler:connect("timeoutChanged", function(n) ActionMirroringFrameProfile.timeout = n end)
        
        ActionMirroringFrameHandler.maxFrames = ActionMirroringFrameProfile.maxFrames
        ActionMirroringFrameHandler:connect("maxFramesChanged", function(n) ActionMirroringFrameProfile.maxFrames = n end)
        
        ActionMirroringFrameHandler.showRanks = ActionMirroringFrameProfile.showRanks
        ActionMirroringFrameHandler:connect("showRanksChanged", function(n) ActionMirroringFrameProfile.showRanks = n end)
        
        ActionMirroringFrameHandler.rankStyle = ActionMirroringFrameProfile.rankStyle
        ActionMirroringFrameHandler:connect("rankStyleChanged", function(n) ActionMirroringFrameProfile.rankStyle = n end)
        
        ActionMirroringFrameHandler.vertical = ActionMirroringFrameProfile.vertical
        ActionMirroringFrameHandler:connect("verticalChanged", function(v) ActionMirroringFrameProfile.vertical = v end)
        
        ActionMirroringFrameHandler.direction = ActionMirroringFrameProfile.direction
        ActionMirroringFrameHandler:connect("directionChanged", function(d) ActionMirroringFrameProfile.direction = d end)
        
        ActionMirroringFrameHandler.powerAnchor = ActionMirroringFrameProfile.powerAnchor
        ActionMirroringFrameHandler:connect("powerAnchorChanged", function(d) ActionMirroringFrameProfile.powerAnchor = d end)
        
        ActionMirroringFrameHandler.noDoubles = ActionMirroringFrameProfile.noDoubles
        ActionMirroringFrameHandler:connect("noDoublesChanged", function(d) ActionMirroringFrameProfile.noDoubles = d end)
        
        ActionMirroringFrameHandler.posAnims = ActionMirroringFrameProfile.posAnims
        ActionMirroringFrameHandler:connect("posAnimsChanged", function(d) ActionMirroringFrameProfile.posAnims = d end)
        
        ActionMirroringFrameHandler.successAnim = ActionMirroringFrameProfile.successAnim
        ActionMirroringFrameHandler:connect("successAnimChanged", function(d) ActionMirroringFrameProfile.successAnim = d end)
        
        ActionMirroringFrameHandler.showHotkeys = ActionMirroringFrameProfile.showHotkeys
        ActionMirroringFrameHandler:connect("showHotkeysChanged", function(d) ActionMirroringFrameProfile.showHotkeys = d end)
        
        ActionMirroringFrameHandler.stickyCD = ActionMirroringFrameProfile.stickyCD
        ActionMirroringFrameHandler:connect("stickyCDChanged", function(d) ActionMirroringFrameProfile.stickyCD = d end)

        if not _G.ActionMirroringFrameSettings then
            _G.ActionMirroringFrameSettings = {}
        end
        if not ActionMirroringFrameSettings.borderColors then
            ActionMirroringFrameSettings.borderColors = {}
        end
        for k, v in pairs(ActionMirroringFrameSettings.borderColors) do
            borderColors[k] = v
        end
        for k in pairs(defaultColors) do
            borderColors:connect(k.."Changed", function(v)  ActionMirroringFrameSettings.borderColors[k] = v end)
        end
    end
end

function eventHandler.UNIT_SPELLCAST_SUCCEEDED(target, _, spell)
    if target ~= "player" and target ~= "pet" or not spells[spell] then return end
    local action = spells[spell][1]
    if action then
        action.successTime = GetTime()
        if action.actionType == ACTION_TYPE_NORMAL then
            action.used = not IsAutoRepeatAction(action.id)
        else
            action.used = true
        end
    end
end

function eventHandler.UNIT_SPELLCAST_STOP(target, _, spell)
    if target ~= "player" and target ~= "pet" or not spells[spell] then return end
    local action = spells[spell][1]
    if action and action.status == "CURRENT" then
        action.status = "FAILED"
    end
    current[target] = nil
end
eventHandler.UNIT_SPELLCAST_FAILED = eventHandler.UNIT_SPELLCAST_STOP
eventHandler.UNIT_SPELLCAST_FAILED_QUIET = eventHandler.UNIT_SPELLCAST_STOP


function eventHandler.UNIT_SPELLCAST_START(target, _, spell)
    if target ~= "player" and target ~= "pet" or not spells[spell] then return end
    local st = spells[spell]
    if #st == 1 then
        ActionMirroringFrameHandler:onActionUsed(st[1].id, st[1].actionType)
    end
end

function eventHandler.UNIT_SPELLCAST_CHANNEL_START(target)
    if target ~= "player" and target ~= "pet" then return end
    if current[target] then
        current[target].channeling = true
        currentChannel[target] = current[target]
    end
end

function eventHandler.UNIT_SPELLCAST_CHANNEL_STOP(target)
    if target ~= "player" and target ~= "pet" then return end
    if currentChannel[target] then
        currentChannel[target].channeling = false
    end
end

function eventHandler.UNIT_SPELLCAST_CHANNEL_UPDATE(target, ...)
    if target ~= "player" and target ~= "pet" then return end
    if currentChannel[target] then
        currentChannel[target].channeling = true
    end
end

function eventHandler.UNIT_SPELLCAST_SENT(target, _, _, spell)
    if target ~= "player" and target ~= "pet" or not spells[spell] then return end
    local st = spells[spell]
    if #st == 1 then
        ActionMirroringFrameHandler:onActionUsed(st[1].id, st[1].actionType)
    end
    current[target] = st[1]
end

eventHandler:SetScript("OnEvent", function(self, event, ...) EFrame:atomic(self[event], ...) end)


ActionMirroringFrameHandler = EFrame.Object()
ActionMirroringFrameHandler:attach("scale")
ActionMirroringFrameHandler:attach("maxFrames")
ActionMirroringFrameHandler:attach("powerAnchor")
ActionMirroringFrameHandler:attach("direction")
ActionMirroringFrameHandler:attach("vertical")
ActionMirroringFrameHandler:attach("mirrors")
ActionMirroringFrameHandler:attach("noDoubles")
ActionMirroringFrameHandler:attach("posAnims")
ActionMirroringFrameHandler:attach("successAnim")
ActionMirroringFrameHandler:attach("showRanks")
ActionMirroringFrameHandler:attach("timeout")
ActionMirroringFrameHandler:attach("rankStyle")
ActionMirroringFrameHandler:attach("showHotkeys")
ActionMirroringFrameHandler:attachSignal("actionUsed")
ActionMirroringFrameHandler.__scale = 1
ActionMirroringFrameHandler.__direction = 1
ActionMirroringFrameHandler.__powerAnchor = 0
ActionMirroringFrameHandler.__rankStyle = 1
ActionMirroringFrameHandler.__showRanks = true
ActionMirroringFrameHandler.__noDoubles = true
ActionMirroringFrameHandler.__showHotkeys = true
ActionMirroringFrameHandler.__mirrors = {}

function ActionMirroringFrameHandler:onMirrorsChanged(m)
    for i = 1, #m do
        m[i].__action.position = m[i].__action.__status ~= "HIDE" and  i or nil
    end
end

hooksecurefunc("UseAction", EFrame:makeAtomic(function (id)
    ActionMirroringFrameHandler:actionUsed(id, ACTION_TYPE_NORMAL)
end))
hooksecurefunc("CastShapeshiftForm", EFrame:makeAtomic(function (id)
    ActionMirroringFrameHandler:actionUsed(id, ACTION_TYPE_SPECIAL)
end))
hooksecurefunc("CastPetAction", EFrame:makeAtomic(function (id)
    ActionMirroringFrameHandler:actionUsed(id, ACTION_TYPE_PET)
end))

function ActionMirroringFrameHandler:onActionUsed(id, type)
    if type == ACTION_TYPE_NORMAL and not HasAction(id) then return
    elseif type == ACTION_TYPE_PET and not GetPetActionInfo(id) then return
    end
    local mirrors = ActionMirroringFrameHandler.__mirrors
    local lasti = #mirrors
    local updatePos = true
    local action
    if ActionMirroringFrameHandler.noDoubles then
        action = actions[type][id]
        if action then
            action.start = GetTime()
            action.actionType = type
            action:update(true)
            if action:IsCurrentMirrorAction() then
                lasti = action.position
                updatePos = false
            else
                return
            end
        end
    else
        for i = 1, lasti-1 do
            local first = mirrors[i].__action
            if first.__status == "HIDE" or first.id ~= id and first.__status ~= "CURRENT" then
                break
            end
            if first.id == id then
                action = first
                action.start = GetTime()
                action.actionType = type
                action:update(true)
                if action:IsCurrentMirrorAction() then
                    lasti = action.position
                    updatePos = false
                else
                    return
                end
            end
        end
    end
    local le = 1

    local mirror = tremove(mirrors,lasti)
    if not action then
        action = mirror.__action
        action:reset()
        if action.id and actions[type][action.id] == action then actions[type][action.id] = nil end
        action.actionType = type
        action.start = GetTime()
        action.id = id
        actions[type][id] = action
        action:update(true)
    end
    for i = 1, lasti-1 do
        if mirrors[i].__action:IsCurrentMirrorAction() then
            le = i +1
        else
            break
        end
    end
    tinsert(mirrors, le, mirror)
    ActionMirroringFrameHandler:mirrorsChanged(mirrors)
    mirror:updatePosition(updatePos)
end

anchor = EFrame.MouseArea()
anchor.width = EFrame.bind(function() return ActionMirroringFrameHandler.scale * EFrame.normalize(45) end)
anchor.height = EFrame.bind(anchor, "width")
anchor.tex = EFrame.Image(anchor)
anchor.tex.anchorFill = anchor
anchor.tex.source = "Interface\\AddOns\\ActionMirroringFrame\\handle.tga"
anchor.tex.rotation = EFrame.bind(function() return ActionMirroringFrameHandler.direction*math.pi/2 + (ActionMirroringFrameHandler.vertical and math.pi/2 or 0) end)
anchor.dragTarget = anchor
anchor.visible = false

anchor.scalingHandle = EFrame.Button(anchor)
anchor.scalingHandle.icon = "Interface\\Addons\\EmeraldFramework\\Textures\\ResizeHandle_small"
anchor.scalingHandle.width=14
anchor.scalingHandle.height=14
anchor.scalingHandle.anchorBottom = anchor.bottom
anchor.scalingHandle.anchorRight = anchor.right
anchor.scalingHandle:connect("pressedChanged", function (p)
    local handle = anchor.scalingHandle
    if p then
        handle.ox = handle.mouseX
        handle.oy = handle.mouseY
    end
end)
anchor.scalingHandle:connect("mouseXChanged", function (x)
    local handle = anchor.scalingHandle
    if handle.__pressed then
        ActionMirroringFrameHandler.scale = math.max((anchor.__width + (x - handle.ox)) / EFrame.normalize(45), 0.5)
    end
end)

EFrame.newClass("Action", EFrame.Object)
Action:attach("status")
Action:attach("texture")
Action:attach("usable")
Action:attach("nomana")
Action:attach("missingPower", nil, "setMissingPower")
Action:attach("powerType")
Action:attach("cdEnabled")
Action:attach("cdStart")
Action:attach("cdDuration")
Action:attach("pressed")
Action:attach("hotkey")
Action:attach("count")
Action:attach("position")
Action:attach("rank")
Action:attach("rankMax")
Action.__status = "HIDE"
Action.__start = 0
Action.__count = ""
Action.__time = 0
Action.__missingPower = {}
Action.__powerType = 0
Action.__position = 1
Action.__rank = 0
Action.__rankMax = 0

function Action:new()
    EFrame.Object.new(self)
    EFrame.root:connect("update", self, "update")
    self:connect("statusChanged", function (s)
        if s == "HIDE" then
            local mirrors = ActionMirroringFrameHandler.__mirrors
            tinsert(mirrors, tremove(mirrors, self.__position))
            ActionMirroringFrameHandler:mirrorsChanged(mirrors)
            self:reset()
        end
    end)
end

function Action:IsCurrentMirrorAction()
    return self.actionType == ACTION_TYPE_NORMAL and self.id and actions[ACTION_TYPE_NORMAL][self.id] == self and (IsCurrentAction(self.id) or IsAutoRepeatAction(self.id))
end

local bindNameCache = {}
local bindCache = {}
local bindMap = {
    MOUSEWHEELUP = "W↑",
    MOUSEWHEELDOWN = "W↓",
    NUMPAD = "P",
    BUTTON = "M",
}

local function mangleBind(s)
    if not s or s == "" then return "" end
    local c = bindCache[s]
    if c then return c end
    c = ""
    if strmatch(s, "ALT") then
        c = "a"
    end
    if strmatch(s, "CTRL") then
        c = c .. "c"
    end
    if strmatch(s, "SHIFT") then
        c = c .. "s"
    end
    local r
    local b, _, n = strfind(s, "-([^-]*)$")
    if c == "" then
        r = s
    else
        r = n
    end
    if #r < 4 then
        c = c .. r
    elseif bindMap[r] then
        c = c .. bindMap[r]
    elseif r == "MOUSEWHEELDOWN" then
        c = c .. "MD"
    else
        local b, _, t, n = strfind(r, "(%D*)(%d*)")
        if b then
            c = c .. (bindMap[t] or t) .. n
        else
            c = c .. r
        end
    end
    bindCache[s] = c
    return c
end

local function getBindString(name, id)
    if not bindNameCache[name] then
        bindNameCache[name] = {}
    end
    local n = bindNameCache[name]
    if not n[id] then
        n[id] = name .. id
    end
    return mangleBind(GetBindingKey(n[id]))
end

local getActionBarNameCache = {}
local function getActionBarName(id)
        local bar = 6 - math.floor((id-1)/12)
        if bar == 4 then
            bar = 3
        elseif bar == 3 then
            bar = 4
        end
    if not getActionBarNameCache[id] then
        getActionBarNameCache[id] = (bar < 1 or id <= 12) and "ACTIONBUTTON" or ("MULTIACTIONBAR"..bar.."BUTTON")
    end
    return getActionBarNameCache[id]
end

function Action:update(wake)
    if wake then self.__status = ""
    elseif self.__status == "HIDE" then return end
    local time = GetTime() - self.start
    if not self.id then return end
    local action = self.id;
    local checkmana
    if self.actionType == ACTION_TYPE_NORMAL then
        local button = self.id 
        local actionButtonType = getActionBarName(button)
        self.hotkey = getBindString(actionButtonType, mod(button -1,12)+1)
        self.texture = GetActionTexture(self.id)
        local actionType, id = GetActionInfo(self.id)
        if actionType == "macro" then
            self.spell = GetMacroSpell(id)
        elseif actionType == "spell" then
            self.spell = id
        elseif actionType == "item" then
            _, self.spell = GetItemSpell(id)
            self.item = id
        else
            self.spell = nil
        end
        if ( IsConsumableAction(action) or IsStackableAction(action) or (not IsItemAction(action) and GetActionCount(action) > 0) ) then
            local count = GetActionCount(action);
            if ( count > 9999 ) then
                self.count = "*";
            else
                self.count = count;
            end
        else
            local charges, maxCharges, chargeStart, chargeDuration = GetActionCharges(action);
            if (maxCharges > 1) then
                self.count = charges;
            else
                self.count = ""
            end
        end
        self.cdStart, self.cdDuration, self.cdEnabled = GetActionCooldown(self.id)
        local usable, nomana = IsUsableAction(self.id)
        local current = self:IsCurrentMirrorAction()
        if not HasAction(self.id) or not (ActionMirroringFrameHandler.timeout > 0 and time <= ActionMirroringFrameHandler.timeout or current and not self.used or self.channeling or self.cdStart > 0 and self.cdDuration - (GetTime() - self.cdStart)  <= ActionMirroringFrameHandler.stickyCD) then
            self.status = "HIDE"
            if actions[self.actionType][self.id] == self then actions[self.actionType][self.id] = nil end
            return
        elseif current then
            self.status = "CURRENT"
        elseif IsEquippedAction(self.id) then
            self.status = "EQUIPPED"
        elseif nomana then
            self.status = "NOMANA"
            checkmana = true
        elseif not usable then
            self.status = "NOTUSABLE"
        elseif IsActionInRange(self.id) == false then
            self.status = "NOTINRANGE"
        else
            self.status = "NORMAL"
        end
    elseif self.actionType == ACTION_TYPE_SPECIAL then
        self.hotkey = getBindString("SHAPESHIFTBUTTON", self.id)
        local current, usable
        self.texture,current,usable,self.spell = GetShapeshiftFormInfo(self.id)
        current = current or IsCurrentSpell(self.spell)
        self.cdStart, self.cdDuration, self.cdEnabled = GetShapeshiftFormCooldown(self.id)
        if not (ActionMirroringFrameHandler.timeout > 0 and time <= ActionMirroringFrameHandler.timeout or current and not self.used or self.channeling or self.cdStart > 0 and self.cdDuration - (GetTime() - self.cdStart)  <= ActionMirroringFrameHandler.stickyCD) then
            self.status = "HIDE"
            if actions[self.actionType][self.id] == self then actions[self.actionType][self.id] = nil end
            return
        elseif current then
            self.status = "CURRENT"
        elseif not usable then
            self.status = "NOTUSABLE"
        else
            self.status = "NORMAL"
        end
        checkmana = true
    elseif self.actionType == ACTION_TYPE_PET then
        self.hotkey = getBindString("BONUSACTIONBUTTON", self.id)
        local inRange, hasTarget, tex
        _,tex,_,_, useMana, mana,self.spell, hasTarget,inRange = GetPetActionInfo(self.id)
        self.texture = tonumber(tex) and tex or _G[tex]
        self.cdStart, self.cdDuration, self.cdEnabled = GetPetActionCooldown(self.id)
        local usable = GetPetActionsUsable(self.id)
        if not GetPetActionInfo(self.id) or not (ActionMirroringFrameHandler.timeout > 0 and time <= ActionMirroringFrameHandler.timeout or self.channeling or self.channeling or self.cdStart > 0 and self.cdDuration - (GetTime() - self.cdStart)  <= ActionMirroringFrameHandler.stickyCD) then
            self.status = "HIDE"
            if actions[self.actionType][self.id] == self then actions[self.actionType][self.id] = nil end
            return
        elseif not usable then
            self.status = "NOTUSABLE"
        elseif hasTarget and not inRange then
            self.status = "NOTINRANGE"
        else
            self.status = "NORMAL"
        end
        checkmana = true
    end
    
    if hasRanks and self.spell then
        local rank = strmatch(GetSpellSubtext(self.spell) or "", "(%d+)")
        local maxrank = strmatch(GetSpellSubtext((select(7,GetSpellInfo(GetSpellInfo(self.spell))))) or "", "(%d+)")
        self.rank = tonumber(rank) or 0
        self.rankMax = tonumber(maxrank) or 0
    else
        self.rank = 0
        self.rankMax = 0
    end
    if wake and self.spell then
        if not spells[self.spell] then
            spells[self.spell] = {self}
        else
            local found
            for k, s in ipairs(spells[self.spell]) do
                if s.id == self.id then
                    spells[self.spell][k] = self
                    found = true
                    break
                end
            end
            if not found then
                tinsert(spells[self.spell], self)
            end
        end
    end
    if self.spell and checkmana then
        local missingPowers = {}
        local runes
        for k,v in ipairs(GetSpellPowerCost(self.spell)) do
            local mp = v.minCost - UnitPower(self.actionType == ACTION_TYPE_PET and "pet" or "player", v.type)
            if mp > 0 then
                if self.actionType ~= ACTION_TYPE_NORMAL then
                    self.status = "NOMANA"
                end
                tinsert(missingPowers, { missing = mp, type = v.type })
            elseif v.type >= 20 and v.type <= 22 then
                runes = runes or {}
                runes[runesType[v.type]] = true
            end
        end
        if runes then
            local runesCd = {}
            local deathRunes = {}
            for i = 1,6 do
                local rtype = GetRuneType(i)
                local start, duration, ready = GetRuneCooldown(i)
                local cdEnd = ready and 0 or start + duration
                if rtype == 4 then
                    tinsert(deathRunes, { start, duration, ready, type = rtype, cdEnd = cdEnd})
                elseif runes[rtype] then
                    local mcd = runesCd[rtype] and runesCd[rtype].cdEnd
                    if not mcd or cdEnd < mcd then
                        runesCd[rtype] = {start, duration, ready, type = rtype, cdEnd = cdEnd}
                    end
                end
            end
            table.sort(deathRunes, function(t) return cdEnd end)
            while #deathRunes > 0 do
                local highest = deathRunes[1].cdEnd
                for k, v in pairs(runes) do
                    local cd = runesCd[k] and runesCd[k].cdEnd
                    if not cd then
                        highest = k
                        break
                    elseif not highest or cd > highest then
                        highest = k
                    end
                end
                if not highest then
                    break
                end
                runesCd[highest] = deathRunes[1]
                tremove(deathRunes, 1)
            end
            missingPowers.runes = {}
            for k in pairs(runes) do
                if not runesCd[k][3] then
                    missingPowers.runes[k] = runesCd[k]
                end
            end
        end
        self.missingPower = missingPowers
    end
    self.pressed = time < 0.125
end

function Action:reset()
    self.channeling = false
    self.successTime = nil
    self.used = false
    self.item = nil
    if not (self.spell and spells[self.spell]) then return end
    for k, s in ipairs(spells[self.spell]) do
        if s.id == self.id then
            tremove(spells[self.spell], k)
            break
        end
    end
    self.spell = nil
end

function Action:setMissingPower(missingPower)
    local same = false
    if #missingPower == #self.__missingPower then
        same = true
        for k, v in ipairs(self.__missingPower) do
            if v ~= missingPower[k] then
                same = false
                break
            end
        end
        if same then
            local runes = self.__missingPower.runes
            local newRunes = missingPower.runes
            if not runes and not newRunes then
            elseif not runes or not newRunes then
                same = false
            else
                for k = 1,3 do
                    local rune = missingPower.runes[k]
                    local oldRune = self.__missingPower.runes[k]
                    if not oldRune and not rune then
                    elseif not oldRune or  not rune then
                        same = false
                        break
                    else
                        for kk, vv in pairs(oldRune) do
                            if vv ~= rune[kk] then
                                same = false
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if same then return end
    self.__missingPower = missingPower
    self:missingPowerChanged(missingPower)
    if #missingPower > 0 then
        self.powerType = missingPower[1].type
    else
        self.powerType = -1
    end
end
            
    

EFrame.newClass("ActionMirroringFrame", EFrame.Item)
ActionMirroringFrame:attach("action")
ActionMirroringFrame:attach("position")
ActionMirroringFrame.__position = 1

borderColors = EFrame.Object()
for k, v in pairs(defaultColors) do
    borderColors:attach(k)
    borderColors[k] = v
end
borderColors.HIDE = {0,0,0,0}


powerColors = {
    [-2] = {0.5 , 0   , 0   , 0.5 }, -- HP
    [-1] = {0.75, 0.75, 0.75, 0.5 }, -- NONE
    [0] =  {0   , 0   , 1   , 0.5 }, -- MANA
    [1] =  {1   , 0   , 0   , 0.5 }, -- RAGE
    [2] =  {1   , 0.5 , 0   , 0.5 }, -- FOCUS
    [3] =  {1   , 1   , 0   , 0.5 }, -- ENERGY
    [4] =  {1   , 0.96, 0.41, 0.25}, -- COMBO
    [5] =  {0.5 , 0.5 , 0.5 , 0.5 }, -- RUNES
    [6] =  {0   , 0.82, 1   , 0.5 }, -- RUNIC POWER
    [7] =  {0.5 , 0.32, 0.55, 0.5 }, -- SOUL SHARDS
    [8] =  {0.3 , 0.52, 0.90, 0.5 }, -- LUNAR POWER
    [9] =  {0.95, 0.9 , 0.6 , 0.5 }, -- HOLY POWER
    [10] = {0.75, 0.75, 0.75, 0.5 }, -- NONE
    [11] = {0   , 0.5 , 1   , 0.5 }, -- MAELSTROM
    [12] = {0.71, 1   , 0.92, 0.5 }, -- CHI
    [13] = {0.4 , 0   , 0.8 , 0.5 }, -- INSANITY
    [16] = {0.1 , 0.1 , 0.98, 0.5 }, -- ARCANE CHARGES
    [17] = {0.79, 0.26, 0.99, 0.5 }, -- FURY
    [18] = {1   , 0.61, 0   , 0.5 }, -- PAIN
    [19] = {0   , 0   , 1   , 0.5 }, -- Essence
    [20] = {1   , 0   , 0   , 0.5 }, -- RuneBlood
    [21] = {0   , 1   , 1   , 0.5 }, -- RuneFrost
    [22] = {0   , 0.33, 0   , 0.5 }, -- RuneUnholy
    ["AMMOSLOT"] =  { 0.8, 0.6 , 0  , 0.5 },
    ["FUEL"]     =  { 0.0, 0.55, 0.5, 0.5 },
}

runesOrder = { 1, 3, 2, 4 }
runesType2Index = { 20, 22, 21 }
runesType = { [20] = 1, [21] = 2, [22] = 3 }

local runesTextures = {}
runesTextures[1] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Blood"
runesTextures[2] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Unholy"
runesTextures[3] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Frost"
runesTextures[4] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Death"

function getPowerColor(t)
    local b = GetPowerBarColor and GetPowerBarColor(t)
    return b and {b.r, b.b, b.g} or powerColors[t] or powerColors[-1]
end

rankColors = {
    [0] = {0  ,0  ,0  ,0},
    [1] = {0  ,1  ,0  ,1},
    [2] = {1  ,1  ,0  ,1},
    [3] = {1  ,0  ,0  ,1},
    [4] = {1  ,1  ,1  ,1},
}

if
    WOW_PROJECT_ID == WOW_PROJECT_CLASSIC or
    WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC or
    WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC then
    hasRanks = true
end

function ActionMirroringFrame:new(action)
    self.__action = action
    EFrame.Item.new(self)
    self.anchorCenter = anchor.center
    self.hoffset = EFrame.bind(function() return ActionMirroringFrameHandler.vertical and 0 or EFrame.normalize(44) * ActionMirroringFrameHandler.direction * self.position * self.scale end)
    self.voffset = EFrame.bind(function() return -(ActionMirroringFrameHandler.vertical and EFrame.normalize(44) * ActionMirroringFrameHandler.direction * self.position * self.scale or 0) end)
    self.width = EFrame.normalizeBind(40)
    self.height = EFrame.normalizeBind(40)
    self.scale = EFrame.bind(ActionMirroringFrameHandler, "scale")
    self.tex = EFrame.Image(self)
    self.tex:setCoords(0.1,0.9,0.1,0.9)
    self.tex.margins = 2
    self.tex.anchorFill = self
    self.tex.source = EFrame.bind(function() return self.action.texture end)
    self.tex.layer = "BACKGROUND"
    
    ActionMirroringFrameHandler:connect("successAnimChanged", self, "initAnim")
    
    self.border = EFrame.Image(self)
    self.border.margins = EFrame.normalizeBind(-14)
    self.border.anchorFill = self
    self.border.source = 'Interface\\AddOns\\ActionMirroringFrame\\ButtonBorder.tga'
    self.border.layer = "OVERLAY"
    self.highlight = EFrame.Image(self)
    self.highlight.margins = 1
    self.highlight.anchorFill = self
    self.highlight.source = 'Interface\\AddOns\\ActionMirroringFrame\\ButtonHighlight.tga'
    self.highlight.color = EFrame.bind(function() return borderColors[self.action.status] or borderColors.HIDE  end)
    self.highlight.layer = "OVERLAY"
    self.highlight.blendMode = "ADD"
    self.highlight.visible = EFrame.bind(function() return self.action.status ~= "HIDE" end)
    self.powerIndicator = EFrame.Rectangle(self)
    self.powerIndicator.margins = 2
    self.powerIndicator.color = EFrame.bind(function() return getPowerColor(self.action.powerType) end)
    self.powerIndicator.visible = EFrame.bind(function() return self.action.status == "NOMANA" end)
    local powerAnchor = EFrame.bind(function()
        self.powerIndicator:clearAnchors()
        if ActionMirroringFrameHandler.powerAnchor == -1 or ActionMirroringFrameHandler.vertical then
            self.powerIndicator.anchorBottom = self.bottom
        elseif ActionMirroringFrameHandler.powerAnchor == 1 then
            self.powerIndicator.anchorTop = self.bottom
        else
            self.powerIndicator.anchorBottom = self.top
        end
        self.powerIndicator.anchorLeft = self.left
        self.powerIndicator.anchorRight = self.right
    end)
    powerAnchor.parent = self.powerIndicator
    powerAnchor:update()
    self.powerLabel = EFrame.Label(self.powerIndicator)
    self.powerLabel.marginBottom = 4
    self.powerLabel.marginTop = 2
    self.powerLabel.anchorFill = self.powerIndicator
    self.powerLabel.sizeMode = EFrame.Label.VerticalFit
    self.powerLabel.implicitHeight = EFrame.normalizeBind(10)
    self.powerLabel.text = EFrame.bind(function()
        local mp = {}
        for _,v in ipairs(self.action.missingPower) do
            tinsert(mp, v.missing)
        end
        return table.concat(mp, "/") end)
    self.powerIndicator.implicitHeight = EFrame.bind(function() return self.powerLabel.implicitHeight + 6 end)
    self.runesRow = EFrame.RowLayout(self.powerIndicator)
    self.runesRow.anchorFill = self.powerIndicator
    self.runes = {}
    for i = 1,3 do
        local idx = i
        local rune = EFrame.Image(self.runesRow)
        rune.Layout.alignment = EFrame.Layout.AlignHCenter
        rune.Layout.fillHeight = true
        rune.implicitWidth = EFrame.bind(rune, "height")
        rune.cooldown = EFrame.Cooldown(rune)
        rune.cooldown.margins = 0
        rune.cooldown.anchorFill = rune
        rune.cooldown.enabled = EFrame.bind(function() return self.action.missingPower.runes and self.action.missingPower.runes[idx] and not self.action.missingPower.runes[idx][3] end)
        rune.cooldown.start = EFrame.bind(function() return self.action.missingPower.runes and self.action.missingPower.runes[idx] and self.action.missingPower.runes[idx][1] or 0 end)
        rune.cooldown.duration = EFrame.bind(function() return self.action.missingPower.runes and self.action.missingPower.runes[idx] and self.action.missingPower.runes[idx][2] or 0 end)
        rune.cooldown.showCountdown = false
        rune.cooldown.swipeTexture = "Interface\\AddOns\\EmeraldFramework\\Textures\\CooldownCircular"
        rune.cooldown.swipeColor = {0, 0, 0, 1}
        rune.cooldown.drawEdge = true
        rune.visible = EFrame.bind(function()
            return self.action.missingPower.runes and self.action.missingPower.runes[idx] and true or false
        end)
        rune.source = EFrame.bind(function() return self.action.missingPower.runes and self.action.missingPower.runes[idx] and runesTextures[runesOrder[self.action.missingPower.runes[idx].type]] or "" end)
        self.runes[idx] = rune
    end
    self.cooldown = EFrame.Cooldown(self)
    self.cooldown.margins = 0
    self.cooldown.anchorFill = self.tex
    self.cooldown.enabled = EFrame.bind(function() return self.action.cdEnabled end)
    self.cooldown.start = EFrame.bind(function() return self.action.cdStart end)
    self.cooldown.duration = EFrame.bind(function() return self.action.cdDuration end)
    self.click = EFrame.Image(self)
    self.click.margins = 1
    self.click.source = "Interface\\Buttons\\UI-Quickslot-Depress"
    self.click.layer = "ARTWORK"
    self.click.anchorFill = self
    self.click.visible = EFrame.bind(function() return self.action.pressed end)
    self.label = EFrame.Label(self)
    self.label.n_text:SetFontObject("NumberFontNormalSmallGray")
    self.label.n_text:SetNonSpaceWrap(true)
    self.label.marginRight = 2
    self.label.marginTop = 4
    self.label.sizeMode = EFrame.Label.VerticalFit
    self.label.height = EFrame.normalizeBind(10)
    self.label.anchorTop = self.top
    self.label.anchorRight = self.right
    self.label.anchorLeft = self.left
    self.label.hAlignment = "RIGHT"
    self.label.text = EFrame.bind(function() return self.action.hotkey end)
    self.label.visible = EFrame.bind(ActionMirroringFrameHandler, "showHotkeys")
    self.countLabel = EFrame.Label(self)
    self.countLabel.n_text:SetFontObject("NumberFontNormal")
    self.countLabel.margins = 3
    self.countLabel.sizeMode = EFrame.Label.VerticalFit
    self.countLabel.anchorBottom = self.bottom
    self.countLabel.anchorRight = self.right
    self.countLabel.anchorLeft = self.left
    self.countLabel.hAlignment = EFrame.bind(function() return self.label.marginTop + self.label.height > self.height - self.countLabel.height - self.countLabel.marginBottom and "LEFT" or "RIGHT" end)
    self.countLabel.text = EFrame.bind(function() return self.action.count end)
    if hasRanks then
        for i=1,5 do
            local border = EFrame.Image(self)
            border.source = "Interface\\AddOns\\ActionMirroringFrame\\Rank2"
            border.color = EFrame.bind(function() local rank = self.action.rankMax return rankColors[(rank % 5 < i and 0 or 1) + math.floor(rank/5)] end)
            border.height = EFrame.normalizeBind(10)
            border.width = EFrame.normalizeBind(14)
            border:setCoords(0,1,0.25,0.75)
            border.marginBottom = EFrame.normalizeBind(5*(i -1) + 3)
            border.anchorBottom = self.bottomLeft
            border.z = 3
            border.visible = EFrame.bind(function() return self.action.rank > 0 and ActionMirroringFrameHandler.showRanks and (ActionMirroringFrameHandler.rankStyle == 1 or ActionMirroringFrameHandler.rankStyle == 3) end)
            
            local rank = EFrame.Image(border)
            rank.source = "Interface\\AddOns\\ActionMirroringFrame\\Rank"
            rank.color = EFrame.bind(function() local rank = self.action.rank return rankColors[(rank % 5 < i and 0 or 1) + math.floor(rank/5)] end)
            rank.height = EFrame.normalizeBind(8)
            rank.width = EFrame.normalizeBind(12)
            rank:setCoords(0,1,0.25,0.75)
            rank.marginBottom = EFrame.normalizeBind(5*(i -1) + 3)
            rank.anchorBottom = self.bottomLeft
            
        end
        self.rankLabel = EFrame.Label(self)
        self.rankLabel.anchorCenter = self.bottomLeft
        self.rankLabel.n_text:SetFontObject("NumberFontNormal")
        self.rankLabel.text = EFrame.bind(function() return self.action.rank end)
        self.rankLabel.z = 4
        self.rankLabel.sizeMode = EFrame.Label.VerticalFit
        self.rankLabel.height = EFrame.normalizeBind(10)
        self.rankLabel.visible = EFrame.bind(function() return self.action.rank > 0 and ActionMirroringFrameHandler.showRanks and (ActionMirroringFrameHandler.rankStyle == 1 or ActionMirroringFrameHandler.rankStyle == 2) end)
    end
    self.action:connect("positionChanged", self, "startPosition")
    EFrame.root:connect("update", self, "updateAnimations")
    self.visible = EFrame.bind(function(self) return self.action.status ~= "HIDE" end)
end

function ActionMirroringFrame:initAnim(a)
    if self.texAnim then self.texAnim:deleteLater() end
    local a = a or ActionMirroringFrameHandler.successAnim
    if a == 1 then
        self.texAnim = EFrame.Image(self)
        self.texAnim:setCoords(0.1,0.9,0.1,0.9)
        self.texAnim.margins = 2
        self.texAnim.anchorCenter = self.center
        self.texAnim.width = EFrame.bind(self, "width")
        self.texAnim.height = EFrame.bind(self, "height")
        self.texAnim.source = EFrame.bind(function() return self.action.texture end)
        self.texAnim.layer = "ARTWORK"
        self.texAnim.blendMode = "ADD"
        self.texAnim.duration = 0.250
    elseif a == 2 then
        self.texAnim = EFrame.Image(self)
        self.texAnim.margins = 2
        self.texAnim.anchorFill = self
        self.texAnim.source = "Interface\\AddOns\\ActionMirroringFrame\\ButtonHighlight"
        self.texAnim.color = {0,1,0,1}
        self.texAnim.layer = "ARTWORK"
        self.texAnim.duration = 0.5
    elseif a == 3 then
        self.texAnim = EFrame.Rectangle(self)
        self.texAnim.margins = 2
        self.texAnim.anchorFill = self
        self.texAnim.color = {.25,1,.25,0.5}
        self.texAnim.layer = "ARTWORK"
        self.texAnim.blendMode = "ADD"
        self.texAnim.duration = 0.5
    end
end

function ActionMirroringFrame:startPosition()
    self.animStart = GetTime()
end

function ActionMirroringFrame:updateAnimations()
    local s = self.__action.successTime
    if s then
        local t = (GetTime() - s) * 1/self.texAnim.duration
        if t >= 1 then
            t = 1
            self.__action.successTime = nil
        end
        local a = ActionMirroringFrameHandler.successAnim
        if a == 1 then
            self.texAnim.scale = 1 + math.sin(t*math.pi/2)*0.6
            self.texAnim.opacity = math.cos(t*math.pi/2)
        elseif a == 2 then
            self.texAnim.rotation = t * 20
            self.texAnim.opacity = math.cos(t*math.pi/2)
        elseif a == 3 then
            self.texAnim.color = {1 - math.cos(t*math.pi/2), 1, 1-math.cos(t*math.pi/2), 1-math.sin(t*math.pi/2)}
        end
        self.texAnim.visible = true
    else
        self.texAnim.visible = false
    end
    self:updatePosition()
end

function ActionMirroringFrame:updatePosition(instant)
    if not self.animStart or instant or not ActionMirroringFrameHandler.posAnims then self.position = self.__action.__position - 1 return end
    local t = (GetTime() - self.animStart) * 4
    if t >= 1 then
        t = 1
        self.animStart = nil
    end
    self.position = (self.__action.__position - 1) * t + self.__position * (1-t)
end

function ActionMirroringFrameHandler:onMaxFramesChanged(m)
    local mirrors = ActionMirroringFrameHandler.__mirrors
    if m > #mirrors then
        for i = #mirrors +1, m do
            tinsert(mirrors, ActionMirroringFrame(Action()))
        end
    elseif m < #mirrors then
        for i = #mirrors, m +1, -1 do
            mirrors[i].action:destroy()
            mirrors[i]:destroy()
            mirrors[i] = nil
        end
    end
end

local options
local of = CreateFrame("Frame")
of.name = "ActionMirroringFrame"
--of:Hide()
InterfaceOptions_AddCategory(of)

local function showOptions()
    if not options then
        options = EFrame.Item(nil, of, false)
        options.style = EFrame.Blizzlike
        options.toolBar = EFrame.RowLayout(options)
        options.toolBar.marginTop = 10
        options.toolBar.marginLeft = 10
        options.toolBar.marginRight = 10
        options.toolBar.anchorTopLeft = options.topLeft
        options.toolBar.anchorRight = options.right
        options.toolRow = EFrame.Rectangle(options)
        options.toolRow.color = {0.4,0.4,0.4,0.6}
        options.toolRow.height = 1
        options.toolRow.marginTop = 2
        options.toolRow.anchorTopLeft = options.toolBar.bottomLeft
        options.toolRow.anchorRight = options.toolBar.right
        options.unlockButton = options.style.Button(options.toolBar)
        options.unlockButton.text = EFrame.bind(function() return anchor.visible and "Lock" or "Unlock" end)
        options.unlockButton:connect("clicked", function() anchor.visible = not anchor.visible end)
        options.scroll = EFrame.Flickable(options)
        options.scroll.anchorLeft = options.left
        options.scroll.anchorRight = options.right
        options.scroll.anchorTop = options.toolBar.bottom
        options.scroll.anchorBottom = options.bottom
        options.scroll.marginLeft = 10
        options.scroll.marginRight = 10
        options.scroll.marginTop = 5
        options.scroll.marginBottom = 10
        options.main = EFrame.ColumnLayout(options.scroll)
        options.scroll.contentItem = options.main
        options.main.spacing = 4
        
        options.version = EFrame.RowLayout(options.main)
        options.version.label = EFrame.Label(options.version)
        options.version.label.text = "Version:"
        options.version.edit = EFrame.TextEdit(options.version)
        options.version.edit.implicitWidth = 100
        options.version.edit.readOnly = true
        options.version.edit.text = GetAddOnMetadata(addonName, "version")
        
        options.timeoutRow = EFrame.RowLayout(options.main)
        options.timeoutRow.spacing = 2
        options.timeoutLabel = EFrame.Label(options.timeoutRow)
        options.timeoutLabel.text = "Show actions duration (seconds):"
        options.timeoutSpinBox = options.style.SpinBox(options.timeoutRow)
        options.timeoutSpinBox.from = 0
        options.timeoutSpinBox.step = 0.1
        options.timeoutSpinBox.value = ActionMirroringFrameHandler.timeout
        function options.timeoutSpinBox:onValueModified(v) ActionMirroringFrameHandler.timeout = v end
        
        EFrame.Item(options.main).implicitHeight = 4
        
        options.maxFramesRow = EFrame.RowLayout(options.main)
        options.maxFramesRow.spacing = 2
        options.maxFramesLabel = EFrame.Label(options.maxFramesRow)
        options.maxFramesLabel.text = "Maximum number of actions shown:"
        options.maxFramesSpin = options.style.SpinBox(options.maxFramesRow)
        options.maxFramesSpin.from = 1
        options.maxFramesSpin.value = EFrame.bind(ActionMirroringFrameHandler, "maxFrames")
        function options.maxFramesSpin:onValueModified(v)
            ActionMirroringFrameHandler.maxFrames = v
        end
        
        options.cdRow = EFrame.RowLayout(options.main)
        options.cdRow.spacing = 2
        options.cdLabel = EFrame.Label(options.cdRow)
        options.cdLabel.text = "Keep visible cooldowns below (seconds):"
        options.cdSpinBox = options.style.SpinBox(options.cdRow)
        options.cdSpinBox.from = 0
        options.cdSpinBox.step = 0.1
        options.cdSpinBox.value = ActionMirroringFrameHandler.stickyCD
        function options.cdSpinBox:onValueModified(v) ActionMirroringFrameHandler.stickyCD = v end
        
        EFrame.Item(options.main).implicitHeight = 4
        
        options.noDoublesCheck = options.style.CheckButton(options.main)
        options.noDoublesCheck.checked = ActionMirroringFrameHandler.noDoubles
        options.noDoublesCheck.text = "No duplicates"
        function options.noDoublesCheck:onCheckedChanged(c)
            ActionMirroringFrameHandler.noDoubles = c
        end
        
        options.verticalRow = EFrame.RowLayout(options.main)
        options.verticalRow.spacing = 2
        options.verticalLabel = EFrame.Label(options.verticalRow)
        options.verticalLabel.text = "Growth:"
        options.growthCombo = options.style.ComboBox(options.verticalRow)
        options.growthCombo.model = {"Right", "Bottom", "Left", "Top"}
        options.growthCombo.currentIndex = (ActionMirroringFrameHandler.vertical and 3 or 2) - ActionMirroringFrameHandler.direction
        options.growthCombo:connect("activated", function(a) ActionMirroringFrameHandler.vertical = a%2 == 0 ActionMirroringFrameHandler.direction = (a%2 == 0 and 3 or 2) - a end)
        
        EFrame.Item(options.main).implicitHeight = 4
        
        options.powerAnchorRow = EFrame.RowLayout(options.main)
        options.powerAnchorRow.spacing = 2
        options.powerAnchorLabel = EFrame.Label(options.powerAnchorRow)
        options.powerAnchorLabel.text = "Missing Power frame position:"
        options.powerAnchorCombo = options.style.ComboBox(options.powerAnchorRow)
        options.powerAnchorCombo.model = {"Inner", "Top", "Bottom"}
        options.powerAnchorCombo.currentIndex = EFrame.bind(function() return ActionMirroringFrameHandler.vertical and 1 or ActionMirroringFrameHandler.powerAnchor + 2 end)
        options.powerAnchorCombo:connect("activated", function(a) ActionMirroringFrameHandler.powerAnchor = a - 2 end)
        options.powerAnchorCombo.enabled = EFrame.bind(function() return not ActionMirroringFrameHandler.vertical end)
        
        EFrame.Item(options.main).implicitHeight = 4
        
        options.hotkeysCheck = options.style.CheckButton(options.main)
        options.hotkeysCheck.checked = ActionMirroringFrameHandler.showHotkeys
        options.hotkeysCheck.text = "Show Action Hotkeys"
        function options.hotkeysCheck:onCheckedChanged(c)
            ActionMirroringFrameHandler.showHotkeys = c
        end
            
        EFrame.Item(options.main).implicitHeight = 4
        
        if hasRanks then
            options.rankCheck = options.style.CheckButton(options.main)
            options.rankCheck.checked = ActionMirroringFrameHandler.showRanks
            options.rankCheck.text = "Show spell ranks"
            function options.rankCheck:onCheckedChanged(c)
                ActionMirroringFrameHandler.showRanks = c
            end
            options.rankStyle = options.style.ComboBox(options.main)
            options.rankStyle.model = { "Icon and Number", "Number only", "Icon only" }
            options.rankStyle.currentIndex = ActionMirroringFrameHandler.rankStyle
            options.rankStyle:connect("activated", function(a) ActionMirroringFrameHandler.rankStyle = a end)
            options.rankStyle.enabled = EFrame.bind(ActionMirroringFrameHandler, "showRanks")
        
            EFrame.Item(options.main).implicitHeight = 4
        end
        
        options.animsTitle = EFrame.Label(options.main)
        options.animsTitle.text = "Animation Options"
        
        options.posAnims = options.style.CheckButton(options.main)
        options.posAnims.text = "Animate mirrors' positions changes"
        options.posAnims.checked = ActionMirroringFrameHandler.posAnims
        function options.posAnims:onCheckedChanged(c) ActionMirroringFrameHandler.posAnims = c end
        
        options.successAnimRow = EFrame.RowLayout(options.main)
        options.successAnimRow.spacing = 2
        options.successAnimLabel = EFrame.Label(options.successAnimRow)
        options.successAnimLabel.text = "Success Animation:"
        options.successAnimCombo = options.style.ComboBox(options.successAnimRow)
        options.successAnimCombo.model = {"Zoom", "Green Spin", "Green Flash"}
        options.successAnimCombo.currentIndex = EFrame.bind(ActionMirroringFrameHandler, "successAnim")
        options.successAnimCombo:connect("activated", function(a) ActionMirroringFrameHandler.successAnim = a end)
        
        
        local function ShowColorPicker(r, g, b, a, changedCallback)
            ColorPickerFrame:Hide()
            ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = nil, nil, nil
            ColorPickerFrame:SetColorRGB(r,g,b)
            ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = (a ~= nil), 1 - a or 0
            ColorPickerFrame.previousValues = {r,g,b,a}
            ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = changedCallback, changedCallback, changedCallback
            ColorPickerFrame:Show()
        end
        function colorPick(p, text, colors)
            local row = EFrame.RowLayout(p)
            row.Layout.fillWidth = true
            row.spacing = 2
            row.square = EFrame.Rectangle(row)
            row.square.Layout.fillHeight = true
            row.square.Layout.preferredWidth = EFrame.bind(row.square, "height")
            row.square.color = borderColors[colors[1]]
            row.label = EFrame.Label(row)
            row.label.text = text
            row.mouse = EFrame.MouseArea(row.square)
            row.mouse.anchorFill = row.square
            row.mouse:connect("clicked", function ()
                local color = borderColors[colors[1]]
                ShowColorPicker(color[1], color[2], color[3], color[4], function (restore)
                    if restore then
                        for _, v in ipairs(colors) do
                            borderColors[v] = restore
                        end
                    else
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        for _, v in ipairs(colors) do
                            borderColors[v] = {r, g, b, 1 - OpacitySliderFrame:GetValue()}
                        end
                    end
                    row.square.color = borderColors[colors[1]]
                end)
            end)
            row.reset = options.style.Button(row)
            row.reset.text = "X"
            row.reset:connect("clicked", function ()
                local color = defaultColors[colors[1]]
                for _, v in ipairs(colors) do
                    borderColors[v] = color
                end
                row.square.color = color
            end)
            row.reset.Layout.alignment = EFrame.Layout.AlignRight
            return row
        end
        
        options.borderColors = EFrame.ColumnLayout(options.main)
        options.borderColors.Layout.alignment = EFrame.Layout.AlignTop
        options.borderColors.spacing = 2
        options.borderColors.caption = EFrame.Label(options.borderColors)
        options.borderColors.caption.text = "Border Colors"
        for _,v in ipairs(
            {{"Casting", {"CURRENT"}},
            {"No Power", {"NOMANA"}},
            {"Not in range", {"NOTINRANGE"}},
            {"Not usable", {"NOTUSABLE"}},
            {"Equipped", {"EQUIPPED"}}}) do
            colorPick(options.borderColors, v[1], v[2])
        end
    end
end

of.refresh = EFrame:makeAtomic(showOptions)
of.OnRefresh = EFrame:makeAtomic(showOptions)
-- of:SetScript("OnShow", function ()
--     showOptions()
-- end)

local function chatcmd(msg)
    if not msg or msg == "" then
        if not InterfaceOptionsFrame_Show then
            Settings.OpenToCategory('ActionMirroringFrame')
        else
            if not options then
                InterfaceOptionsFrame_Show()
            end
            InterfaceOptionsFrame_OpenToCategory("ActionMirroringFrame")
        end
        return
    elseif msg == "unlock" then
        anchor.visible = true
    elseif msg == "lock" then
        anchor.visible = false
    elseif msg == "version" then
        print(format("ActionMirroringFrame: %s (EmeraldFramework: %s)", GetAddOnMetadata(addonName, "version"), EFrame.version or ""))
    else
        print(format("ActionMirroringFrame %s slash commands (/amf):", GetAddOnMetadata(addonName, "version")))
        print("    unlock - allows to move and resize the frame")
        print("    lock - locks the frame in place")
    end
end

_G.SLASH_ACTIONMIRRORINGFRAME1 = "/actionmirroringframe"
_G.SLASH_ACTIONMIRRORINGFRAME2 = "/amf"
_G.SlashCmdList["ACTIONMIRRORINGFRAME"] = chatcmd
