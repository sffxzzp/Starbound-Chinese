require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/rect.lua"
require "/interface/cockpit/cockpitutil.lua"
require "/scripts/quest/messaging.lua"
require("/scripts/replaceTags.lua")

function init()
  local tryUniqueId = config.getParameter("tryUniqueId")
  if entity.uniqueId() ~= tryUniqueId then
    if world.findUniqueEntity(tryUniqueId):result() == nil then
      stagehand.setUniqueId(tryUniqueId)
    else
      stagehand.die()
    end
  end

  self.outbox = Outbox.new("bountyOutbox", ContactList.new("bountyContacts"))

  self.questArc = config.getParameter("questArc")
  self.worldId = config.getParameter("worldId")
  -- when spawned in an instance world we can't deduce the world ID from quest parameters
  self.questId = config.getParameter("questId")

  self.quests = {}
  for _, quest in ipairs(self.questArc.quests) do
    self.quests[quest.questId] = quest
  end

  self.tasks = {}
  table.insert(self.tasks, coroutine.create(keepAlive))

  message.setHandler("participantDied", function(_, _, uniqueId) participantDied(uniqueId) end)
  message.setHandler("involvesQuest", function(_, _, questId) return isQuestOnWorld(questId) end)
  message.setHandler("playerStarted", function(_, _, playerId, questId)
      sb.logInfo("QM: Player %s started %s", playerId, questId)
      playerStarted(playerId, questId)
    end)
  message.setHandler("playerCompleted", function(_, _, playerId, questId)
      sb.logInfo("QM: Player %s completed %s", playerId, questId)
      playerCompleted(playerId, questId)
    end)
  message.setHandler("playerFailed", function(_, _, playerId, questId)
      sb.logInfo("QM: Player %s failed %s", playerId, questId)
      playerFailed(playerId, questId)
    end)
  message.setHandler("interactObject", function(_, _, questId, entityId)
      world.callScriptedEntity(entityId, "object.say", storage.questStorage[questId].dialog[world.entityUniqueId(entityId)])
      for _, playerId in ipairs(storage.questStorage[questId].players) do
        self.outbox:sendMessage(playerId, questId..".participantEvent", world.entityUniqueId(entityId), "objectInteracted")
      end
    end)
  message.setHandler("keypadUnlocked", function(_, _, uniqueId, questId)
      for _, questStore in pairs(storage.questStorage) do
        for _, playerId in ipairs(questStore.players) do
          self.outbox:sendMessage(playerId, questId.."keypadUnlocked", uniqueId, questId)
        end
      end
    end)

  local generator = root.assetJson("/quests/bounty/generator.config")

  self.spawners = {}

  self.questSpawns = {}
  self.questLocations = {}
  self.pendingLocations = self.pendingLocations or {}
  storage.questStorage = storage.questStorage or {}
  storage.tileProtection = storage.tileProtection or {}
  for _,q in pairs(self.questArc.quests) do
    storage.questStorage[q.questId] = storage.questStorage[q.questId] or {
      players = jarray(),
      dialog = {},
      spawned = {},
      locations = {},
    }

    self.questSpawns[q.questId] = {}
    self.questLocations[q.questId] = {}
    self.pendingLocations[q.questId] = {}

    local spawnsParameter = q.parameters.spawns
    if spawnsParameter then
      for spawnName, spawn in pairs(spawnsParameter.spawns) do
        self.questSpawns[q.questId][spawnName] = spawn
      end
    end

    local locationsParameter = q.parameters.locations
    if locationsParameter then
      for locationName, location in pairs(locationsParameter.locations) do
        self.questLocations[q.questId][locationName] = location
      end
    end
  end
end

function update()
  self.keepAlive = false

  for questId, questSpawners in pairs(self.spawners) do
    for spawnName, spawn in pairs(questSpawners) do
      self.keepAlive = true
      local status, result, position = coroutine.resume(spawn.coroutine, spawn.config)
      if not status then
        error(result)
      end
      if result then
        for _, playerId in ipairs(storage.questStorage[questId].players) do
          self.outbox:sendMessage(playerId, questId.."entitySpawned", spawnName, result)
        end

        if spawn.config.type == "npc" and not spawn.config.multiple then
          local role = {
            turnInQuests = {},
            offerQuest = false,
            participateIn = {
              [questId] = true
            },
            stateDeltas = {
              [questId] = {}
            },
            behaviorOverrides = spawn.config.behaviorOverrides or {}
          }

          self.outbox:sendMessage(result, "reserve", entity.uniqueId(), self.questArc, role)
          local questDesc = self.quests[questId]
          for _,playerId in ipairs(storage.questStorage[questId].players) do
            self.outbox:sendMessage(result, "playerStarted", entity.uniqueId(), playerId, questId, questDesc.parameters)
          end
        end
        
        local questStorage = storage.questStorage[spawn.config.questId]
        if spawn.config.questId then
          if not questStorage.spawned[spawn.config.name] then
            questStorage.spawned[spawn.config.name] = result
          end
        end

        if spawn.config.type == "monster" then
          local uuid = questStorage.spawned[spawn.config.name]
          table.insert(self.tasks, coroutine.create(function() return trackEntity(questId, uuid) end))
        end

        if spawn.config.type == "scan" then
          self.outbox:sendMessage(spawn.config.playerId, spawn.config.questId.."scanIds", spawn.config.name, result.uuids)
        end

        self.spawners[questId][spawnName] = nil
      elseif position then
        if not spawn.pendingPosition or world.magnitude(position, spawn.pendingPosition) > 40 then
          spawn.pendingPosition = position
          
          for _,playerId in ipairs(storage.questStorage[questId].players) do
            self.outbox:unreliableMessage(playerId, questId.."entityPending", spawnName, spawn.pendingPosition)
          end
        end
      end
    end
  end

  self.tasks = util.filter(self.tasks, function(task)
      local status, result = coroutine.resume(task)
      if not status then
        error(result)
      end
      return result ~= true
    end)

  -- don't unload while in the process of spawning things
  if self.keepAlive then
    local region = rect.withSize(vec2.sub(entity.position(), {8, 8}), {16, 16})
    world.loadRegion(region)
  end
end

function participantDied(uniqueId)
  sb.logInfo("QM: Participant died: %s", uniqueId)
  for questId, questStore in pairs(storage.questStorage) do
    for name, spawnResult in pairs(questStore.spawned) do
      if type("spawnResult") == "string" and spawnResult == uniqueId then
        for _,playerId in ipairs(storage.questStorage[questId].players) do
          sb.logInfo("QM: Notify %s of %s death", playerId, uniqueId)
          self.outbox:sendMessage(playerId, questId.."entityDied", name, uniqueId)
        end
      end
    end
  end
end

function newDungeonId()
  local newDungeonId = world.getProperty("lastBountyDungeonId")
  local range = config.getParameter("dungeonIdRange")
  if newDungeonId then
    newDungeonId = newDungeonId - 1
  else
    newDungeonId = range[2]
  end

  world.setProperty("lastBountyDungeonId", newDungeonId)
  return newDungeonId
end

function completeQuestParticipants(questId, playerId)
  -- clear out existing entity spawns
  local questStore = storage.questStorage[questId]
  for _, spawnResult in pairs(questStore.spawned) do
    if type(spawnResult) == "string" then
      self.outbox:sendMessage(spawnResult, "playerCompleted", entity.uniqueId(), playerId, questId)
      if #questStore.players == 0 then
        self.outbox:sendMessage(spawnResult, "unreserve", entity.uniqueId(), self.questArc)
      end
    end
    questStore.completed = true
  end
  for _, playerId in ipairs(questStore.players) do
    self.outbox:sendMessage(playerId, questId..".complete")
  end
  questStore.spawned = {}
end

function playerStarted(playerId, questId)
  if not contains(storage.questStorage[questId].players, playerId) then
    table.insert(storage.questStorage[questId].players, playerId)
  end
  if storage.questStorage[questId].completed then
    self.outbox:sendMessage(playerId, questId..".complete")
  elseif storage.questStorage[questId].failed then
    self.outbox:sendMessage(playerId, questId..".fail")
  else
    if storage.questStorage[questId].scanIds then
      for _, playerId in ipairs(storage.questStorage[questId].players) do
        self.outbox:sendMessage(playerId, questId.."scanIds", storage.questStorage[questId].scanIds.name, storage.questStorage[questId].scanIds.uuids)
      end
    end
    startSpawners(playerId, questId)
  end
end

function startSpawners(playerId, questId)
  self.spawners[questId] = self.spawners[questId] or {}
  local hasScanClue = false
  local addScanObjectLocation = nil
  for spawnName, spawnConfig in pairs(self.questSpawns[questId]) do
    spawnConfig.questId = questId
    spawnConfig.name = spawnName
    spawnConfig.playerId = playerId

    -- start spawner from another quest early
    while spawnConfig.type == "otherQuest" do
      local q = util.find(self.questArc.quests, function(q) return q.questId == spawnConfig.quest end)
      local spawnsParameter = q.parameters.spawns

      local newConfig = copy(spawnsParameter.spawns[spawnConfig.spawn])
      newConfig.questId = spawnConfig.quest
      newConfig.name = spawnConfig.spawn
      newConfig.playerId = spawnConfig.playerId
      spawnConfig = newConfig
    end

    local locationConfig = self.questLocations[spawnConfig.questId][spawnConfig.location]
    -- spawns may use locations from the previous step
    while locationConfig.type == "previous" do
      locationConfig = self.questLocations[locationConfig.quest][locationConfig.location]
    end

    local stepWorld = self.quests[questId].parameters.world and coordinateWorldId(self.quests[questId].parameters.world.coordinate)
    local worldId = locationConfig.worldId or stepWorld or self.worldId
    if self.spawners[questId][spawnName] == nil and worldId == self.worldId then
      local spawner
      local questStorage = storage.questStorage[questId]
      if questStorage.spawned[spawnConfig.name] then
        spawner = coroutine.create(function()
            return questStorage.spawned[spawnConfig.name]
          end)
      else
        if spawnConfig.type == "npc" then
          if not spawnConfig.multiple then
            -- spawn for a single clue or bounty npc, add scan objects
            addScanObjectLocation = {
              questId = spawnConfig.questId,
              location = spawnConfig.location
            }
          end
          spawner = coroutine.create(spawnNpc)
        elseif spawnConfig.type == "monster" then
          spawner = coroutine.create(spawnMonster)
        elseif spawnConfig.type == "item" then
          -- spawn for an item clue, add scan objects
          addScanObjectLocation = {
            questId = spawnConfig.questId,
            location = spawnConfig.location
          }
          spawner = coroutine.create(spawnItem)
        elseif spawnConfig.type == "object" then
          -- spawn for an object clue, add scan objects
          addScanObjectLocation = {
            questId = spawnConfig.questId,
            location = spawnConfig.location
          }
          spawner = coroutine.create(spawnObject)
        elseif spawnConfig.type == "keypad" then
          spawner = coroutine.create(setKeypadCode)
        elseif spawnConfig.type == "stagehand" then
          spawner = coroutine.create(spawnStagehand)
        elseif spawnConfig.type == "scan" then
          hasScanClue = true
          spawnConfig.clue = true
          spawner = coroutine.create(spawnScanObject)
        else
          error(string.format("No spawner available for spawn type %s", spawnConfig.type))
        end
      end

      self.spawners[questId][spawnName] = {
        config = spawnConfig,
        coroutine = spawner
      }
    end
  end
  
  -- spawn non-clue scan objects at locations that have another clue
  if not hasScanClue and addScanObjectLocation ~= nil then
    self.spawners[questId]["inertScans"] = {
      config = {
        location = addScanObjectLocation.location,
        questId = addScanObjectLocation.questId,
        name = "inertScans",
        clue = false,
      },
      coroutine = coroutine.create(spawnScanObject)
    }
  end
end

function die()
  sb.logInfo("QM: Die")
  local celestialWorld = worldIdCoordinate(self.worldId) ~= nil
  if celestialWorld then
    -- if this is not a celestial world we don't need to remove tile protection, and the stagehand doesn't need to die
    -- it's better to stay around in case other players are on the same quest
    removeTileProtection()
    stagehand.die()
  end
end

function anyActivePlayers()
  for _, questStore in pairs(storage.questStorage) do
    if #questStore.players > 0 then
      return true
    end
  end
  return false
end

function playerCompleted(playerId, questId)
  sb.logInfo("Player %s completed %s", playerId, questId)
  completeQuestParticipants(questId, playerId)
  storage.questStorage[questId].players = util.filter(storage.questStorage[questId].players, function(p)
      return p ~= playerId
    end)

  if lastQuestOnWorld(questId) and not anyActivePlayers() then
    die()
  end
end

function playerFailed(playerId, questId)
  sb.logInfo("Player %s failed %s", playerId, questId)
  storage.questStorage[questId].players = util.filter(storage.questStorage[questId].players, function(p)
      return p ~= playerId
    end)
  for _, spawnResult in pairs(storage.questStorage[questId].spawned) do
    if type(spawnResult) ~= "table" then
      self.outbox:unreliableMessage(spawnResult, "playerFailed", entity.uniqueId(), playerId, questId)
      if #storage.questStorage[questId].players == 0 then
        self.outbox:unreliableMessage(spawnResult, "unreserve", entity.uniqueId(), self.questArc)
      end
    end
  end
  storage.questStorage[questId].failed = true

  if not anyActivePlayers() then
    die()
  end
end

function isQuestOnWorld(questId)
  sb.logInfo("%s %s", questId, self.questId)
  if questId == self.questId then
    return true
  end
  for _, quest in pairs(self.questArc.quests) do
    if quest.questId == questId then
      local world = quest.parameters.world
      if world and coordinateWorldId(world.coordinate) == self.worldId then
        return true
      end
    end
  end
  return false
end

function lastQuestOnWorld(questId)
  local checkWorld = nil
  for _, quest in pairs(self.questArc.quests) do
    if checkWorld then
      local world = quest.parameters.world
      if compare(checkWorld.coordinate, world and world.coordinate) then
        -- there is a quest ahead that uses the same world, this is not the last quest on this world
        return false
      end
    end
    if quest.questId == questId then
      checkWorld = quest.parameters.world
    end
  end
  return true
end

function keepAlive()
  while true do
    local onQuest = false
    for questId, questStore in pairs(storage.questStorage) do
      for _,playerId in ipairs(questStore.players) do
        local entityId = world.loadUniqueEntity(playerId)
        if entityId ~= nil and world.entityExists(entityId) then
          local onQuest = util.await(world.sendEntityMessage(playerId, questId.."keepAlive")):succeeded()
          if contains(questStore.players, playerId) and not onQuest then
            -- the player is on the world but no longer on this quest, the player must have abandoned or failed the quest
            playerFailed(playerId, questId)
          end
        end
      end
    end

    util.wait(1.0)
  end
end

function selectDungeons(dungeonType, tags, biome)
  local dungeons = root.assetJson("/quests/bounty/dungeons.config")
  local pool = dungeons.biomePools[biome] or dungeons.biomePools.default
  pool = util.filter(pool, function(name)
    local dungeonConfig = dungeons.dungeons[name]
    if dungeonConfig.type ~= dungeonType then
      return false
    end
    for _,tag in pairs(tags) do
      if not contains(dungeonConfig.tags, tag) then
        return false
      end
    end
    return true
  end)

  if #pool == 0 then
    return nil
  end

  -- return a list of the valid dungeon configs
  return pool
end

function setTileProtection(dungeonId)
  world.setTileProtection(dungeonId, true)

  sb.logInfo("Protect dungeon id %s", dungeonId)
  table.insert(storage.tileProtection, dungeonId)
end

function removeTileProtection(questId)
  sb.logInfo("Unprotect dungeon ids %s", storage.tileProtection)
  for _, dungeonId in ipairs(storage.tileProtection) do
    world.setTileProtection(dungeonId, false)
  end
  storage.tileProtection = {}
end

function spawnDungeon(locationConfig)
  local position
  local tries = 0

  local spawnedDungeon
  local spawnPosition

  local placements = {}

  local surfaceDungeons = selectDungeons("surface", locationConfig.tags, locationConfig.biome)
  table.insert(placements, {
        mode = "floor",
        priority = -10.0,
        variants = 1,
        distribution = "/biomes/distributions.config:mainBiomeMicrodungeon",

        type = "microdungeon",
        microdungeons = surfaceDungeons
  })

  local oceanDungeons = selectDungeons("ocean", locationConfig.tags, locationConfig.biome)
  if oceanDungeons then
    table.insert(placements, {
          mode = "ocean",
          priority = -10.0,
          variants = 1,
          distribution = "/biomes/distributions.config:mainBiomeMicrodungeon",

          type = "microdungeon",
          microdungeons = oceanDungeons
    })
  end

  local dungeonId = newDungeonId()
  local place = world.enqueuePlacement(placements, dungeonId);
  while not place:finished() do
    coroutine.yield()
  end
  local spawnPosition = place:result()
  if spawnPosition then
    sb.logInfo("placed bounty dungeon at %s", spawnPosition)
    setTileProtection(dungeonId)
    return spawnPosition
  else
    error(string.format("Unable to place bounty dungeon '%s'", spawnedDungeon))
  end
end

function getLocationPositions(questId, locationName)
  sb.logInfo("Get location %s %s", questId, locationName)
  local locationConfig = self.questLocations[questId][locationName]
  while locationConfig.type == "previous" do
    questId = locationConfig.quest
    locationName = locationConfig.location
    locationConfig = self.questLocations[questId][locationName]
  end

  if storage.questStorage[questId].locations[locationName] then
    return shuffled(storage.questStorage[questId].locations[locationName])
  end

  if self.pendingLocations[questId][locationName] == nil then
    -- location is not currently being created, mark it as being currently created
    self.pendingLocations[questId][locationName] = false

    sb.logInfo("Create location %s %s %s", questId, locationName, locationConfig.type)
    if locationConfig.type == "dungeon" then
      local spawn = coroutine.create(spawnDungeon)
      while true do
        local status, result, position = coroutine.resume(spawn, locationConfig)
        if not status then
          error(result)
        else
          if result then
            storage.questStorage[questId].locations[locationName] = {result}
            self.pendingLocations[questId][locationName] = nil
            break
          elseif position then
            self.pendingLocations[questId][locationName] = position
          end
        end
        coroutine.yield(nil, self.pendingLocations[questId][locationName])
      end
    elseif locationConfig.type == "stagehand" then
      local findStagehand = world.findUniqueEntity(locationConfig.stagehand)

      while not findStagehand:finished() do
        coroutine.yield()
      end

      if not findStagehand:succeeded() then
        local waypoints = world.getProperty("waypoints")
        if waypoints and waypoints[locationConfig.stagehand] then
          storage.questStorage[questId].locations[locationName] = waypoints[locationConfig.stagehand]
        else
          error(string.format("Unable to find position of stagehand '%s'", locationConfig.stagehand))
        end
      else
        storage.questStorage[questId].locations[locationName] = {findStagehand:result()}
      end
    else
      error(string.format("Could not generate location of type '%s'", locationConfig.type))
    end
  end

  -- if the location is being created by another coroutine, wait until the
  -- position has been set
  while not storage.questStorage[questId].locations[locationName] do
    coroutine.yield(nil, self.pendingLocations[questId][locationName])
  end

  return shuffled(storage.questStorage[questId].locations[locationName])
end

function spawnStagehand(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)
  world.spawnStagehand(positions[1], "waypoint", {uniqueId = spawnConfig.stagehandUniqueId})

  return spawnConfig.stagehandUniqueId
end

function spawnMonster(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)

  local stagehands = {}
  local stagehandType = spawnConfig.stagehand or "monsterspawn"
  for _, position in ipairs(positions) do
    local region = rect.withSize(vec2.sub(position, {32, 32}), {64, 64})
    while not world.regionActive(region) do
      world.loadRegion(region)
      coroutine.yield()
    end
    local near = world.entityQuery(rect.ll(region), rect.ur(region), { includedTypes = {"stagehand"} })
    near = util.filter(near, function(entityId)
        return world.entityName(entityId) == stagehandType
      end)
    for _, entityId in ipairs(near) do
      stagehands[entityId] = true
    end
  end
  stagehands = util.keys(stagehands)
  if #stagehands > 0 then
    position = world.entityPosition(util.randomFromList(stagehands))
  else
    position = util.randomFromList(positions)
  end

  local uniqueId = sb.makeUuid()
  local parameters = copy(spawnConfig.monster.parameters)
  parameters.persistent = true
  parameters.level = spawnConfig.monster.level or world.threatLevel()
  parameters.elite = true
  parameters.aggressive = true

  -- TEMPORARY: Spawn monster above surface
  position = vec2.add(position, {0, 3.0})
  local monsterId = world.spawnMonster(spawnConfig.monster.monsterType, position, parameters)
  world.setUniqueId(monsterId, uniqueId)

  return uniqueId
end

function trackEntity(questId, uniqueId)
  -- It can take one tick to set the unique ID of an entity
  -- Yield once before starting to track
  coroutine.yield()
  while true do
    self.keepAlive = true
    local findMonster = world.findUniqueEntity(uniqueId)
    while not findMonster:finished() do
      coroutine.yield()
    end
    if not findMonster:succeeded() then
      participantDied(uniqueId)
      return true
    end
    util.wait(0.5)
  end
end

function spawnNpc(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)

  -- check for npcspawn stagehands
  local uniqueIds = {}
  local stagehands = {}
  local stagehandType = spawnConfig.stagehand or "npcspawn"
  for _, position in ipairs(positions) do
    local region = rect.withSize(vec2.sub(position, {32, 32}), {64, 64})
    while not world.regionActive(region) do
      world.loadRegion(region)
      coroutine.yield()
    end
    local near = world.entityQuery(rect.ll(region), rect.ur(region), { includedTypes = {"stagehand"} })
    near = util.filter(near, function(entityId)
        return world.entityName(entityId) == stagehandType
      end)
    for _, entityId in ipairs(near) do
      stagehands[entityId] = true
    end
  end

  stagehands = shuffled(util.keys(stagehands))
  if #stagehands > 0 then
    positions = util.map(stagehands, world.entityPosition)
  end
  for _, position in ipairs(positions) do
    local uniqueId = sb.makeUuid()
    local parameters = spawnConfig.npc.parameters
    parameters.scriptConfig = parameters.scriptConfig or {}
    parameters.scriptConfig.uniqueId = uniqueId
    world.spawnNpc(position, spawnConfig.npc.species, spawnConfig.npc.typeName, spawnConfig.npc.level or world.threatLevel(), spawnConfig.npc.seed, parameters)

    if not spawnConfig.multiple then
      -- single npc spawn, return unique ID
      return uniqueId
    end
  end

  -- return average position of all spawns
  return vec2.div(util.fold(positions, {0, 0}, vec2.add), #positions)
end

function spawnItem(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)

  for _, position in ipairs(positions) do
    local region = rect.withSize(vec2.sub(position, {32, 32}), {64, 64})
    while not world.regionActive(region) do
      world.loadRegion(region)
      coroutine.yield()
    end

    local regions = {region}
    if spawnConfig.stagehand then
      regions = {}
      local stagehands = world.entityQuery(rect.ll(region), rect.ur(region), {includedTypes = {"stagehand"}})
      stagehands = util.filter(stagehands, function(entityId)
          return world.entityName(entityId) == spawnConfig.stagehand
        end)

      for _, stagehandId in pairs(stagehands) do
        local broadcastArea = world.sendEntityMessage(stagehandId, "broadcastArea")
        while not broadcastArea:finished() do
          coroutine.yield()
        end
        table.insert(regions, rect.translate(broadcastArea:result(), world.entityPosition(stagehandId)))
      end
    end

    while not util.all(regions, world.regionActive) do
      util.each(regions, world.loadRegion)
      coroutine.yield()
    end

    local objects = {}
    for _,region in pairs(regions) do
      local newObjects = world.entityQuery(rect.ll(region), rect.ur(region), {includedTypes = {"object"}})
      newObjects = util.filter(newObjects, function(entityId)
        return world.containerSize(entityId) ~= nil
      end)
      util.appendLists(objects, newObjects)
    end
    local container = util.randomFromList(objects)
    world.containerAddItems(container, spawnConfig.item)

    return position
  end
end

-- somewhat of a misnomer, doesn't actually place an object
-- instead queries for clue objects and assigns one as the goal
function spawnObject(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)

  local clueConfigs = root.assetJson("/quests/bounty/clue_objects.config")

  local stagehands = {}
  for _, position in ipairs(positions) do
    local region = rect.withSize(vec2.sub(position, {32, 32}), {64, 64})
    while not world.regionActive(region) do
      world.loadRegion(region)
      coroutine.yield()
    end
    local near = world.entityQuery(rect.ll(region), rect.ur(region), {includedTypes = {"stagehand"}})
    near = util.filter(near, function(entityId)
        return world.entityName(entityId) == "interactobject"
      end)
    for _, entityId in ipairs(near) do
      stagehands[entityId] = true
    end
  end
  stagehands = util.keys(stagehands)

  local objectNames = util.keys(clueConfigs)
  local clueObjects = {}
  for _,stagehandId in ipairs(stagehands) do
    local broadcastArea = world.sendEntityMessage(stagehandId, "broadcastArea")
    while not broadcastArea:finished() do
      coroutine.yield()
    end
    broadcastArea = broadcastArea:result()
    local region = rect.translate(broadcastArea, world.entityPosition(stagehandId))
    local objects = world.entityQuery(rect.ll(region), rect.ur(region), {includedTypes = {"object"}})
    objects = util.filter(objects, function(entityId)
        return contains(objectNames, world.entityName(entityId))
      end)
    clueObjects = util.mergeLists(clueObjects, objects)
  end

  if #clueObjects == 0 then
    error("No viable clue objects found")
  end
  local clue = util.randomFromList(clueObjects)
  local uniqueId = sb.makeUuid()
  world.setUniqueId(clue, uniqueId)

  local clueConfig = clueConfigs[world.entityName(clue)][spawnConfig.clueType]
  if clueConfig then
    local tags = util.generateTextTags(self.quests[spawnConfig.questId].parameters.text.tags)
    --storage.questStorage[spawnConfig.questId].dialog[uniqueId] = sb.replaceTags(clueConfig.dialog, tags)
    storage.questStorage[spawnConfig.questId].dialog[uniqueId] = sb_replaceTags(clueConfig.dialog, tags)
    if clueConfig.message then
      for _,playerId in ipairs(storage.questStorage[spawnConfig.questId].players) do
        --self.outbox:sendMessage(playerId, spawnConfig.questId.."setCompleteMessage", sb.replaceTags(clueConfig.message, tags))
        self.outbox:sendMessage(playerId, spawnConfig.questId.."setCompleteMessage", sb_replaceTags(clueConfig.message, tags))
      end
    end
  end

  return uniqueId
end

function spawnScanObject(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)

  local clueConfigs = root.assetJson("/quests/bounty/clue_scans.config")

  local stagehands = {}
  for _, position in ipairs(positions) do
    local region = rect.withSize(vec2.sub(position, {32, 32}), {64, 64})
    while not world.regionActive(region) do
      world.loadRegion(region)
      coroutine.yield()
    end
    local near = world.entityQuery(rect.ll(region), rect.ur(region), {includedTypes = {"stagehand"}})
    near = util.filter(near, function(entityId)
        return world.entityName(entityId) == "scanclue"
      end)
    for _, entityId in ipairs(near) do
      stagehands[entityId] = true
    end
  end
  stagehands = util.keys(stagehands)
  if spawnConfig.clue and #stagehands == 0 then
    error("no scanclue stagehands found")
  end

  local objectNames = util.keys(clueConfigs)
  local uuids = jarray()

  -- disable tile protection to place objects, then re-enable it again immediately after
  -- this should be synchronous and happen within the same frame
  -- still hugely hacky
  local celestialWorld = worldIdCoordinate(self.worldId) ~= nil
  if celestialWorld then
    for _, dungeonId in ipairs(storage.tileProtection) do
      world.setTileProtection(dungeonId, false)
    end
  else
    world.setTileProtection(0, false)
  end
  for i,stagehandId in ipairs(stagehands) do
    local uuid = sb.makeUuid();
    local objectName = util.randomFromList(objectNames)
    local description
    if spawnConfig.clue and i == 1 then
      local clueConfig = clueConfigs[objectName][spawnConfig.clueType]
      description = clueConfig.description
      uuid = spawnConfig.uuid
  
      if clueConfig.message then
        local tags = util.generateTextTags(self.quests[spawnConfig.questId].parameters.text.tags)
        for _,playerId in ipairs(storage.questStorage[spawnConfig.questId].players) do
          --self.outbox:sendMessage(playerId, spawnConfig.questId.."setCompleteMessage", sb.replaceTags(clueConfig.message, tags))
          self.outbox:sendMessage(playerId, spawnConfig.questId.."setCompleteMessage", sb_replaceTags(clueConfig.message, tags))
        end
      end
    end

    local parameters = {
      inspectionLogName = uuid,
      inspectionDescription = description,
    }
    local entityId = world.placeObject(objectName, world.entityPosition(stagehandId), 1, parameters, true)
    if entityId == nil then
      sb.logInfo("Failed to place object %s at %s", objectName, world.entityPosition(stagehandId))
    else
      sb.logInfo("Placed object %s at %s", entityId, world.entityPosition(stagehandId))
    end
    table.insert(uuids, uuid)
  end
  -- re-enable all tile protection after placing objects
  if celestialWorld then
    for _, dungeonId in ipairs(storage.tileProtection) do
      world.setTileProtection(dungeonId, true)
    end
  else
    world.setTileProtection(0, true)
  end

  -- return average position
  return {
    position = vec2.div(util.fold(positions, {0, 0}, vec2.add), #positions),
    uuids = uuids
  }
end

function setKeypadCode(spawnConfig)
  local positions = getLocationPositions(spawnConfig.questId, spawnConfig.location)

  local objects = {}
  for _, position in ipairs(positions) do
    local region = rect.withSize(vec2.sub(position, {32, 32}), {64, 64})
    while not world.regionActive(region) do
      world.loadRegion(region)
      coroutine.yield()
    end

    local near = world.entityQuery(rect.ll(region), rect.ur(region), {includedTypes = {"object"}})
    near = util.filter(near, function(entityId)
        return world.entityName(entityId) == spawnConfig.objectType
      end)
    for _, entityId in ipairs(near) do
      objects[entityId] = true
    end
  end

  objects = util.keys(objects)
  if #objects == 0 then
    error("No viable passwordable objects found")
  end
  for objectId in ipairs(objects) do
    local passwordObject = util.randomFromList(objects)
    local uuid = sb.makeUuid()
    world.setUniqueId(passwordObject, uuid)
    self.outbox:sendMessage(passwordObject, "setKeypadCombination", spawnConfig.password)
    self.outbox:sendMessage(passwordObject, "registerParticipant", spawnConfig.questId, entity.uniqueId())

    return uuid
  end
end