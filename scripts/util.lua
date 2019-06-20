require("/scripts/replaceTags.lua")

util = {}

--------------------------------------------------------------------------------
function util.blockSensorTest(sensorGroup, direction)
  local reverse = false
  if direction ~= nil then
    reverse = util.toDirection(direction) ~= mcontroller.facingDirection()
  end

  for i, sensor in ipairs(config.getParameter(sensorGroup)) do
    if reverse then
      sensor[1] = -sensor[1]
    end

    if world.pointTileCollision(monster.toAbsolutePosition(sensor), {"Null", "Block", "Dynamic", "Slippery"}) then
      return true
    end
  end

  return false
end

--------------------------------------------------------------------------------
function util.toDirection(value)
  if value < 0 then
    return -1
  else
    return 1
  end
end

--------------------------------------------------------------------------------
function util.clamp(value, min, max)
  return math.max(min, math.min(value, max))
end

function util.wrap(value, min, max)
  if value > max then
    return min
  end
  if value < min then
    return max
  end
  return value
end

--------------------------------------------------------------------------------
function util.angleDiff(from, to)
  return ((((to - from) % (2*math.pi)) + (3*math.pi)) % (2*math.pi)) - math.pi
end

--------------------------------------------------------------------------------
function util.round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

--------------------------------------------------------------------------------
function util.incWrap(value, max)
  if value >= max then
    return 1
  else
    return value + 1
  end
end

--------------------------------------------------------------------------------
function util.wrapAngle(angle)
  while angle >= 2 * math.pi do
    angle = angle - 2 * math.pi
  end

  while angle < 0 do
    angle = angle + 2 * math.pi
  end

  return angle
end

--------------------------------------------------------------------------------
function util.boundBox(poly)
  local min = {}
  local max = {}
  for _,vertex in ipairs(poly) do
    if not min[1] or vertex[1] < min[1] then
      min[1] = vertex[1]
    end
    if not min[2] or vertex[2] < min[2] then
      min[2] = vertex[2]
    end
    if not max[1] or vertex[1] > max[1] then
      max[1] = vertex[1]
    end
    if not max[2] or vertex[2] > max[2] then
      max[2] = vertex[2]
    end
  end
  if not min[1] or not min[2] or not max[1] or not max[2] then
    return {0, 0, 0, 0}
  end
  return {min[1], min[2], max[1], max[2]}
end

function util.tileCenter(pos)
  return {math.floor(pos[1]) + 0.5, math.floor(pos[2]) + 0.5}
end

--------------------------------------------------------------------------------
function util.filter(t, predicate)
  local newTable = {}
  for _,value in ipairs(t) do
    if predicate(value) then
      newTable[#newTable+1] = value
    end
  end
  return newTable
end

function util.find(t, predicate, index)
  if index == nil then index = 1 end
  local current = 0
  for i,value in ipairs(t) do
    if predicate(value) then
      current = current + 1
      if current == index then return value, i end
    end
  end
end

function util.all(t, predicate)
  for _,v in ipairs(t) do
    if not predicate(v) then
      return false
    end
  end
  return true
end

function util.each(t, func)
  for k,v in pairs(t) do
    func(k,v)
  end
end

function util.values(t)
  local vals = {}
  for _, v in pairs(t) do
    table.insert(vals, v)
  end
  return vals
end

function util.keys(t)
  local keys = {}
  for k,_ in pairs(t) do
    table.insert(keys, k)
  end
  return keys
end

function util.orderedKeys(t)
  local keys = util.keys(t)
  table.sort(keys)
  return keys
end

function util.rep(f, n)
  local values = {}
  for i = 1, n do
    values[i] = f()
  end
  return values
end

function util.map(t, func, newTable)
  newTable = newTable or {}
  for k,v in pairs(t) do
    newTable[k] = func(v)
  end
  return newTable
end

function util.count(t,value)
  local count = 0
  for _,v in pairs(t) do
    if v == value then count = count + 1 end
  end
  return count
end

function util.fold(t, a, func)
  for _,v in pairs(t) do
    a = func(a, v)
  end
  return a
end

function util.mapWithKeys(t, func, newTable)
  newTable = newTable or {}
  for k,v in pairs(t) do
    newTable[k] = func(k,v)
  end
  return newTable
end

function util.zipWith(tbl1, tbl2, func, newTable)
  newTable = newTable or {}
  for k,_ in pairs(tbl1) do
    newTable[k] = func(tbl1[k], tbl2[k])
  end
  for k,_ in pairs(tbl2) do
    if tbl1[k] == nil then
      newTable[k] = func(tbl1[k], tbl2[k])
    end
  end
  return newTable
end

function util.toList(t)
  local list = {}
  for _,v in pairs(t) do
    table.insert(list, v)
  end
  return list
end

function util.take(n, list)
  local result = {}
  for i,elem in ipairs(list) do
    if i <= n then
      result[i] = elem
    else
      break
    end
  end
  return result
end

function util.takeEnd(list, n)
  local result = {}
  for i = math.max(#list - n + 1, 1), #list do
    table.insert(result, list[i])
  end
  return result
end

--------------------------------------------------------------------------------
function util.trackTarget(distance, switchTargetDistance, keepInSight)
  local targetIdWas = self.targetId

  if self.targetId == nil then
    self.targetId = util.closestValidTarget(distance)
  end

  if switchTargetDistance ~= nil then
    -- Switch to a much closer target if there is one
    local targetId = util.closestValidTarget(switchTargetDistance)
    if targetId ~= 0 and targetId ~= self.targetId then
      self.targetId = targetId
    end
  end

  util.trackExistingTarget(keepInSight)

  return self.targetId ~= targetIdWas and self.targetId ~= nil
end

function util.nearestPosition(positions)
  local bestDistance = nil
  local bestPosition = nil
  for _,position in pairs(positions) do
    local distance = world.magnitude(position, entity.position())
    if not bestDistance or distance < bestDistance then
      bestPosition = position
      bestDistance = distance
    end
  end
  return bestPosition
end

function util.closestValidTarget(range)
  local newTargets = world.entityQuery(entity.position(), range, { includedTypes = {"player", "npc", "monster"}, order = "nearest" })
  local valid = util.find(newTargets, function(targetId) return entity.isValidTarget(targetId) and entity.entityInSight(targetId) end)
  return valid or 0
end

--------------------------------------------------------------------------------
function util.trackExistingTarget(keepInSight)
  if keepInSight == nil then keepInSight = true end

  -- Lose track of the target if they hide (but their last position is retained)
  if self.targetId ~= nil and keepInSight and not entity.entityInSight(self.targetId) then
    self.targetId = nil
  end

  if self.targetId ~= nil then
    self.targetPosition = world.entityPosition(self.targetId)
  end
end

--------------------------------------------------------------------------------
function util.randomDirection()
  return util.toDirection(math.random(0, 1) - 0.5)
end

function util.interval(interval, func, initialInterval)
  local time = initialInterval or interval
  return function(dt)
    time = time - dt
    if time <= 0 then
      time = time + interval
      func()
    end
  end
end

function util.uniqueEntityTracker(uniqueId, interval)
  return coroutine.wrap(function()
    while true do
      local promise = world.findUniqueEntity(uniqueId)
      while not promise:finished() do
        coroutine.yield(false)
      end
      coroutine.yield(promise:result())
      util.wait(interval or 0)
    end
  end)
end

function util.multipleEntityTracker(uniqueIds, interval, choiceCallback)
  choiceCallback = choiceCallback or util.nearestPosition

  local trackers = {}
  for _,uniqueId in pairs(uniqueIds) do
    table.insert(trackers, util.uniqueEntityTracker(uniqueId, interval))
  end

  return coroutine.wrap(function()
      local positions = {}
      while true do
        for i,tracker in pairs(trackers) do
          local position = tracker()
          if position then
            positions[i] = position
          end
        end

        local best = choiceCallback(util.toList(positions))
        coroutine.yield(best)
      end
    end)
end

--------------------------------------------------------------------------------
-- Useful in coroutines to wait for the given duration, optionally performing
-- some action each update
function util.wait(duration, action)
  local timer = duration
  local dt = script.updateDt()
  while timer > 0 do
    if action ~= nil and action(dt) then return end
    timer = timer - dt
    coroutine.yield(false)
  end
end

-- version of util.wait that yields nil instead of false for when you don't
-- want to yield false and instead want to yield nil
function util.run(duration, action, ...)
  local wait = coroutine.create(util.wait)
  while true do
    local status, result = coroutine.resume(wait, duration, action)
    if result ~= false then break end
    coroutine.yield(nil, ...)
  end
end

--------------------------------------------------------------------------------
-- Run coroutines or functions in parallel until at least one coroutine is dead
function util.parallel(...)
  for _,thread in pairs({...}) do
    if type(thread) == "function" then
      thread()
    elseif type(thread) == "thread" then
      if coroutine.status(thread) == "dead" then
        return false
      end
      local status, result = coroutine.resume(thread)
      if not status then error(result) end
    end
  end

  return true
end

-- yields until a promise is finished
function util.await(promise)
  while not promise:finished() do
    coroutine.yield()
  end
  return promise
end

function util.untilNotNil(func)
  local v
  while true do
    v = func()
    if v ~= nil then return v end
    coroutine.yield()
  end
end

function util.untilNotEmpty(func)
  local v
  while true do
    v = func()
    if v ~= nil and #v > 0 then return v end
    coroutine.yield()
  end
end

--------------------------------------------------------------------------------
function util.hashString(str)
  -- FNV-1a algorithm. Simple and fast.
  local hash = 2166136261
  for i = 1, #str do
    hash = hash ~ str:byte(i)
    hash = (hash * 16777619) & 0xffffffff
  end
  return hash
end

--------------------------------------------------------------------------------
function util.isTimeInRange(time, range)
  if range[1] < range[2] then
    return time >= range[1] and time <= range[2]
  else
    return time >= range[1] or time <= range[2]
  end
end

--------------------------------------------------------------------------------
--get the firing angle to hit a target offset with a ballistic projectile
function util.aimVector(targetVector, v, gravityMultiplier, useHighArc)
  local x = targetVector[1]
  local y = targetVector[2]
  local g = gravityMultiplier * world.gravity(mcontroller.position())
  local reverseGravity = false
  if g < 0 then
    reverseGravity = true
    g = -g
    y = -y
  end

  local term1 = v^4 - (g * ((g * x * x) + (2 * y * v * v)))

  if term1 >= 0 then
    local term2 = math.sqrt(term1)
    local divisor = g * x
    local aimAngle = 0

    if divisor ~= 0 then
      if useHighArc then
        aimAngle = math.atan(v * v + term2, divisor)
      else
        aimAngle = math.atan(v * v - term2, divisor)
      end
    end

    if reverseGravity then
      aimAngle = -aimAngle
    end

    return {v * math.cos(aimAngle), v * math.sin(aimAngle)}, true
  else
    --if out of range, normalize to 45 degree angle
    return {(targetVector[1] > 0 and v or -v) * math.cos(math.pi / 4), v * math.sin(math.pi / 4)}, false
  end
end

function util.predictedPosition(target, source, targetVelocity, projectileSpeed)
  local targetVector = world.distance(target, source)
  local bs = projectileSpeed
  local dotVectorVel = vec2.dot(targetVector, targetVelocity)
  local vector2 = vec2.dot(targetVector, targetVector)
  local vel2 = vec2.dot(targetVelocity, targetVelocity)

  --If the answer is a complex number, for the love of god don't continue
  if ((2*dotVectorVel) * (2*dotVectorVel)) - (4 * (vel2 - bs * bs) * vector2) < 0 then
    return target
  end

  local timesToHit = {} --Gets two values from solving quadratic equation
  --Quadratic formula up in dis
  timesToHit[1] = (-2 * dotVectorVel + math.sqrt((2*dotVectorVel) * (2*dotVectorVel) - 4*(vel2 - bs * bs) * vector2)) / (2 * (vel2 - bs * bs))
  timesToHit[2] = (-2 * dotVectorVel - math.sqrt((2*dotVectorVel) * (2*dotVectorVel) - 4*(vel2 - bs * bs) * vector2)) / (2 * (vel2 - bs * bs))

  --Find the nearest lowest positive solution
  local timeToHit = 0
  if timesToHit[1] > 0 and (timesToHit[1] <= timesToHit[2] or timesToHit[2] < 0) then timeToHit = timesToHit[1] end
  if timesToHit[2] > 0 and (timesToHit[2] <= timesToHit[1] or timesToHit[1] < 0) then timeToHit = timesToHit[2] end

  local predictedPos = vec2.add(target, vec2.mul(targetVelocity, timeToHit))
  return predictedPos
end

function util.randomChoice(options)
  return options[math.random(#options)]
end

function util.weightedRandom(options, seed)
  local totalWeight = 0
  for _,pair in ipairs(options) do
    totalWeight = totalWeight + pair[1]
  end

  local choice = (seed and sb.staticRandomDouble(seed) or math.random()) * totalWeight
  for _,pair in ipairs(options) do
    choice = choice - pair[1]
    if choice < 0 then
      return pair[2]
    end
  end
  return nil
end

function generateSeed()
  return sb.makeRandomSource():randu64()
end

function applyDefaults(args, defaults)
  for k,v in pairs(args) do
    defaults[k] = v
  end
  return defaults
end

function extend(base)
  return {
    __index = base
  }
end

--------------------------------------------------------------------------------
function util.absolutePath(directory, path)
  if string.sub(path, 1, 1) == "/" then
    return path
  else
    return directory..path
  end
end

function util.pathDirectory(path)
  local parts = util.split(path, "/")
  local directory = "/"
  for i=1, #parts-1 do
    if parts[i] ~= "" then
      directory = directory..parts[i].."/"
    end
  end
  return directory
end

function util.split(str, sep)
  local parts = {}
  repeat
    local s, e = string.find(str, sep, 1, true)
    if s == nil then break end

    table.insert(parts, string.sub(str, 1, s-1))
    str = string.sub(str, e+1)
  until string.find(str, sep, 1, true) == nil
  table.insert(parts, str)
  return parts
end

--------------------------------------------------------------------------------
-- TODO: distinguish between arrays and objects to match JSON merging behavior
function util.mergeTable(t1, t2)
  for k, v in pairs(t2) do
    if type(v) == "table" and type(t1[k]) == "table" then
      util.mergeTable(t1[k] or {}, v)
    else
      t1[k] = v
    end
  end
  return t1
end

--------------------------------------------------------------------------------
function util.toRadians(degrees)
  return (degrees / 180) * math.pi
end

function util.toDegrees(radians)
  return (radians * 180) / math.pi
end

function util.sum(values)
  local sum = 0
  for _,v in pairs(values) do
    sum = sum + v
  end
  return sum
end
--------------------------------------------------------------------------------
function util.easeInOutQuad(ratio, initial, delta)
  ratio = ratio * 2
  if ratio < 1 then
    return delta / 2 * ratio^2 + initial
  else
    return -delta / 2 * ((ratio - 1) * (ratio - 3) - 1) + initial
  end
end

function util.easeInOutSin(ratio, initial, delta)
  local ratio = ratio * 2
  if ratio < 1 then
    return initial + (math.sin((ratio * math.pi / 2) - (math.pi / 2)) + 1.0) * delta / 2
  else
    return initial + (delta / 2) + (math.sin((ratio - 1) * math.pi / 2) * delta / 2)
  end
end

function util.easeInOutExp(ratio, initial, delta, exp)
  ratio = ratio * 2
  if ratio < 1 then
    return delta / 2 * (ratio ^ exp) + initial
  else
    local r = 1 - (1 - (ratio - 1)) ^ exp
    return initial + (delta / 2) + (r * delta / 2)
  end
end

function util.lerp(ratio, a, b)
  if type(a) == "table" then
    a, b = a[1], a[2]
  end

  return a + (b - a) * ratio
end

function util.interpolateHalfSigmoid(offset, value1, value2)
  local sigmoidFactor = (util.sigmoid(6 * offset) - 0.5) * 2
  return util.lerp(sigmoidFactor, value1, value2)
end

function util.interpolateSigmoid(offset, value1, value2)
  local sigmoidFactor = util.sigmoid(12 * (offset - 0.5))
  return util.lerp(sigmoidFactor, value1, value2)
end

function util.sigmoid(value)
  return 1 / (1 + math.exp(-value));
end

-- Debug functions
function util.setDebug(debug)
  self.debug = debug
end
function util.debugPoint(...) return self.debug and world.debugPoint(...) end
function util.debugLine(...) return self.debug and world.debugLine(...) end
function util.debugText(...) return self.debug and world.debugText(...) end
function util.debugLog(...) return self.debug and sb.logInfo(...) end
function util.debugRect(rect, color)
  if self.debug then
    world.debugLine({rect[1], rect[2]}, {rect[3], rect[2]}, color)
    world.debugLine({rect[3], rect[2]}, {rect[3], rect[4]}, color)
    world.debugLine({rect[3], rect[4]}, {rect[1], rect[4]}, color)
    world.debugLine({rect[1], rect[4]}, {rect[1], rect[2]}, color)
  end
end
function util.debugPoly(poly, color)
  if self.debug then
    local current = poly[1]
    for i = 2, #poly do
      world.debugLine(current, poly[i], color)
      current = poly[i]
    end
    world.debugLine(current, poly[1], color)
  end
end
function util.debugCircle(center, radius, color, sections)
  if self.debug then
    sections = sections or 20
    for i = 1, sections do
      local startAngle = math.pi * 2 / sections * (i-1)
      local endAngle = math.pi * 2 / sections * i
      local startLine = vec2.add(center, {radius * math.cos(startAngle), radius * math.sin(startAngle)})
      local endLine = vec2.add(center, {radius * math.cos(endAngle), radius * math.sin(endAngle)})
      world.debugLine(startLine, endLine, color)
    end
  end
end

-- Config and randomization helpers
function util.randomInRange(numberRange)
  if type(numberRange) == "table" then
    return numberRange[1] + (math.random() * (numberRange[2] - numberRange[1]))
  else
    return numberRange
  end
end

function util.randomIntInRange(numberRange)
  if type(numberRange) == "table" then
    return math.random(numberRange[1], numberRange[2])
  else
    return numberRange
  end
end

function util.randomFromList(list, randomSource)
  if type(list) == "table" then
    if randomSource then
      return list[randomSource:randInt(1, #list)]
    else
      return list[math.random(1,#list)]
    end
  else
    return list
  end
end

function util.mergeLists(first, second)
  local merged = copy(first)
  for _,item in pairs(second) do
    table.insert(merged, item)
  end
  return merged
end

function util.appendLists(first, second)
  for _,item in ipairs(second) do
    table.insert(first, item)
  end
end

function util.tableKeys(tbl)
  local keys = {}
  for key,_ in pairs(tbl) do
    keys[#keys+1] = key
  end
  return keys
end

function util.tableValues(tbl)
  local values = {}
  for _,value in pairs(tbl) do
    values[#values+1] = value
  end
  return values
end

function util.tableSize(tbl)
  local size = 0
  for _,_ in pairs(tbl) do
    size = size + 1
  end
  return size
end

function util.tableWrap(tbl, i)
  return tbl[util.wrap(i, 1, #tbl)]
end

function util.tableToString(tbl)
  local contents = {}
  for k,v in pairs(tbl) do
    local kstr = tostring(k)
    local vstr = tostring(v)
    if type(v) == "table" and (not getmetatable(v) or not getmetatable(v).__tostring) then
      vstr = util.tableToString(v)
    end
    contents[#contents+1] = kstr.." = "..vstr
  end
  return "{ " .. table.concat(contents, ", ") .. " }"
end

function util.stringTags(str)
  local tags = {}
  local tagStart, tagEnd = str:find("<.->")
  while tagStart do
    table.insert(tags, str:sub(tagStart+1, tagEnd-1))
    tagStart, tagEnd = str:find("<.->", tagEnd+1)
  end
  return tags
end

function util.replaceTag(data, tagName, tagValue)
  local tagString = "<"..tagName..">"
  if type(data) == "table" then
    local newData = {}

    for k, v in pairs(data) do
      local newKey = k
      if type(k) == "string" and k:find(tagString) then
        newKey = k:gsub(tagString, tagValue)
      end

      newData[newKey] = util.replaceTag(v, tagName, tagValue)
    end

    return newData
  elseif type(data) == "string" and data:find(tagString) then
    return data:gsub(tagString, tagValue)
  else
    return data
  end
end

function util.generateTextTags(t)
  local tags = {}
  for k,v in pairs(t) do
    if type(v) == "table" then
      for tagName,tag in pairs(util.generateTextTags(v)) do
        tags[k.."."..tagName] = tag
      end
    else
      tags[k] = v
    end
  end
  return tags
end

function util.recReplaceTags(v, tags)
  if type(v) == "table" then
    for k, v2 in pairs(v) do
      v[k] = util.recReplaceTags(v2, tags)
    end
    return v
  elseif type(v) == "string" then
    return sb_replaceTags(v, tags)
  else
    return v
  end
end

function util.seedTime()
  return math.floor((os.time() + (os.clock() % 1)) * 1000)
end

--Table helpers
function copy(v)
  if type(v) ~= "table" then
    return v
  else
    local c = {}
    for k,v in pairs(v) do
      c[k] = copy(v)
    end
    setmetatable(c, getmetatable(v))
    return c
  end
end

function copyArray(t)
  local array = jarray()
  for i,v in ipairs(t) do
    table.insert(array, copy(v))
  end
  return array
end

function compare(t1,t2)
  if t1 == t2 then return true end
  if type(t1) ~= type(t2) then return false end
  if type(t1) ~= "table" then return false end
  for k,v in pairs(t1) do
    if not compare(v, t2[k]) then return false end
  end
  for k,v in pairs(t2) do
    if not compare(v, t1[k]) then return false end
  end
  return true
end

function contains(t, v1)
  for i,v2 in ipairs(t) do
    if compare(v1, v2) then
      return i
    end
  end
  return false
end

function construct(t, ...)
  for _,child in ipairs({...}) do
    t[child] = t[child] or {}
    t = t[child]
  end
end

function path(t, ...)
  for _,child in ipairs({...}) do
    if t[child] == nil then return nil end
    t = t[child]
  end
  return t
end

function jsonPath(t, pathString)
  return path(t, table.unpack(util.split(pathString, ".")))
end

function setPath(t, ...)
  local args = {...}
  sb.logInfo("args are %s", args)
  if #args < 2 then return end

  for i,child in ipairs(args) do
    if i == #args - 1 then
      t[child] = args[#args]
      return
    else
      t[child] = t[child] or {}
      t = t[child]
    end
  end
end

function jsonSetPath(t, pathString, value)
  local argList = util.split(pathString, ".")
  table.insert(argList, value)
  setPath(t, table.unpack(argList))
end

function shuffle(list)
  -- Fisher-Yates shuffle
  if #list < 2 then return end
  for i = #list, 2, -1 do
    local j = math.random(i)
    local tmp = list[j]
    list[j] = list[i]
    list[i] = tmp
  end
end

function shallowCopy(list)
  local result = setmetatable({}, getmetatable(list))
  for k,v in pairs(list) do
    result[k] = v
  end
  return result
end

function shuffled(list)
  local result = shallowCopy(list)
  shuffle(result)
  return result
end

function isEmpty(tbl)
  for _,_ in pairs(tbl) do
    return false
  end
  return true
end

function xor(a,b)
  -- Logical xor
  return (a and not b) or (not a and b)
end

function bind(fun, ...)
  local boundArgs = {...}
  return function(...)
    local args = {}
    util.appendLists(args, boundArgs)
    util.appendLists(args, {...})
    return fun(table.unpack(args))
  end
end

function util.wrapFunction(fun, wrapper)
  return function (...)
      return wrapper(fun, ...)
    end
end

-- The very most basic state machine
-- Allows setting a single coroutine as an active state
FSM = {}
function FSM:new()
  local instance = {}
  setmetatable(instance, { __index = self })
  return instance
end

function FSM:set(state, ...)
  if state == nil then
    self.state = nil
    return
  end
  self.state = coroutine.create(state)
  self:resume(...)
end

function FSM:resume(...)
  local s, r = coroutine.resume(self.state, ...)
  if not s then error(r) end
  return r
end

function FSM:update(dt)
  if self.state then
    return self:resume()
  end
end

-- Very basic and probably not that reliable profiler
Profiler = {}
function Profiler:new()
  local instance = {
    totals = {},
    timers = {},
    ticks = 0
  }
  setmetatable(instance, { __index = self })
  return instance
end

function Profiler:start(key)
  self.timers[key] = os.clock()
end

function Profiler:stop(key)
  if not self.totals[key] then
    self.totals[key] = 0
  end
  if self.timers[key] then
    self.totals[key] = self.totals[key] + (os.clock() - self.timers[key])
    self.timers[key] = nil
  end
end

function Profiler:tick()
  self.ticks = self.ticks + 1
end

function Profiler:dump()
  local profiles = util.keys(self.totals)
  table.sort(profiles, function(a,b) return self.totals[a] > self.totals[b] end)
  sb.logInfo("-- PROFILE --")
  for _,profile in ipairs(profiles) do
    sb.logInfo("[%s] %s", profile, self.totals[profile])
  end
  sb.logInfo("-- END --")
end


-- ControlMap
-- Simple helper for activating named values and clearing them
-- I.e damage sources, physics regions etc
ControlMap = {}
function ControlMap:new(controlValues)
  local instance = {
    controlValues = controlValues,
    activeValues = {}
  }
  setmetatable(instance, { __index = self })
  return instance
end

function ControlMap:contains(name)
  return self.controlValues[name] ~= nil
end

function ControlMap:clear()
  self.activeValues = {}
end

function ControlMap:setActive(name)
  self.activeValues[name] = copy(self.controlValues[name])
end

function ControlMap:add(value)
  table.insert(self.activeValues, value)
end

function ControlMap:values()
  return util.toList(self.activeValues)
end
