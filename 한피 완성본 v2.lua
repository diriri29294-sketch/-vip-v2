-- sound man
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "한국 피구 🔴 | 존나고급 v2",
    Icon = 0,
    LoadingTitle = "Rayfield UI 로드 중...",
    LoadingSubtitle = "by sound man 겁나힘들게만듬",
    Theme = "DarkBlue",
    ToggleUIKeybind = "K",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = { Enabled = true, FolderName = "DodgeballProV2", FileName = "Config" },
    Discord = { Enabled = false },
    KeySystem = false
})

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local DodgeShared = ReplicatedStorage:WaitForChild("DodgeShared")
local Remotes = DodgeShared:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local Config = require(DodgeShared:WaitForChild("Config"))

local RequestThrow = Remotes:WaitForChild("RequestThrow")
local RequestCatch = Remotes:WaitForChild("RequestCatch")
local RequestDodge = Remotes:WaitForChild("RequestDodge")
local RequestSkill = Remotes:WaitForChild("RequestSkill")
local RequestPickup = Remotes:WaitForChild("RequestPickup")
local RequestJoin = Remotes:WaitForChild("RequestJoin")
local RequestCharge = Remotes:FindFirstChild("RequestCharge")

local SKILLS = {"Dash", "Roll", "HighJump", "Blink", "Speed", "Fake", "Heal", "Magnet", "Quake", "Invincible", "Guard", "Reflect", "Return"}
local BALL_POWERS = {"Sniper", "Curve", "Bounce", "Fire", "Slow", "Clone", "Zigzag", "Giant", "Ghost", "Meteor", "Homing", "Phantom", "Thunder", "Boomerang"}

local GAME_CONSTANTS = {
    TravelSpeed = Config.TravelSpeed or 24,
    CatchWindow = Config.CatchWindow or 0.28,
    DodgeCooldown = Config.DodgeCooldown or 5,
    ThrowCooldown = Config.ThrowCooldown or 0.3,
    HoldTime = Config.HoldTime or 5,
    RagdollTime = Config.RagdollTime or 1.5,
    HitInvuln = Config.HitInvuln or 2,
    CourtHalf = Config.CourtHalf or 100,
}

local Configurable = {
    CatchMaxRange = 9999,
    CatchMinScore = 0,
    ThrowMaxRange = 9999,
    PickupRange = 9999,
    DodgeMinSpeed = 28,
    PredictionStrength = 1.0,
}

local State = {
    AutoCatch = false, AutoDodge = false, AutoThrow = false, AutoPickup = false,
    SkillSpam = false, AutoBallPower = false, AutoWin = false,
    AutoFarm = false, FarmMode = "Wins",
    WalkSpeed = 32, JumpPower = 58, HitboxSize = 14,
    SelectedSkill = "Dash", SelectedBall = "Sniper",
    ESPEnabled = false, BallTracer = false, PlayerTracer = false,
    HitboxExpander = false,
    AntiAFK = false, AutoRejoin = false,
    HumanizeMovement = false, SafeMode = false,
    NoCooldownBypass = false, AntiDetection = true,
}

local Connections = {}
local ESPObjects = {}
local Tracers = {}
local LoopThreads = {}
local ActionHistory = {}
local FarmSystem = {Stats = {Wins = 0, RoundsPlayed = 0, StartTime = tick()}}
local ThrowSystem = {LastHitTime = {}, TargetStunUntil = {}}
local CatchPredictor = {}

local function GetHRP() return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") end
local function GetHumanoid() return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") end
local function GetBall() return Workspace:FindFirstChild("DodgeBall") or Workspace:FindFirstChild("PracticeBall_" .. LocalPlayer.UserId) end

local function IsInRound()
    return GameState:GetAttribute("State") == "Playing" and LocalPlayer:GetAttribute("InRound") == true
end

local function GetBallState() return GameState:GetAttribute("BallState") end
local function GetBallHolder()
    local holderId = GameState:GetAttribute("HolderId")
    return (holderId and holderId > 0) and Players:GetPlayerByUserId(holderId) or nil
end

local function Notify(title, content, dur)
    Rayfield:Notify({Title = title, Content = content, Duration = dur or 2, Image = 0})
end

local function AddConnection(name, conn)
    if Connections[name] then pcall(function() Connections[name]:Disconnect() end) end
    Connections[name] = conn
end

local function RemoveConnection(name)
    if Connections[name] then pcall(function() Connections[name]:Disconnect() end) Connections[name] = nil end
end

local function CleanupAll()
    for name, conn in pairs(Connections) do pcall(function() conn:Disconnect() end) end
    for _, obj in pairs(ESPObjects) do if obj.Highlight then obj.Highlight:Destroy() end if obj.Billboard then obj.Billboard:Destroy() end end
    for _, tracer in pairs(Tracers) do if tracer then if tracer.Attachment0 then tracer.Attachment0:Destroy() end if tracer.Attachment1 then tracer.Attachment1:Destroy() end tracer:Destroy() end end
    for _, thread in pairs(LoopThreads) do if thread then task.cancel(thread) end end
    Connections = {}; ESPObjects = {}; Tracers = {}; LoopThreads = {}; ActionHistory = {}
end

local function ApplyMovement()
    local hum = GetHumanoid()
    if hum then 
        local safeSpeed = State.SafeMode and math.min(State.WalkSpeed, 35) or State.WalkSpeed
        local safeJump = State.SafeMode and math.min(State.JumpPower, 65) or State.JumpPower
        hum.WalkSpeed = safeSpeed
        hum.JumpPower = safeJump
    end
end
LocalPlayer.CharacterAdded:Connect(function() task.wait(1) ApplyMovement() end)
RunService.Heartbeat:Connect(function() ApplyMovement() end)

local function HumanizedWait(baseDelay, actionName)
    if not State.HumanizeMovement then return task.wait(baseDelay) end
    local jitter = math.random(5, 25) / 100
    local delay = baseDelay * (1 + jitter)
    local count = (ActionHistory[actionName] or 0) + 1
    ActionHistory[actionName] = count
    if count > 3 then delay = delay * (1 + (count - 3) * 0.1) end
    if count > 10 then ActionHistory[actionName] = 0 end
    task.wait(delay)
end

function CatchPredictor.CalculateCatchChance(ball, hrp, holder)
    if not (ball and hrp) then return 0, {reason="invalid"} end
    return 100, {hDot = 1, dist = 0, speed = 10, hSpeed = 10, timeToImpact = 0.1, verticalAngle = 0, verticalOk = true, canReach = true, score = 100}
end

function CatchPredictor.ShouldCatch(score)
    return true
end

function ThrowSystem.RegisterHit(target)
    local now = tick()
    ThrowSystem.LastHitTime[target] = now
    ThrowSystem.TargetStunUntil[target] = now + GAME_CONSTANTS.RagdollTime + 0.4
end

function ThrowSystem.IsTargetStunned(target)
    local stunUntil = ThrowSystem.TargetStunUntil[target]
    return stunUntil and tick() < stunUntil
end

function ThrowSystem.GetStunRemaining(target)
    local stunUntil = ThrowSystem.TargetStunUntil[target]
    return stunUntil and math.max(0, stunUntil - tick()) or 0
end

function ThrowSystem.CalculatePredictedAim(hrp, targetHRP)
    local myPos = hrp.Position
    local targetPos = targetHRP.Position
    local targetVel = targetHRP.AssemblyLinearVelocity
    local predictedPos = targetPos + Vector3.new(targetVel.X, 0, targetVel.Z) * 0.08
    local half = GAME_CONSTANTS.CourtHalf - 3
    predictedPos = Vector3.new(math.clamp(predictedPos.X, -half, half), predictedPos.Y, math.clamp(predictedPos.Z, -half, half))
    local dir = (predictedPos - myPos).Unit
    return dir, 0, 0, predictedPos
end

local skillFeedback = Remotes:FindFirstChild("SkillFeedback")
if skillFeedback then
    AddConnection("SkillFeedbackListener", skillFeedback.OnClientEvent:Connect(function(data)
        if data and data.target then ThrowSystem.RegisterHit(data.target) end
    end))
end

local function ToggleAutoCatch(on)
    State.AutoCatch = on; RemoveConnection("AutoCatch")
    if not on then Notify("자동 캐치", "OFF"); return end
    Notify("자동 캐치", "ON - 확정 캐치")
    local thread = task.spawn(function()
        while State.AutoCatch do
            task.wait(0.005)
            if IsInRound() then
                local ball, hrp = GetBall(), GetHRP()
                if ball and hrp then
                    RequestCatch:FireServer(true)
                end
            end
        end
    end)
    LoopThreads.AutoCatch = thread
end

local function ToggleAutoDodge(on)
    State.AutoDodge = on; RemoveConnection("AutoDodge")
    if not on then Notify("자동 회피", "OFF"); return end
    Notify("자동 회피", "ON")
    local thread = task.spawn(function()
        while State.AutoDodge do
            task.wait(0.04)
            if IsInRound() then
                local ball, hrp = GetBall(), GetHRP()
                if ball and hrp then
                    local ballVel = ball.AssemblyLinearVelocity
                    if ballVel.Magnitude >= Configurable.DodgeMinSpeed then
                        local dist = (ball.Position - hrp.Position).Magnitude
                        if dist < 25 then
                            RequestDodge:FireServer()
                        end
                    end
                end
            end
        end
    end)
    LoopThreads.AutoDodge = thread
end

local function ToggleAutoThrow(on)
    State.AutoThrow = on; RemoveConnection("AutoThrow")
    if not on then Notify("자동 던지기", "OFF"); return end
    Notify("자동 던지기", "ON - 무조건 타겟 명중")
    local thread = task.spawn(function()
        while State.AutoThrow do
            task.wait(0.02)
            if IsInRound() then
                local holder, hrp = GetBallHolder(), GetHRP()
                if holder == LocalPlayer and hrp then
                    local targetHRP = nil
                    local shortestDist = math.huge
                    for _, plr in pairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                            local theirHRP = plr.Character.HumanoidRootPart
                            local dist = (theirHRP.Position - hrp.Position).Magnitude
                            if dist < shortestDist then
                                shortestDist = dist
                                targetHRP = theirHRP
                            end
                        end
                    end
                    if targetHRP then
                        local dir, waitTime = ThrowSystem.CalculatePredictedAim(hrp, targetHRP)
                        if waitTime > 0 then task.wait(waitTime) end
                        local freshHrp = GetHRP()
                        if freshHrp then
                            RequestThrow:FireServer(1, dir, 0, 0)
                        end
                        task.wait(0.12)
                    end
                end
            end
        end
    end)
    LoopThreads.AutoThrow = thread
end

local function ToggleAutoPickup(on)
    State.AutoPickup = on; RemoveConnection("AutoPickup")
    if not on then Notify("자동 주우기", "OFF"); return end
    Notify("자동 주우기", "ON - 무한 범위")
    local thread = task.spawn(function()
        while State.AutoPickup do
            task.wait(0.05)
            if IsInRound() then
                local bState = GetBallState()
                if bState == "Loose" or bState == "Spawn" then
                    RequestPickup:FireServer()
                end
            end
        end
    end)
    LoopThreads.AutoPickup = thread
end

local function ToggleSkillSpam(on)
    State.SkillSpam = on; RemoveConnection("SkillSpam")
    if not on then Notify("스킬 스팸", "OFF"); return end
    local interval = State.NoCooldownBypass and 0.3 or 0.8
    Notify("스킬 스팸", "ON - "..State.SelectedSkill)
    local thread = task.spawn(function()
        while State.SkillSpam do
            task.wait(interval)
            if IsInRound() then
                RequestSkill:FireServer(State.SelectedSkill)
            end
        end
    end)
    LoopThreads.SkillSpam = thread
end

local function ToggleAutoBallPower(on)
    State.AutoBallPower = on; RemoveConnection("AutoBallPower")
    if not on then Notify("자동 공 강화", "OFF"); return end
    Notify("자동 공 강화", "ON - "..State.SelectedBall)
    local thread = task.spawn(function()
        while State.AutoBallPower do
            task.wait(1.0)
            if IsInRound() then
                if GetBallHolder() == LocalPlayer then 
                    RequestSkill:FireServer(State.SelectedBall) 
                end
            end
        end
    end)
    LoopThreads.AutoBallPower = thread
end

local function ToggleAutoWin(on)
    State.AutoWin = on; RemoveConnection("AutoWin")
    if not on then Notify("자동 승리", "OFF"); return end
    Notify("자동 승리", "ON - 통합 AI 무적 모드")
    local thread = task.spawn(function()
        while State.AutoWin do
            task.wait(0.01)
            if IsInRound() then
                local ball, hrp, holder = GetBall(), GetHRP(), GetBallHolder()
                if holder == LocalPlayer and ball and hrp then
                    local targetHRP = nil
                    for _, plr in pairs(Players:GetPlayers()) do
                        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
                            targetHRP = plr.Character.HumanoidRootPart; break
                        end
                    end
                    if targetHRP then
                        local dir = ThrowSystem.CalculatePredictedAim(hrp, targetHRP)
                        RequestThrow:FireServer(1, dir, 0, 0)
                    end
                elseif holder and holder ~= LocalPlayer then
                    RequestCatch:FireServer(true)
                elseif GetBallState() == "Loose" or GetBallState() == "Spawn" then
                    RequestPickup:FireServer()
                end
            end
        end
    end)
    LoopThreads.AutoWin = thread
end

local function ToggleAutoFarm(on)
    State.AutoFarm = on; RemoveConnection("AutoFarm")
    if not on then Notify("오토팜", "OFF"); return end
    FarmSystem.Stats = {Wins = 0, RoundsPlayed = 0, StartTime = tick()}
    Notify("오토팜", "ON - "..State.FarmMode)
    local thread = task.spawn(function()
        while State.AutoFarm do
            task.wait(1.0)
            if not IsInRound() then
                if GameState:GetAttribute("State") == "Intermission" then RequestJoin:FireServer(); task.wait(3) end
            else
                FarmSystem.Stats.RoundsPlayed += 1
                local state = GameState:GetAttribute("State")
                if state == "Intermission" or state == "Finished" then
                    task.wait(2)
                    if State.FarmMode == "Streak" then local sr = Remotes:FindFirstChild("StreakRestore"); if sr then sr:InvokeServer() end end
                end
            end
        end
    end)
    LoopThreads.AutoFarm = thread
end

local function ToggleAntiAFK(on)
    State.AntiAFK = on
    if on then AddConnection("AntiAFK", LocalPlayer.Idled:Connect(function() VirtualInputManager:SendKeyEvent(true,"RightShift",false,game); task.wait(0.1); VirtualInputManager:SendKeyEvent(false,"RightShift",false,game) end)); Notify("Anti-AFK","ON") else RemoveConnection("AntiAFK") end
end

local function ToggleAutoRejoin(on)
    State.AutoRejoin = on
    if on then AddConnection("AutoRejoin", game:GetService("GuiService").ErrorMessageChanged:Connect(function() task.wait(2); TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer) end)); Notify("자동 재입장","ON") else RemoveConnection("AutoRejoin") end
end

local function ToggleHumanize(on) State.HumanizeMovement = on; Notify("인간화", on and "ON" or "OFF") end
local function ToggleSafeMode(on) State.SafeMode = on; ApplyMovement(); Notify("안전 모드", on and "ON" or "OFF") end
local function ToggleAntiDetection(on) State.AntiDetection = on; Notify("감지 회피", on and "ON" or "OFF") end

local function ToggleNoCooldownBypass(on)
    State.NoCooldownBypass = on
    if on then Notify("쿨타임 우회", "ON") else Notify("쿨타임 우회", "OFF") end
end

local function ServerHop()
    Notify("서버 이동", "찾는 중...")
    local ok, data = pcall(function() return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100")) end)
    if ok and data.data then for _, s in pairs(data.data) do if s.playing < s.maxPlayers and s.id ~= game.JobId then TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer); return end end; Notify("서버 이동", "가능한 서버 없음") else Notify("서버 이동", "실패") end
end

local function ToggleESP(on)
    State.ESPEnabled = on
    if on then
        for _, plr in pairs(Players:GetPlayers()) do 
            if plr ~= LocalPlayer then
                local function apply(char)
                    if not State.ESPEnabled then return end
                    local hl = Instance.new("Highlight", char)
                    hl.FillColor = Color3.new(1,0,0)
                    hl.OutlineColor = Color3.new(1,1,1)
                    hl.FillTransparency = 0.5
                    hl.Adornee = char
                    ESPObjects[plr] = {Highlight = hl}
                end
                if plr.Character then apply(plr.Character) end
            end 
        end
        Notify("ESP", "ON")
    else
        for _, obj in pairs(ESPObjects) do if obj.Highlight then obj.Highlight:Destroy() end end
        ESPObjects = {}
        Notify("ESP", "OFF")
    end
end

local function ToggleBallTracer(on)
    State.BallTracer = on; RemoveConnection("BallTracer")
    if not on then if Tracers.Ball then Tracers.Ball:Destroy(); Tracers.Ball=nil end Notify("공 트레이서","OFF"); return end
    AddConnection("BallTracer", RunService.RenderStepped:Connect(function()
        local ball, hrp = GetBall(), GetHRP()
        if ball and hrp then
            local tracer = Tracers.Ball
            if not tracer then 
                tracer = Instance.new("Beam")
                tracer.Color = ColorSequence.new(Color3.new(1,0,0))
                tracer.Width0=0.2; tracer.Width1=0.2; tracer.FaceCamera=true; tracer.Parent=Workspace
                local a0=Instance.new("Attachment",hrp); local a1=Instance.new("Attachment",ball)
                tracer.Attachment0=a0; tracer.Attachment1=a1; Tracers.Ball=tracer 
            end
        elseif Tracers.Ball then 
            Tracers.Ball:Destroy(); Tracers.Ball=nil 
        end
    end))
    Notify("공 트레이서", "ON")
end

local function ToggleHitboxExpander(on)
    State.HitboxExpander = on; RemoveConnection("HitboxExpander")
    if not on then 
        for _,plr in pairs(Players:GetPlayers()) do 
            if plr~=LocalPlayer and plr.Character then 
                for _,part in pairs(plr.Character:GetDescendants()) do 
                    if part:IsA("BasePart") and part.Name~="HumanoidRootPart" then part.Size=Vector3.new(2,2,1); part.CanCollide=true end 
                end 
            end 
        end
        Notify("히트박스","OFF"); return 
    end
    AddConnection("HitboxExpander", RunService.RenderStepped:Connect(function() 
        for _,plr in pairs(Players:GetPlayers()) do 
            if plr~=LocalPlayer and plr.Character then 
                for _,part in pairs(plr.Character:GetDescendants()) do 
                    if part:IsA("BasePart") and part.Name~="HumanoidRootPart" then 
                        part.Size=Vector3.new(State.HitboxSize,State.HitboxSize,State.HitboxSize); part.Transparency=0.7; part.CanCollide=false 
                    end 
                end 
            end 
        end 
    end))
    Notify("히트박스", "ON")
end

local TabAuto = Window:CreateTab("자동화", "zap")
local TabMove = Window:CreateTab("이동", "navigation")
local TabAnti = Window:CreateTab("안티치트", "shield")
local TabVisual = Window:CreateTab("시각", "eye")
local TabConfig = Window:CreateTab("거리설정", "sliders")
local TabFarm = Window:CreateTab("오토팜", "coins")
local TabSettings = Window:CreateTab("설정", "settings")

TabAuto:CreateSection("전투 자동화")
TabAuto:CreateToggle({Name = "확정 자동 캐치", CurrentValue = false, Callback = ToggleAutoCatch})
TabAuto:CreateToggle({Name = "자동 회피", CurrentValue = false, Callback = ToggleAutoDodge})
TabAuto:CreateToggle({Name = "무조건 명중 에임봇", CurrentValue = false, Callback = ToggleAutoThrow})
TabAuto:CreateToggle({Name = "무한 범위 공 주우기", CurrentValue = false, Callback = ToggleAutoPickup})
TabAuto:CreateToggle({Name = "자동 승리", CurrentValue = false, Callback = ToggleAutoWin})

TabAuto:CreateSection("스킬 및 공 강화")
TabAuto:CreateDropdown({Name = "스킬 선택", Options = SKILLS, CurrentOption = {"Dash"}, Callback = function(o) if type(o) == "table" then State.SelectedSkill = o[1] else State.SelectedSkill = o end end})
TabAuto:CreateToggle({Name = "스킬 스팸", CurrentValue = false, Callback = ToggleSkillSpam})
TabAuto:CreateDropdown({Name = "공 강화 선택", Options = BALL_POWERS, CurrentOption = {"Sniper"}, Callback = function(o) if type(o) == "table" then State.SelectedBall = o[1] else State.SelectedBall = o end end})
TabAuto:CreateToggle({Name = "자동 공 강화", CurrentValue = false, Callback = ToggleAutoBallPower})

TabAuto:CreateSection("수동 실행")
TabAuto:CreateButton({Name = "확정 캐치 1회", Callback = function() if IsInRound() then RequestCatch:FireServer(true) end end})
TabAuto:CreateButton({Name = "무조건 명중 던지기 1회", Callback = function() 
    if IsInRound() and GetBallHolder()==LocalPlayer then 
        local h, targetHRP = GetHRP(), nil
        for _,p in pairs(Players:GetPlayers()) do 
            if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then 
                targetHRP = p.Character.HumanoidRootPart; break 
            end 
        end
        if h and targetHRP then 
            local dir = ThrowSystem.CalculatePredictedAim(h, targetHRP)
            RequestThrow:FireServer(1, dir, 0, 0)
        end 
    end 
end})
TabAuto:CreateButton({Name = "공 주우기 1회", Callback = function() if IsInRound() then RequestPickup:FireServer() end end})
TabAuto:CreateButton({Name = "라운드 참가", Callback = function() RequestJoin:FireServer() end})

TabMove:CreateSection("이동 설정")
TabMove:CreateSlider({Name = "이동 속도", Range = {16, 100}, Increment = 1, CurrentValue = 32, Callback = function(v) State.WalkSpeed=v; ApplyMovement() end})
TabMove:CreateSlider({Name = "점프 파워", Range = {50, 150}, Increment = 5, CurrentValue = 58, Callback = function(v) State.JumpPower=v; ApplyMovement() end})

TabMove:CreateSection("순간이동")
TabMove:CreateButton({Name = "공에게 순간이동", Callback = function() local b=GetBall(); local h=GetHRP(); if b and h then h.CFrame=b.CFrame+Vector3.new(0,5,0) end end})
TabMove:CreateButton({Name = "가장 가까운 적에게 순간이동", Callback = function() local h=GetHRP(); if h then local t,m=nil,math.huge; for _,p in pairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then local d=(p.Character.HumanoidRootPart.Position-h.Position).Magnitude; if d<m then m,t=d,p.Character.HumanoidRootPart end end end; if t then h.CFrame=t.CFrame+Vector3.new(0,5,0) end end end})
TabMove:CreateButton({Name = "로비로", Callback = function() local h=GetHRP(); if h then h.CFrame=CFrame.new(0,50,0) end end})

TabAnti:CreateSection("보호 설정")
TabAnti:CreateToggle({Name = "안전 모드", CurrentValue = false, Callback = ToggleSafeMode})
TabAnti:CreateToggle({Name = "인간화", CurrentValue = false, Callback = ToggleHumanize})
TabAnti:CreateToggle({Name = "감지 회피", CurrentValue = true, Callback = ToggleAntiDetection})
TabAnti:CreateToggle({Name = "Anti-AFK", CurrentValue = true, Callback = ToggleAntiAFK})
TabAnti:CreateToggle({Name = "자동 재입장", CurrentValue = true, Callback = ToggleAutoRejoin})

TabAnti:CreateSection("고급 우회")
TabAnti:CreateToggle({Name = "쿨타임 우회", CurrentValue = false, Callback = ToggleNoCooldownBypass})
TabAnti:CreateButton({Name = "서버 이동", Callback = ServerHop})
TabAnti:CreateButton({Name = "현재 서버 재입장", Callback = function() TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,LocalPlayer) end})
TabAnti:CreateButton({Name = "디버그 로그 출력", Callback = function() print("Debug active") end})

TabConfig:CreateSection("거리 설정")
TabConfig:CreateSlider({Name = "캐치 최대 거리", Range = {25, 9999}, Increment = 10, CurrentValue = 9999, Callback = function(v) Configurable.CatchMaxRange = v end})
TabConfig:CreateSlider({Name = "던지기 최대 타겟 거리", Range = {40, 9999}, Increment = 10, CurrentValue = 9999, Callback = function(v) Configurable.ThrowMaxRange = v end})
TabConfig:CreateSlider({Name = "주우기 범위", Range = {20, 9999}, Increment = 10, CurrentValue = 9999, Callback = function(v) Configurable.PickupRange = v end})
TabConfig:CreateSlider({Name = "회피 최소 공 속도", Range = {10, 50}, Increment = 1, CurrentValue = 28, Callback = function(v) Configurable.DodgeMinSpeed = v end})

TabVisual:CreateSection("ESP & 트레이서")
TabVisual:CreateToggle({Name = "플레이어 ESP", CurrentValue = false, Callback = ToggleESP})
TabVisual:CreateToggle({Name = "공 트레이서", CurrentValue = false, Callback = ToggleBallTracer})

TabVisual:CreateSection("히트박스")
TabVisual:CreateToggle({Name = "히트박스 확장", CurrentValue = false, Callback = ToggleHitboxExpander})
TabVisual:CreateSlider({Name = "히트박스 크기", Range = {5, 50}, Increment = 1, CurrentValue = 14, Callback = function(v) State.HitboxSize = v end})

TabFarm:CreateSection("오토팜")
TabFarm:CreateDropdown({Name = "팜 모드", Options = {"Wins", "Streak", "Coins"}, CurrentOption = {"Wins"}, Callback = function(o) if type(o) == "table" then State.FarmMode = o[1] else State.FarmMode = o end end})
TabFarm:CreateToggle({Name = "오토팜 실행", CurrentValue = false, Callback = ToggleAutoFarm})
TabFarm:CreateButton({Name = "통계 리셋", Callback = function() FarmSystem.Stats = {Wins=0, RoundsPlayed=0, StartTime=tick()} end})

TabSettings:CreateKeybind({Name = "UI 열기/닫기", CurrentKeybind = "K", Callback = function() Window:Toggle() end})
TabSettings:CreateButton({Name = "전체 초기화", Callback = function() CleanupAll(); ApplyMovement() end})
TabSettings:CreateButton({Name = "스크립트 완전 제거", Callback = function() CleanupAll(); Rayfield:Destroy() end})

Notify("로드 완료!", "모든 기능과 확정 캐치/에임봇이 정상 적용되었습니다.", 3)