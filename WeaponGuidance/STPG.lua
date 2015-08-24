-- See Readme in git repository for parameter documentation
-- Globals
TargetBufferSize = 120
AimPointMainframeIndex = 0
NonAimPointMainframeIndices = nil
TTTIterationThreshold = 5
TTTMaxIterations = 4

TargetLists = {
  AA = {
    MainframeIndex = 0,
      MinimumSpeed = 0,
      MaximumSpeed = 350,
      MinimumAltitude = -5,
      MaximumAltitude = 99999,
    MaximumRange = 1000,
    TTT = 2
  }
}

WeaponSystems = {}

-- Sample configuration (Dart AA thumpers)
WeaponSystems[1] = {
    Type = 2,
    TargetList = 'AA',
    Stagger = 0.5,
    MaximumAltitude = 99999,
    MinimumAltitude = -3,
    MaximumRange = 800,
    MinimumRange = 100,
    FiringAngle = 60,
    Speed = 175,
    LaunchDelay = 0.3,
    MinimumConvergenceSpeed = 150,
    ProxRadius = nil,
    TransceiverIndices = 'all',
}

flag = 0

DefaultSecantInterval = function(ttt) return math.min(math.ceil(40*ttt/2), 100) end

-- Target buffers
Targets = {}
Missiles = {}

function NewTarget(I)
  return {
    AimPoints = {},
    Index = 0,
    Wrapped = 0,
    Flag = flag,
  }
end

function Length(vel)
  return math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
end

function UpdateTargets(I)
  -- Find all target locations
  local nmf = I:GetNumberOfMainframes()
  local TargetLocations = {}
  local ami = 0
  if AimPointMainframeIndex < nmf then
    ami = AimPointMainframeIndex
  end
  
  -- Aimpoint locations
  for ti = 0, I:GetNumberOfTargets(ami) do
    local t = I:GetTargetInfo(ami,ti)
    TargetLocations[t.Id] = {t.AimPointPosition}
  end
  
  -- Non-aimpoint locations
  if NonAimPointMainframeIndices then
    for k, mfi in ipairs(NonAimPointMainframeIndices) do
      if mfi < nmf then
        for ti = 0, I:GetNumberOfTargets(mfi) do
          local t = I:GetTargetInfo(mfi,ti)
          if TargetLocations[t.Id] then
            table.insert(TargetLocations[t.Id], t.AimPointPosition)
          end
        end
      end
    end
  end

  -- Find priority targets
  for tli, tl in pairs(TargetLists) do
    local m = 0
    if tl.MainframeIndex < nmf then
      m = tl.MainframeIndex
    end

    -- Find qualifying target
    tl.PresentTarget = nil
    for tInd = 0, I:GetNumberOfTargets(m) - 1 do
       local t = I:GetTargetInfo(m,tInd)
       local speed = Length(t.Velocity)
       local interceptPoint = t.Position + t.Velocity * tl.TTT
       if (speed > tl.MinimumSpeed)
         and (speed < tl.MaximumSpeed)
         and (Length(I:GetConstructPosition() - interceptPoint) < tl.MaximumRange) then
        local found = false
        for k, p in ipairs(TargetLocations[t.Id]) do
          if (p.y > tl.MinimumAltitude) and (p.y < tl.MaximumAltitude) then
            found = true
            break
          end
        end
        if found then
          tl.PresentTarget = t.Id
          if not (Targets[t.Id]) then
            Targets[t.Id] = NewTarget(I)
          end
          break
        end
      end
    end
  end

  -- Cull unused targets
  for i, t in ipairs(Targets) do
    if t.Flag ~= flag then
      Targets[i] = nil
    end
  end
  for i, t in ipairs(Missiles) do
    if t.Flag ~= flag then
      Missiles[i] = nil
    end
  end
  flag = flag+1 % 2

  -- Update target info
  for tInd = 0, I:GetNumberOfTargets(ami) - 1 do
    local t = I:GetTargetInfo(ami, tInd)
    if Targets[t.Id] then
      if not t.Protected then
        Targets[t.Id] = nil
      else
        local tar = Targets[t.Id]

        if tar.Index <= TargetBufferSize then
          tar.Index = tar.Index + 1
        else
          tar.Index = 1
          tar.Wrapped = 1
        end

        tar.Velocity = t.Velocity
        tar[tar.Index] = t.Position
        tar.AimPoints = TargetLocations[t.Id]
      end
    end
  end
end

-- I -> Position -> Time -> Velocity
function PredictVelocity(I, target, interval)
  -- Calculate the interval to use
  if target.Wrapped == 0 then
    interval = target.Index-1
  else
    interval = math.min(interval, TargetBufferSize-1)
  end

  local velocity = target.Velocity
  if interval > 0 then
    -- Use secant approximation to smooth
      local oldPos = target[((target.Index - interval) % TargetBufferSize) + 1]
      velocity = (target[target.Index] - oldPos) * (40 / interval)
   end
   return velocity
end

function FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   -- Calculates a time at which the missiles potential sphere intersects the target's track
   local relativePosition = mPos - tPos
   local distance = Length(relativePosition)
   local targetAngle = I:Maths_AngleBetweenVectors(relativePosition, tVel)
   local targetSpeed = Length(tVel)

   -- Find time to earliest possible convergence point
   local a = targetSpeed^2 - mSpeed^2
   local b = -2 * targetSpeed * distance * math.cos(math.rad(targetAngle))
   local c = distance^2
   local det = math.sqrt(b^2-4*a*c)
   local ttt = distance / minConv

   if det > 0 then
      local root1 = math.min((-b + det)/(2*a), (-b - det)/(2*a))
      local root2 = math.max((-b + det)/(2*a), (-b - det)/(2*a))
      if root1 > 0 then
         ttt = root1
      elseif root2 > 0 then
         ttt = root2
      end
   end
   return ttt
end

function PredictTarget(I, target, mPos, mSpeed, delay, Interval, minConv)
   local tPos = target[target.Index]
   local tVel = target.Velocity
   local aPos = target.AimPoints[1]
   -- Find an initial ttt to find the secant width
   local ttt = FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
   for i = 1, TTTMaxIterations do
     local oldVel = tVel
     tVel = PredictVelocity(I, target, Interval(ttt+delay))
     -- Use the secant velocity to refine the TTT guess
     ttt = FindConvergence(I, tPos, tVel, mPos, mSpeed, delay, minConv)
     if Length(oldVel - tVel) < TTTIterationThreshold then
       break
     end
   end
   return aPos + tVel * (ttt+delay)
end

function Update(I)
  I:ClearLogs()
  UpdateTargets(I, target)

  -- Aim and fire
  for i = 0, I:GetWeaponCount() - 1 do
    local w = I:GetWeaponInfo(i)
    if WeaponSystems[w.WeaponSlot] then
      local ws = WeaponSystems[w.WeaponSlot]
      local tIndex = TargetLists[ws.TargetList].PresentTarget
      if Targets[tIndex] then
        local tPos = PredictTarget(I, Targets[tIndex], w.GlobalPosition, ws.Speed, ws.LaunchDelay,
                                   ws.SecantInterval or DefaultSecantInterval,
                                   ws.MinimumConvergenceSpeed)
        if ws.InheritedMovement then
          tPos = tPos - I:GetVelocityVector() * ws.InheritedMovement
        end
        local vector = tPos - w.GlobalPosition
        vector = vector / Length(vector)
        I:AimWeaponInDirection(i, vector.x, vector.y, vector.z, w.WeaponSlot)

        local angle = I:Maths_AngleBetweenVectors(w.CurrentDirection, vector)
        local isDelayed = (ws.Stagger) and I:GetTime() < (ws.LastFired or 0) + ws.Stagger
        if Length(w.GlobalPosition - tPos) < ws.MaximumRange
           and angle < ws.FiringAngle and not isDelayed then
          local fired = I:FireWeapon(i, w.WeaponSlot)
          if fired then
            ws.LastFired = I:GetTime()
          end
        end
      end
    end
  end

  -- Guide missiles
  for wsi = 0, 5 do
    local ws = WeaponSystems[wsi]
    if ws and ws.TransceiverIndices then
      local indices = {}
      if ws.TransceiverIndices == 'all' then
        indices = {}
        for i = 0, I:GetLuaTransceiverCount() - 1 do
          table.insert(indices, i)
        end
      else
        indices = ws.TransceiverIndices
      end
      for ind, trans in ipairs(indices) do
        if I:GetLuaTransceiverInfo(trans).Valid then
          for mi = 0, I:GetLuaControlledMissileCount(trans) - 1 do
            local mInfo = I:GetLuaControlledMissileInfo(trans, mi)

            if Missiles[mInfo.Id] == nil or Targets[Missiles[mInfo.Id].Target] == nil then
              Missiles[mInfo.Id] = { Target = TargetLists[ws.TargetList].PresentTarget }
            end

            Missiles[mInfo.Id].Flag = flag
            local target = Targets[Missiles[mInfo.Id].Target]
            if target then
              target.Flag = flag

              local proximity = Length(target.AimPoints[1] - mInfo.Position)
              if ws.ProxRadius and proximity < ws.ProxRadius then
                I:DetonateLuaControlledMissile(trans,mi)
              end

              local mSpeed = math.max(Length(mInfo.Velocity), ws.Speed)
              local tPos = PredictTarget(I, target, mInfo.Position, ws.Speed, 0,
                                         ws.SecantInterval or DefaultSecantInterval,
                                         ws.MinimumConvergenceSpeed)
              tPos.y = math.min(ws.MaximumAltitude, math.max(tPos.y, ws.MinimumAltitude))
              I:SetLuaControlledMissileAimPoint(trans, mi, tPos.x, tPos.y,tPos.z)
            end
          end
        end
      end
    end
  end
end
