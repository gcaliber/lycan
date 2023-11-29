local AM
if ActionMirroringFrame == nil then 
    ActionMirroringFrame = {}
end
AM = ActionMirroringFrame

setmetatable(AM, {__index = getfenv() })
setfenv(1, AM)

EFrame.newClass("TimelineSpell" , EFrame.Rectangle)
ActionMirroringFrameHandler.timeScale = 20
function TimelineSpell:new(parent, action)
    EFrame.Rectangle.new(self, parent)
    self.action = action
    self.mirror = ActionMirroringFrame(self, action)
    self.mirror.anchorBottom = self.top
    self.mirror.anchorHCentre = self.left
    self.mirror.scale = 0.6
    self.height = 20
    self.y = 800
    EFrame.rootFrame.update:connect(self, "update")
    self.color = EFrame.bind(function() return borderColors[self.action.status] or borderColors.HIDE end)
end

function TimelineSpell:update()
    if not self.action.castStart or self.action.status == "HIDE" then return end
    if GetTime() - self.action.castStart > 30 then
        self.action.status = "HIDE"
        return
    end
    local b = self.action.castEnd or GetTime()
    local w = (b - self.action.castStart) * ActionMirroringFrameHandler.timeScale
    w = w > 4 and w or 4
    self:setWidth(w)
    self:setX(1920/2 - (GetTime() - self.action.castStart) * ActionMirroringFrameHandler.timeScale)
end

test = TimelineSpell(nil, Action())
