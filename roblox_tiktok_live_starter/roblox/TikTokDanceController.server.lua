-- Place this as a Script in ServerScriptService.
-- In ServerStorage, create a StringValue named BridgeKey and set its Value
-- to exactly the same secret as Render's BRIDGE_KEY environment variable.
-- Do not put the secret in a LocalScript or publish it in public source code.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BRIDGE_URL = "https://YOUR-RENDER-SERVICE.onrender.com/next"
local POLL_INTERVAL = 4
local DANCE_DURATION = 30
local ANIMATION_ID = "rbxassetid://507771019"
local STAGE_POSITION = Vector3.new(0, 6, 0)

local keyObject = ServerStorage:WaitForChild("BridgeKey")
assert(keyObject:IsA("StringValue"), "ServerStorage.BridgeKey must be a StringValue")
assert(keyObject.Value ~= "", "ServerStorage.BridgeKey.Value must not be empty")

-- Build a simple stage automatically if one does not already exist.
local function makePart(name, size, position, color, material)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Position = position
    part.Anchored = true
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = Workspace
    return part
end

if not Workspace:FindFirstChild("TikTokDanceStage") then
    local stage = Instance.new("Model")
    stage.Name = "TikTokDanceStage"
    stage.Parent = Workspace

    local platform = makePart(
        "DancePlatform",
        Vector3.new(34, 1, 22),
        Vector3.new(0, 0, 0),
        Color3.fromRGB(35, 35, 55),
        Enum.Material.Neon
    )
    platform.Parent = stage

    makePart("BackWall", Vector3.new(34, 10, 1), Vector3.new(0, 5, -11),
        Color3.fromRGB(110, 35, 180), Enum.Material.Neon).Parent = stage

    for i = -3, 3 do
        makePart("FloorLight" .. tostring(i), Vector3.new(0.35, 0.15, 18),
            Vector3.new(i * 4, 0.58, 0), Color3.fromRGB(0, 220, 255),
            Enum.Material.Neon).Parent = stage
    end

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "PlayerSpawn"
    spawn.Size = Vector3.new(6, 1, 6)
    spawn.Position = Vector3.new(0, 1, 15)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Parent = stage
end

local busy = false

local function spawnDancer(username)
    print("[TikTokBridge] Creating avatar for", username)

    local okId, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)
    if not okId then
        warn("[TikTokBridge] Roblox username not found:", username, userId)
        return
    end

    local okAvatar, avatar = pcall(function()
        return Players:CreateHumanoidModelFromUserIdAsync(userId)
    end)
    if not okAvatar then
        warn("[TikTokBridge] Failed to load avatar:", username, avatar)
        return
    end

    avatar.Name = "TikTokDancer_" .. username
    avatar.Parent = Workspace
    avatar:PivotTo(CFrame.new(STAGE_POSITION + Vector3.new(0, 2, 0)))

    local humanoid = avatar:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[TikTokBridge] Avatar has no Humanoid:", username)
        avatar:Destroy()
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = Instance.new("Animation")
    animation.AnimationId = ANIMATION_ID

    local okTrack, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if not okTrack then
        warn("[TikTokBridge] Animation failed:", track)
        avatar:Destroy()
        animation:Destroy()
        return
    end

    track.Looped = true
    track:Play()
    print("[TikTokBridge] Dancing:", username)

    task.wait(DANCE_DURATION)

    track:Stop()
    avatar:Destroy()
    animation:Destroy()
    print("[TikTokBridge] Dance finished:", username)
end

local function getNextUsername()
    local response = HttpService:RequestAsync({
        Url = BRIDGE_URL,
        Method = "GET",
        Headers = {
            ["X-Bridge-Key"] = keyObject.Value
        }
    })

    if not response.Success then
        warn("[TikTokBridge] Render HTTP error:", response.StatusCode, response.StatusMessage)
        return nil
    end

    local data = HttpService:JSONDecode(response.Body)
    if typeof(data) ~= "table" then
        warn("[TikTokBridge] Invalid JSON response")
        return nil
    end

    if data.username == nil then
        return nil
    end

    if typeof(data.username) ~= "string" then
        warn("[TikTokBridge] Invalid username in response")
        return nil
    end

    return data.username
end

print("[TikTokBridge] Started. Polling Render.")

while true do
    if not busy then
        local ok, username = pcall(getNextUsername)
        if not ok then
            warn("[TikTokBridge] Could not poll Render:", username)
        elseif username then
            busy = true
            task.spawn(function()
                local okSpawn, err = pcall(spawnDancer, username)
                if not okSpawn then
                    warn("[TikTokBridge] Avatar error:", err)
                end
                busy = false
            end)
        end
    end
    task.wait(POLL_INTERVAL)
end
