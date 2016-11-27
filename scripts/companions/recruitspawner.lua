require "/scripts/companions/petspawner.lua"
require "/scripts/companions/crewbenefits.lua"
require("/scripts/replaceTags.lua")

Recruit = setmetatable({}, Pet)
Recruit.__index = Recruit

function Recruit.new(...)
  local self = setmetatable({}, Recruit)
  self:init(...)
  return self
end

function Recruit:init(uuid, json)
  Pet.init(self, uuid, json)

  self.rank = json.rank
  self.statusText = json.statusText
  self.uniform = json.uniform
  self.role = root.npcConfig(self.spawnConfig.type).scriptConfig.crew.role
  self.benefits = loadBenefits(self.role.benefits, json.benefits)
  self.hasDied = json.hasDied or false

  self.description = self:buildDescription()

  self.spawner = recruitSpawner
  self.dirtyOnStatusUpdate = false
  self.returnMessage = "recruit.beamOut"
  self.statusRequestMessage = "recruit.status"
end

function Recruit:toJson()
  local json = Pet.toJson(self)
  json.rank = self.rank
  json.statusText = self.statusText
  json.uniform = self.uniform
  json.benefits = self.benefits:store()
  json.hasDied = self.hasDied
  return json
end

function Recruit:sendMessage(...)
  if self.uniqueId and not self.spawning then
    return world.sendEntityMessage(self.uniqueId, ...)
  end
end

function Recruit:setUniform(uniform)
  if compare(self.uniform, uniform) then return end
  if self.uniqueId and not self.spawning then
    self:sendMessage("recruit.setUniform", uniform)
    self.uniform = uniform
  end
end

function Recruit:buildDescription()
  local description = config.getParameter("recruitDescription")
  description = sb_replaceTags(description, {
      name = self.name or "Cannon Fodder",
      role = self.role.name or "Soldier",
      rank = self.rank or "Ensign",
      status = self.statusText or "Slacking off"
    })
  return description
end

function Recruit:npcType()
  return self.spawnConfig.type
end

function Recruit:_scriptConfig(parameters)
  parameters.scriptConfig = parameters.scriptConfig or {}
  return parameters.scriptConfig
end

function Recruit:_spawn(position, parameters)
  self.uniform = nil
  return world.spawnNpc(position, self.spawnConfig.species, self.spawnConfig.type, parameters.level, self.spawnConfig.seed, parameters)
end

function Recruit:fieldBenefits()
  local regeneration = self.benefits:regenerationAmount()
  return { getRegenerationEffect("field", regeneration) }
end

function Recruit:combatBenefits()
  local effects = copy(self.benefits:ephemeralEffects())
  local regeneration = self.benefits:regenerationAmount()
  table.insert(effects, getRegenerationEffect("combat", regeneration))
  return effects
end

function Recruit:update(dt)
  Pet.update(self, dt)
  if self:dead() then
    self.hasDied = true
  elseif self.hasDied and self.uniqueId and not self.spawning then
    self:sendMessage("notify", { type = "respawned", sourceId = entity.id() })
    self.hasDied = false
  end
end

function Recruit:eventFields()
  return {
      recruitSpecies = self.spawnConfig.species,
      recruitType = self.spawnConfig.type,
      recruitRole = self.role.type
    }
end

recruitSpawner = {}

function recruitSpawner:init()
  message.setHandler("recruits.updateRecruit", simpleHandler(bind(recruitSpawner.updateRecruit, self)))

  self.followers = {}
  self.shipCrew = {}
  self.beenOnShip = {}
  self.ownerUuid = nil
  self.tetherUniqueId = nil
  self.levelOverride = nil

  self.uniform = nil

  self.activeCrewLimit = nil
  self.crewLimit = nil
end

function recruitSpawner:eventFields()
  return {
      crewSize = self:crewSize()
    }
end

function recruitSpawner:crewSize()
  return util.tableSize(self.followers) + util.tableSize(self.shipCrew)
end

function recruitSpawner:followerCount()
  return util.tableSize(self.followers)
end

function recruitSpawner:storeCrew()
  local crew = {}
  local followers = util.map(util.tableValues(self.followers), Recruit.toJson)
  local shipCrew = util.map(util.tableValues(self.shipCrew), Recruit.toJson)
  util.appendLists(crew, followers)
  util.appendLists(crew, shipCrew)
  return {
      crew = crew,
      followers = followers,
      shipCrew = shipCrew
    }
end

function recruitSpawner:store()
  return {
      beenOnShip = self.beenOnShip,
      uniform = self.uniform
    }
end

function recruitSpawner:_loadRecruits(recruits)
  local result = {}
  for _,recruitStore in pairs(recruits) do
    local uuid = recruitStore.podUuid
    result[uuid] = Recruit.new(uuid, recruitStore)
  end
  return result
end

function recruitSpawner:load(companions, stored)
  self.followers = self:_loadRecruits(companions.followers or {})
  self.shipCrew = self:_loadRecruits(companions.shipCrew or {})
  self.beenOnShip = stored.beenOnShip or {}
  self.uniform = stored.uniform
  self:markDirty()
end

function recruitSpawner:uninit()
  for uuid, recruit in pairs(self.followers) do
    recruit:despawn()
    recruit.uniqueId = nil
  end
end

function recruitSpawner:markDirty()
  -- Engine-side PlayerCompanions needs updating
  self.dirty = true
end

function recruitSpawner:clearDirty()
  self.dirty = false
end

function recruitSpawner:isDirty()
  return self.dirty
end

function recruitSpawner:forEachCrewMember(func)
  for uuid, recruit in pairs(self.followers) do
    if func(recruit) then
      return
    end
  end
  for uuid, recruit in pairs(self.shipCrew) do
    if func(recruit) then
      return
    end
  end
end

function recruitSpawner:getRecruit(recruitUuid)
  return self.followers[recruitUuid] or self.shipCrew[recruitUuid]
end

-- The effects you get while you're on the ship
function recruitSpawner:getShipPersistentEffects()
  local effects = {}
  local regeneration = 0

  self:forEachCrewMember(function (recruit)
      util.appendLists(effects, recruit.benefits:persistentEffects())
      regeneration = regeneration + recruit.benefits:regenerationAmount()
    end)

  if regeneration > 0 then
    table.insert(effects, getRegenerationEffect("ship", regeneration))
  end

  return effects
end

-- The effects you get as you leave the ship
function recruitSpawner:getShipEphemeralEffects()
  local effects = {}
  self:forEachCrewMember(function (recruit)
      util.appendLists(effects, recruit.benefits:ephemeralEffects())
    end)
  return effects
end

function recruitSpawner:_updateRecruits(recruits, persistentRecruits, dt)
  for uuid, recruit in pairs(recruits) do
    recruit.persistent = persistentRecruits
    recruit:setUniform(self.uniform)
    recruit:update(dt)
  end
end

function recruitSpawner:update(dt)
  self:_updateRecruits(self.followers, false, dt)
end

function recruitSpawner:shipUpdate(dt)
  self:_updateRecruits(self.shipCrew, true, dt)

  local toRespawn = {}
  self:forEachCrewMember(function (recruit)
      if recruit:dead() or (recruit.persistent and not recruit.uniqueId) then
        toRespawn[recruit.podUuid] = recruit
      else
        recruit.benefits:shipUpdate(recruit, dt)
      end
    end)

  for uuid, recruit in pairs(toRespawn) do
    self:respawnRecruit(uuid, recruit)
  end
end

function recruitSpawner:respawnRecruit(uuid, recruit)
  self.followers[uuid] = nil
  self.shipCrew[uuid] = recruit

  recruit.uniqueId = nil
  recruit.status = nil
  recruit.persistent = true
  recruit.storage = recruit.storage or {}
  recruit.storage.followingOwner = false
  recruit.storage.behaviorFollowing = false

  recruit:spawn()
end

function recruitSpawner:updateRecruit(recruitUuid, status, dead)
  local recruit = self:getRecruit(recruitUuid)
  if not recruit then
    sb.logInfo("Cannot update unknown recruit %s", recruitUuid)
    return
  end

  recruit:setStatus(status, dead)
  self:markDirty()
end

function recruitSpawner:canGainFollower(recruitUuid)
  if self.followers[recruitUuid] then
    return true
  end

  if self.activeCrewLimit then
    if self:followerCount() >= self.activeCrewLimit then
      return false
    end
  end

  return true
end

function recruitSpawner:canGainCrew(recruitUuid)
  if self.followers[recruitUuid] or self.shipCrew[recruitUuid] then
    return true
  end

  if self.crewLimit then
    if self:crewSize() >= self.crewLimit() then
      return false
    end
  end

  return true
end

function recruitSpawner:addCrew(recruitUuid, recruitInfo)
  local recruit = Recruit.new(recruitUuid, recruitInfo)
  self.shipCrew[recruitUuid] = recruit

  self:markDirty()
end

function recruitSpawner:recruitFollowing(onShip, recruitUuid, recruitInfo)
  local recruit = Recruit.new(recruitUuid, recruitInfo)
  self.followers[recruitUuid] = recruit

  if onShip then
    self.shipCrew[recruitUuid] = nil
  end

  self:markDirty()
end

function recruitSpawner:recruitUnfollowing(onShip, recruitUuid)
  local recruit = self.followers[recruitUuid] or self.shipCrew[recruitUuid]
  if not recruit then
    sb.logInfo("Cannot update following state of unknown recruit %s", recruitUuid)
    return
  end
  self.followers[recruitUuid] = nil

  if onShip then
    self.shipCrew[recruitUuid] = recruit
  end

  self:markDirty()
end

function recruitSpawner:dismiss(recruitUuid)
  local recruit = self.followers[recruitUuid] or self.shipCrew[recruitUuid]
  if not recruit then
    sb.logInfo("Cannot dismiss unknown recruit %s", recruitUuid)
    return
  end
  if recruit.spawning then return end
  if recruit.uniqueId then
    world.sendEntityMessage(recruit.uniqueId, "recruit.beamOut")
  end
  self.followers[recruitUuid] = nil
  self.shipCrew[recruitUuid] = nil

  self:markDirty()
end
