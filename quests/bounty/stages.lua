require("/scripts/replaceTags.lua")

function playExploreMessage()
  local shouldPlay = config.getParameter("playExploreMessage", false)
  if shouldPlay and quest.isCurrent() and not storage.playedExploreMessage then
    local message = config.getParameter("exploreMessage", "exploreclueplanet")
    player.radioMessage(message)
    storage.playedExploreMessage = true
  end
end

function playApproachMessage(message)
  local shouldPlay = config.getParameter("playApproachMessage", false)
  if shouldPlay and quest.isCurrent() and not storage.playedApproachMessage then
    message = config.getParameter("approachMessage", message)
    player.radioMessage(message)
    storage.playedApproachMessage = true
  end
end

function playBountyMusic()
  local musicTrack = config.getParameter("approachMusic")
  if musicTrack then
    local tracks = jarray()
    table.insert(tracks, musicTrack)
    world.sendEntityMessage(player.id(), "startBountyMusic", {musicTrack})
  end
end

function onQuestWorld()
  return player.worldId() == quest.worldId() and player.serverUuid() == quest.serverUuid()
end

function findWorldStage()
  if questInvolvesWorld() then
    return nextStage()
  end

  local objectiveText = config.getParameter("objectives.findWorldStage")
  local targetWorld = quest.parameters().world.coordinate
  quest.setLocation({system = targetWorld.location, location = {"coordinate", targetWorld}})
  quest.setWorldId(coordinateWorldId(targetWorld))

  quest.setCompassDirection(nil)
  quest.setIndicators({})

  while celestial.planetName(targetWorld) == nil do
    coroutine.yield()
  end
  quest.setObjectiveList({
    {string.format(objectiveText[1], celestial.planetName(targetWorld)), false}
  })

  while player.worldId() ~= quest.worldId() do
    coroutine.yield()
  end

  return nextStage()
end

function findSystemStage()
  local objectiveText = config.getParameter("objectives.findSystemStage")
  local targetWorld = quest.parameters().world.coordinate
  local targetSystem = coordinateSystem(quest.parameters().world.coordinate)
  quest.setLocation({system = targetSystem.location, location = nil})
  quest.setWorldId(nil)

  quest.setCompassDirection(nil)
  quest.setIndicators({})

  while celestial.planetName(targetSystem) == nil do
    coroutine.yield()
  end
  quest.setObjectiveList({
    {string.format(objectiveText[1], celestial.planetName(targetSystem)), false}
  })

  local targetWorldId = coordinateWorldId(targetWorld)
  while player.worldId() ~= targetWorldId and not compare(celestial.currentSystem(), targetSystem) do
    coroutine.yield()
  end

  return nextStage()
end

function killBountyStage()
  local tags = util.generateTextTags(quest.parameters().text.tags)
  local objectiveText = util.map(config.getParameter("objectives.killBountyStage"), function(text)
      return sb_replaceTags(text, tags)
    end)
  quest.setObjectiveList({
    {objectiveText[1], false},
    {objectiveText[2], false}
  })
  quest.setCompassDirection(nil)
  
  while not storage.spawned["bounty"] do
    if not onQuestWorld() then
      return previousStage()
    end

    playExploreMessage()
    coroutine.yield()
  end
  
  playBountyMusic()
  playApproachMessage("approachingbounty")
  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })

  quest.setParameter("bounty", {type = "entity", uniqueId = storage.spawned["bounty"]})
  quest.setIndicators({"bounty"})

  local tracker = util.uniqueEntityTracker(storage.spawned["bounty"])
  local celestialWorld = worldIdCoordinate(player.worldId()) ~= nil
  while not storage.killed["bounty"] and onQuestWorld() do
    local pos = tracker()
    if pos then
      local toClue = world.distance(pos, entity.position())
      if world.magnitude(pos, entity.position()) < 32 then
        local promise = world.sendEntityMessage(storage.spawned["bounty"], "notify", {
          type = "bountyProximity",
          sourceId = entity.id()
        })
        while not promise:finished() do
          coroutine.yield()
        end
        quest.setCompassDirection(nil)
      elseif celestialWorld then
        quest.setCompassDirection(vec2.angle(toClue))
      end
    end
    coroutine.yield()
  end

  if storage.killed["bounty"] then
    if storage.event["escape"] then
      return quest.fail()
    end
    return nextStage()
  else
    return previousStage()
  end
end

function findClueNpcStage()
  local objectiveText = config.getParameter("objectives.findClueNpcStage")

  quest.setObjectiveList({
    {objectiveText[1], false}
  })
  quest.setCompassDirection(nil)

  while not storage.spawned["clue"] and onQuestWorld() do
    playExploreMessage()
    coroutine.yield()
  end
  
  playBountyMusic()
  playApproachMessage("approachingbounty")
  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })

  quest.setParameter("clue", {type = "entity", uniqueId = storage.spawned["clue"]})
  quest.setIndicators({"clue"})

  local tracker = util.uniqueEntityTracker(storage.spawned["clue"])
  local celestialWorld = worldIdCoordinate(player.worldId()) ~= nil
  while true do
    if not onQuestWorld() then
      return previousStage()
    end

    local pos = tracker()
    if pos then
      local toClue = world.distance(pos, entity.position())
      if world.magnitude(toClue) < 32 then
        local promise = world.sendEntityMessage(storage.spawned["clue"], "notify", {
          type = "bountyProximity",
          sourceId = entity.id()
        })
        while not promise:finished() do
          coroutine.yield()
        end
        quest.setCompassDirection(nil)
      elseif celestialWorld then
        quest.setCompassDirection(vec2.angle(toClue))
      end
    end

    if storage.event["clueGiven"] then
      break
    end
    coroutine.yield()
  end
  return nextStage()
end

function findClueObjectStage()
  local objectiveText = config.getParameter("objectives.findClueObjectStage")

  quest.setObjectiveList({
    {objectiveText[1], false}
  })
  quest.setCompassDirection(nil)

  while not storage.spawned["clue"] and onQuestWorld() do
    playExploreMessage()
    coroutine.yield()
  end
  
  playBountyMusic()
  playApproachMessage("approachingclue")
  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })

  self.onInteract = function(entityId)
    if world.entityUniqueId(entityId) ~= storage.spawned["clue"] then
      return
    end

    local name = world.entityName(entityId)
    local clueConfig = root.assetJson("/quests/bounty/clue_objects.config")[name]
    if clueConfig then
      world.sendEntityMessage(quest.questArcDescriptor().stagehandUniqueId, "interactObject", quest.questId(), entityId)
    end
  end

  local tracker = util.uniqueEntityTracker(storage.spawned["clue"])
  local celestialWorld = worldIdCoordinate(player.worldId()) ~= nil
  while not storage.event["objectInteracted"] do
    if not onQuestWorld() then
      return previousStage()
    end

    if celestialWorld then
      local pos = tracker()
      if pos then
        local toClue = world.distance(pos, entity.position())
        local distance = world.magnitude(toClue)
        if distance > 32 then
          quest.setCompassDirection(vec2.angle(toClue))
        else
          quest.setCompassDirection(nil)
        end

    
        quest.setObjectiveList({
          {objectiveText[1], true},
          {objectiveText[2], false}
        })
      end
    end
    coroutine.yield()
  end

  return nextStage()
end

function findClueItemStage()
  local objectiveText = config.getParameter("objectives.findClueItemStage")
  local clueItem = quest.parameters().spawns.spawns.clue.item

  quest.setObjectiveList({
    {objectiveText[1], false}
  })
  quest.setCompassDirection(nil)
  quest.setIndicators({})

  while not storage.spawned["clue"] and onQuestWorld() do
    playExploreMessage()

    if player.worldId() ~= quest.worldId() then
      return previousStage()
    end

    coroutine.yield()
  end
  
  playBountyMusic()
  playApproachMessage("approachingclue")
  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })

  local celestialWorld = worldIdCoordinate(player.worldId()) ~= nil
  while true do
    if celestialWorld then
      local toClue = world.distance(storage.spawned["clue"], entity.position())
      local distance = world.magnitude(toClue)
      if distance > 32 then 
        quest.setCompassDirection(vec2.angle(toClue))
      else
        quest.setCompassDirection(nil)
      end
    end

    if storage.event["foundClue"] then
      return nextStage()
    end
  
    if not onQuestWorld() then
      return previousStage()
    end
    coroutine.yield()
  end
end

function findClueScanStage()
  local objectiveText = config.getParameter("objectives.findClueScanStage")

  quest.setObjectiveList({
    {objectiveText[1], false}
  })
  quest.setCompassDirection(nil)
  quest.setIndicators({})

  while not storage.spawned["clue"] do
    if not onQuestWorld() then
      return previousStage()
    end

    playExploreMessage()
    coroutine.yield()
  end
  
  playBountyMusic()
  playApproachMessage("approachingclue")
  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })
  
  storage.scanObjects = storage.scanObjects or copyArray(storage.spawned["clue"].uuids)
  self.scanClue = quest.parameters().spawns.spawns.clue.uuid

  local celestialWorld = worldIdCoordinate(player.worldId()) ~= nil
  while not storage.event["scannedClue"] do
    if celestialWorld then
      local toClue = world.distance(storage.spawned["clue"].position, entity.position())
      local distance = world.magnitude(toClue)
      if distance > 32 then 
        quest.setCompassDirection(vec2.angle(toClue))
      else
        quest.setCompassDirection(nil)
      end
    end
  
    if player.worldId() ~= quest.worldId() or player.serverUuid() ~= quest.serverUuid() then
      return previousStage()
    end
    coroutine.yield()
  end

  return nextStage()
end

function findSpaceBountyStage()
  local objectiveText = config.getParameter("objectives.findSpaceBountyStage")
  local systemSpawn = quest.parameters().systemSpawn
  local system = coordinateSystem(quest.parameters()["system"].coordinate)

  if not quest.location() or not compare(quest.location().system, system.location) then
    quest.setLocation({system = system.location, location = nil})
    quest.setWorldId(nil)
  end

  quest.setObjectiveList({})
  quest.setCompassDirection(nil)
  quest.setIndicators({})

  while celestial.planetName(system) == nil do
  
    coroutine.yield()
  end
  local objectives = {
    {string.format(objectiveText[1], celestial.planetName(system)), false},
    {objectiveText[2], false},
    {objectiveText[3], false}
  }

  while not onQuestWorld() do
    if self.managerPosition ~= nil then
      -- found the bounty manager for this quest, this is the correct world
      quest.setWorldId(player.worldId())
      return nextStage()
    end

    local inSystem = compare(celestial.currentSystem(), system)
    objectives[1][2] = inSystem

    local questLocation = quest.location()
    if inSystem and celestial.objectPosition(systemSpawn.uuid) == nil then
      celestial.systemSpawnObject(systemSpawn.objectType, nil, systemSpawn.uuid)
      while celestial.objectPosition(systemSpawn.uuid) == nil do
        coroutine.yield()
      end
    end
    quest.setLocation({system = system.location, location = {"object", systemSpawn.uuid}})
    local warpActionWorld = celestial.objectWarpActionWorld(systemSpawn.uuid)
    if warpActionWorld then
      quest.setWorldId(warpActionWorld)
    end

    local atLocation = questLocation and compare(celestial.shipLocation(), questLocation.location)
    objectives[2][2] = (atLocation == true)
    quest.setObjectiveList(objectives)

    coroutine.yield()
  end

  return nextStage()
end

function scanPlanetsStage()
  local world = quest.parameters().world.coordinate
  if coordinateWorldId(world) == player.worldId() then
    return nextStage()
  end

  quest.setIndicators({})
  quest.setCompassDirection(nil)
  quest.setObjectiveList({
    {config.getParameter("objectives.scanPlanetsStage.searching"), false}
  })

  storage.scanned = storage.scanned or {}
  local planets = celestial.children(coordinateSystem(world))
  while #planets == 0 do
    planets = celestial.children(coordinateSystem(world))
    coroutine.yield()
  end

  planets = util.filter(planets, function(p)
    if celestialWrap.planetParameters(p).worldType == "Terrestrial" then
      return true
    end
    for _, m in ipairs(celestialWrap.children(p)) do
      if celestialWrap.planetParameters(m).worldType == "Terrestrial" then
        return true
      end
    end
    return false
  end)

  table.sort(planets, function(a, b) return a.planet < b.planet end)

  local planetWorld = copy(world)
  planetWorld.satellite = 0
  local _, planetIndex = util.find(planets, function(p) return compare(p, planetWorld) end)
  local objectives = util.map(planets, function(p)
    return {string.format(config.getParameter("objectives.scanPlanetsStage.scan"), celestialWrap.planetName(p)), false}
  end)

  while not storage.scanned[planetIndex] do
    if not compare(celestial.currentSystem(), coordinateSystem(world)) then
      return previousStage()
    end

    local location = celestial.shipLocation()
    local orbited
    if location then
      if location[1] == "coordinate" then
        orbited = location[2]
      elseif location[1] == "orbit" then
        orbited = location[2].target
      end
    end

    if quest.isCurrent() then
      for i,v in pairs(planets) do
        if compare(v, orbited) then
          if i == planetIndex then
            return nextStage()
          elseif not storage.scanned[i] then
            local message = {
              messageId = "scan_planets_message",
              unique = false,
              text = string.format(config.getParameter("scanMessage"), celestialWrap.planetName(v))
            }
            player.radioMessage(message)
            storage.scanned[i] = true
          end
        end
      end
    end

    for i,objective in pairs(objectives) do
      if storage.scanned[i] then
        objective[2] = true
      else
        objective[2] = false
      end
    end
    quest.setObjectiveList(objectives)

    coroutine.yield()
  end
end

function missionTeleportStage()
  local missionWorld = quest.parameters().locations.locations.bounty.worldId
  local objectiveText = config.getParameter("objectives.missionTeleportStage")
  quest.setObjectiveList({
    {objectiveText[1], false},
    {objectiveText[2], false}
  })

  if not onQuestWorld() then
    -- proceed to the next stage if the player is on the mission world
    if player.worldId() == missionWorld then
      return nextStage()
    else
      return previousStage()
    end
  end

  -- wait for teleporter to spawn
  while not storage.spawned["teleport"] and onQuestWorld() do
    playExploreMessage()

    coroutine.yield()
  end

  playBountyMusic()
  quest.setParameter("teleport", {type = "entity", uniqueId = storage.spawned["teleport"]})
  quest.setIndicators({"teleport"})
  
  playApproachMessage("approachingclue")
  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })

  -- set up teleport confirmation popup on interaction
  local confirmWarp
  self.onInteract = function(entityId)
    if confirmWarp or world.entityUniqueId(entityId) ~= storage.spawned["teleport"] then
      return
    end

    local warpDialog = config.getParameter("warpDialog")
    confirmWarp = player.confirm(warpDialog)
    return false
  end

  -- locate teleporter and teleport
  local tracker = util.uniqueEntityTracker(storage.spawned["teleport"])
  while onQuestWorld() do
    local pos = tracker()
    if pos then
      local toTeleporter = world.distance(pos, entity.position())
      if world.magnitude(toTeleporter) < 32 then
        quest.setCompassDirection(nil)
      else
        quest.setCompassDirection(vec2.angle(toTeleporter))
      end
    end

    if confirmWarp and confirmWarp:finished() then
      if confirmWarp:result() then
        local warpType = "beam"
        if quest.parameters().warp then
          warpType = quest.parameters().warp.warpType
        end
        local deploy = warpType == "deploy"
        player.warp(missionWorld, warpType, deploy)
        self.onInteract = nil

        -- wait for warp
        -- after warping the quest will reinitialize starting this stage over
        -- at which point the quest will proceed to the next stage
        while true do
          coroutine.yield()
        end
      end
      confirmWarp = nil
    end
    coroutine.yield()
  end

  return previousStage()
end

function missionBountyStage()
  local missionWorld = quest.parameters().locations.locations.bounty.worldId
  quest.setWorldId(missionWorld)

  local tags = util.generateTextTags(quest.parameters().text.tags)
  local objectiveText = util.map(config.getParameter("objectives.missionBountyStage"), function(text)
      return sb_replaceTags(text, tags)
    end)
  quest.setObjectiveList({
    {objectiveText[1], false}
  })

  while not storage.spawned["bounty"] and player.worldId() == missionWorld do
    coroutine.yield()
  end

  quest.setParameter("bounty", {type = "entity", uniqueId = storage.spawned["bounty"]})
  quest.setIndicators({"bounty"})
  quest.setCompassDirection(nil)

  while not storage.killed["bounty"] and player.worldId() == missionWorld do
    coroutine.yield()
  end

  if storage.killed["bounty"] then
    if storage.event["escape"] then
      return quest.fail()
    end
    local flag = quest.parameters().mission.universeFlag
    if flag then
      player.setUniverseFlag(flag)
    end
    return nextStage()
  else
    return previousStage()
  end
end

function tutorialClueStage()
  local objectiveText = config.getParameter("objectives.tutorialClueStage")
  local clueItem = quest.parameters().spawns.spawns.clueItem.item

  quest.setObjectiveList({
    {objectiveText[1], false}
  })
  quest.setCompassDirection(nil)
  quest.setIndicators({})

  while not storage.spawned["clueItem"] or not storage.spawned["clueObject"] or not storage.spawned["clueNpc"] or not storage.spawned["clueScan"] do
    playExploreMessage()
    
    if not onQuestWorld() then
      return previousStage()
    end

    coroutine.yield()
  end

  -- scan clue
  storage.scanObjects = storage.scanObjects or copyArray(storage.spawned["clueScan"].uuids)
  self.scanClue = quest.parameters().spawns.spawns.clueScan.uuid
  
  -- object interaction clue
  self.onInteract = function(entityId)
    if world.entityUniqueId(entityId) ~= storage.spawned["clueObject"] then
      return
    end

    local name = world.entityName(entityId)
    local clueConfig = root.assetJson("/quests/bounty/clue_objects.config")[name]
    if clueConfig then
      world.sendEntityMessage(quest.questArcDescriptor().stagehandUniqueId, "interactObject", quest.questId(), entityId)
    end
  end
  
  playBountyMusic()
  playApproachMessage("approachclue")
  while true do
    local toClue = world.distance(storage.spawned["clueItem"], entity.position())
    local distance = world.magnitude(toClue)
    if distance > 32 then 
      quest.setCompassDirection(vec2.angle(toClue))
    else
      quest.setCompassDirection(nil)
    end

    local findItemStatus = storage.event["foundClue"] or false
    local findObjectStatus = storage.event["objectInteracted"] or false
    local findScanStatus = storage.event["scannedClue"] or false
    local findNpcStatus = storage.event["clueGiven"] or false

    quest.setObjectiveList({
      {objectiveText[2].findNpc, findNpcStatus},
      {objectiveText[2].findItem, findItemStatus},
      {objectiveText[2].findObject, findObjectStatus},
      {objectiveText[2].findScan, findScanStatus}
    })

    if findItemStatus and findObjectStatus and findScanStatus and findNpcStatus then
      return nextStage()
    end

    coroutine.yield()
  end
end

function finalMissionStage()
  local objectiveText = config.getParameter("objectives.finalMissionStage")
  quest.setObjectiveList({
    {objectiveText[1], false},
    {objectiveText[2], false}
  })
  
  if string.find(player.worldId(), "InstanceWorld:cultistmission1") == nil then
    while true do
      coroutine.yield()
    end
  end

  quest.setObjectiveList({
    {objectiveText[1], true},
    {objectiveText[2], false}
  })

  message.setHandler("swansongDead", function(_, _)
      quest.complete()
    end)
  while true do
    coroutine.yield()
  end
end
