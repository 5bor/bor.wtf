local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local CFG = {
    toggleKey = Enum.KeyCode.F,
    silent = false,
    fov = 120,
    strength = 0.85,
    maxTurnRate = 780,
    smoothing = 11,
    pitchClamp = 78,
    reactionMin = 0.10,
    reactionMax = 0.26,
    switchCooldown = 0.35,
    visibleDelay = 0.09,
    headOffset = 0.12,
    jitterDeg = 0.22,
    fatigueAfter = 3.0,
    fatigueMaxDeg = 1.5,
    deadzoneDeg = 0.05,
    teamCheck = true,
    wallCheck = true,
    onlyWhenFiring = false,
    part = "Head",
    prediction = 0.0,
    noticeTime = 1.3,
    stepName = "CameraUpdateFix",
}

local state = {
    on = true,
    target = nil,
    acquireAt = 0,
    lockStart = 0,
    visibleFor = 0,
    switchedAt = 0,
    seeds = { math.random() * 6.28, math.random() * 6.28, math.random() * 6.28, math.random() * 6.28 },
    offset = Vector3.new(),
    offsetUntil = 0,
}

local function now() return os.clock() end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if Workspace.CurrentCamera then Camera = Workspace.CurrentCamera end
end)

local function notify(text, color)
    if CFG.silent then return end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local old = pg:FindFirstChild("notice_gui")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "notice_gui"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 5

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 0.04)
    lbl.Position = UDim2.fromScale(0, 0.86)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 18
    lbl.TextColor3 = color
    lbl.TextStrokeTransparency = 0.25
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.Text = text
    lbl.Parent = gui
    gui.Parent = pg

    task.delay(CFG.noticeTime * 0.4, function()
        for i = 1, 10 do
            if not gui.Parent then return end
            lbl.TextTransparency = i / 10
            lbl.TextStrokeTransparency = 0.25 + 0.75 * (i / 10)
            task.wait(CFG.noticeTime * 0.06)
        end
        gui:Destroy()
    end)
end

local function getChar(plr)
    local c = plr.Character
    if not c or not c.Parent then return nil end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return c, hum
end

local function getPart(char)
    return char:FindFirstChild(CFG.part) or char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function isVisible(char, part)
    if not CFG.wallCheck then return true end
    rayParams.FilterDescendantsInstances = { char, LocalPlayer.Character }
    local origin = Camera.CFrame.Position
    return Workspace:Raycast(origin, part.Position - origin, rayParams) == nil
end

local function isValid(entry)
    if not entry then return false end
    local char = entry.char
    if not char or not char.Parent then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local part = entry.part
    if not part or not part.Parent then return false end
    return true
end

local function findTarget()
    local best, bestDist = nil, math.huge
    local myTeam = LocalPlayer.Team
    local vp = Camera.ViewportSize
    local centre = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char, hum = getChar(plr)
            local ok = char ~= nil
            if ok and CFG.teamCheck and myTeam ~= nil and plr.Team == myTeam then ok = false end
            if ok then
                local part = getPart(char)
                if part then
                    local screen, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen and screen.Z > 0 then
                        local dist = (Vector2.new(screen.X, screen.Y) - centre).Magnitude
                        if dist <= CFG.fov and dist < bestDist and isVisible(char, part) then
                            best = { char = char, part = part, hum = hum }
                            bestDist = dist
                        end
                    end
                end
            end
        end
    end
    return best
end

local function randInSphere(r)
    local v = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
    if v.Magnitude > 1 then v = v.Unit * math.random() end
    return v * r
end

local function aimPoint(t)
    local part = t.part
    local p = part.Position

    if now() >= state.offsetUntil then
        local scale = 1
        pcall(function() scale = math.max(part.Size.X, part.Size.Y) * 0.5 end)
        state.offset = randInSphere(CFG.headOffset * scale * 0.6)
        state.offsetUntil = now() + 0.4 + math.random() * 0.8
    end

    if CFG.prediction > 0 then
        p = p + part.AssemblyLinearVelocity * CFG.prediction
    end
    return p + state.offset
end

local function fatigueDeg()
    local held = now() - state.lockStart
    if held <= CFG.fatigueAfter then return 0 end
    return math.min(CFG.fatigueMaxDeg, (held - CFG.fatigueAfter) * 0.35)
end

local function jitterCF()
    local t = now()
    local s = state.seeds
    local yaw = math.sin(t * 2.7 + s[1]) * math.sin(t * 0.9 + s[2])
    local pitch = math.sin(t * 1.9 + s[3]) * math.cos(t * 0.7 + s[4])
    return CFrame.fromEulerAnglesYXZ(math.rad(CFG.jitterDeg) * pitch, math.rad(CFG.jitterDeg) * yaw, 0)
end

local function step(dt)
    if not state.on then return end
    if not Camera then return end

    if CFG.onlyWhenFiring then
        local firing = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        if not firing then return end
    end

    if not isValid(state.target) then
        state.target = nil
        state.visibleFor = 0
        state.offsetUntil = 0
        state.switchedAt = now()
    end

    if not state.target then
        if now() - state.switchedAt < CFG.switchCooldown then return end
        local pick = findTarget()
        if not pick then return end
        state.target = pick
        state.acquireAt = now() + CFG.reactionMin + math.random() * (CFG.reactionMax - CFG.reactionMin)
        state.lockStart = now()
        state.visibleFor = 0
        return
    end

    if not isVisible(state.target.char, state.target.part) then
        state.visibleFor = 0
        return
    end
    state.visibleFor = state.visibleFor + dt
    if state.visibleFor < CFG.visibleDelay then return end
    if now() < state.acquireAt then return end

    local camCF = Camera.CFrame
    local from = camCF.Position
    local aim = aimPoint(state.target)

    local fwd = camCF.LookVector
    local toTarget = aim - from
    if toTarget.Magnitude < 0.4 then return end
    toTarget = toTarget.Unit

    local dot = math.clamp(fwd:Dot(toTarget), -1, 1)
    local angle = math.acos(dot)
    if angle < math.rad(CFG.deadzoneDeg) then return end

    local k = 1 - math.exp(-CFG.smoothing * dt)
    local move = math.min(angle * k * CFG.strength, math.rad(CFG.maxTurnRate) * dt)
    local targetAngle = math.min(angle, move)

    local axis = fwd:Cross(toTarget)
    if axis.Magnitude < 1e-6 then return end
    axis = axis.Unit

    local fat = fatigueDeg()
    if fat > 0 then
        local t = now()
        local yaw = math.sin(t * 1.3 + state.seeds[1]) * math.rad(fat)
        local pitch = math.cos(t * 0.9 + state.seeds[3]) * math.rad(fat * 0.6)
        targetAngle = math.max(0, targetAngle - math.rad(fat) * 0.2)
        axis = (CFrame.fromEulerAnglesYXZ(pitch, yaw, 0) * axis).Unit
    end

    local rotated = (CFrame.fromAxisAngle(axis, targetAngle) * fwd)
    local look = (jitterCF() * rotated).Unit

    local pitchDeg = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
    if math.abs(pitchDeg) > CFG.pitchClamp then
        local clamped = math.rad(CFG.pitchClamp * (pitchDeg < 0 and -1 or 1))
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude < 1e-4 then return end
        flat = flat.Unit * math.cos(clamped)
        look = (flat + Vector3.new(0, math.sin(clamped), 0)).Unit
    end

    if look.Magnitude < 0.5 then return end
    Camera.CFrame = CFrame.lookAt(from, from + look, Vector3.yAxis)
end

local function safeStep(dt)
    local ok = pcall(step, dt)
    if not ok then state.target = nil end
end

pcall(function() RunService:UnbindFromRenderStep(CFG.stepName) end)
RunService:BindToRenderStep(CFG.stepName, Enum.RenderPriority.Camera.Value + 1, safeStep)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == CFG.toggleKey then
        state.on = not state.on
        state.target = nil
        state.visibleFor = 0
        if state.on then
            notify("headlock on", Color3.fromRGB(90, 230, 120))
        else
            notify("headlock off", Color3.fromRGB(240, 80, 80))
        end
    end
end)

notify("headlock on", Color3.fromRGB(90, 230, 120))
