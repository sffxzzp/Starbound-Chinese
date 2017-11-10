require "/scripts/statusText.lua"
require "/scripts/companions/util.lua"
require "/scripts/messageutil.lua"
require("/scripts/replaceTags.lua")

-- Functions for NPCs that can be 'recruited' by the player and follow them
-- between worlds.
recruitable = {
    defaultDamageTeam = {
        type = "friendly",
        team = 0
      }
  }

function recruitable.init()
  message.setHandler("recruit.beamOut", simpleHandler(recruitable.beamOut))
  message.setHandler("recruit.status", simpleHandler(recruitable.updateStatus))
  message.setHandler("recruit.confirmRecruitment", simpleHandler(recruitable.confirmRecruitment))
  message.setHandler("recruit.declineRecruitment", simpleHandler(recruitable.declineRecruitment))
  message.setHandler("recruit.confirmFollow", simpleHandler(recruitable.confirmFollow))
  message.setHandler("recruit.confirmUnfollow", simpleHandler(recruitable.confirmUnfollow))
  message.setHandler("recruit.confirmUnfollowBehavior", simpleHandler(recruitable.confirmUnfollowBehavior))
  message.setHandler("recruit.setUniform", simpleHandler(recruitable.setUniform))
  message.setHandler("recruit.interactBehavior", simpleHandler(setInteracted))

  local initialStatus = config.getParameter("initialStatus")
  if initialStatus then
    setCurrentStatus(initialStatus, "crew")
  end

  local personality = config.getParameter("personality")
  if personality then
    setPersonality(personality)
  end

  if storage.followingOwner == nil then
    storage.followingOwner = true
  end
  if storage.behaviorFollowing == nil then
    storage.behaviorFollowing = true
  end

  if recruitable.ownerUuid() or recruitable.isRecruitable() then
    recruitable.setUniform(storage.crewUniform or config.getParameter("crew.uniform"))
  end

  if recruitable.ownerUuid() then
    if not storage.beamedIn then
      status.addEphemeralEffect("beamin")
      storage.beamedIn = true
    end
    if storage.followingOwner then
      recruitable.confirmFollow(true)
    else
      recruitable.confirmUnfollow(true)
    end
  end
end

function recruitable.update(dt)
  promises:update()

  if recruitable.ownerUuid() and not entity.uniqueId() then
    world.setUniqueId(entity.id(), sb.makeUuid())
  end

  if recruitable.despawnTimer then
    recruitable.despawnTimer = recruitable.despawnTimer - dt
    if recruitable.despawnTimer <= 0 then
      recruitable.despawn()
    end
  else
    local playerUniqueId = recruitable.ownerUuid()
    if playerUniqueId and recruitable.despawnInPlayersAbsence() and not world.entityExists(world.loadUniqueEntity(playerUniqueId)) then
      recruitable.beamOut()
    end
  end
end

function recruitable.despawnInPlayersAbsence()
  -- In ephemeral (instance worlds) we always follow the player back to their ship
  return storage.followingOwner or world.getProperty("ephemeral")
end

function recruitable.die()
  if recruitable.ownerUuid() and not recruitable.beamedOut then
    local recruitUuid = recruitable.recruitUuid()
    if recruitUuid then
      local status = getCurrentStatus()
      status.dead = true
      recruitable.messageOwner("recruits.updateRecruit", recruitUuid, status, true)
    end
    npc.setDropPools({})
  end
end

function recruitable.ownerUuid()
  return config.getParameter("ownerUuid", storage.ownerUuid)
end

function recruitable.recruitUuid()
  return config.getParameter("podUuid", storage.recruitUuid)
end

function recruitable.messageOwner(message, ...)
  local promise = world.sendEntityMessage(recruitable.ownerUuid(), message, ...)
  return function (success, failure)
      promises:add(promise, success, failure)
    end
end

function recruitable.triggerFieldBenefits()
  recruitable.messageOwner("recruits.triggerFieldBenefits", recruitable.recruitUuid())
end

function recruitable.triggerCombatBenefits()
  recruitable.messageOwner("recruits.triggerCombatBenefits", recruitable.recruitUuid())
end

function recruitable.beamOut()
  status.addEphemeralEffect("beamout")
  recruitable.despawnTimer = 0.7
end

function recruitable.despawn()
  npc.setDropPools({})
  npc.setDeathParticleBurst(nil)
  recruitable.beamedOut = true
  self.forceDie = true
end

function recruitable.isRecruitable()
  return config.getParameter("crew.recruitable", false) and not recruitable.ownerUuid()
end

function recruitable.generateRank()
  local tags = {
      role = config.getParameter("crew.role.name"),
      field = config.getParameter("crew.role.field")
    }
  local ranks = config.getParameter("crew.ranks")
  storage.recruitRank = sb_replaceTags(ranks[math.random(#ranks)], tags)
  return storage.recruitRank
end

function recruitable.generateRecruitInfo()
  local rank = config.getParameter("crew.rank") or storage.recruitRank or recruitable.generateRank()
  local parameters = {
      level = npc.level(),
      identity = npc.humanoidIdentity(),
      scriptConfig = {
          personality = personality(),
          crew = {
              rank = rank
            }
        }
    }

  local poly = mcontroller.collisionPoly()
  if #poly <= 0 then poly = nil end

  local name = world.entityName(entity.id())

  if not entity.uniqueId() then
    world.setUniqueId(entity.id(), sb.makeUuid())
  end

  storage.statusText = storage.statusText or randomStatusText(personalityType())

  return {
      name = name,
      uniqueId = entity.uniqueId(),
      portrait = world.entityPortrait(entity.id(), "full"),
      collisionPoly = poly,
      statusText = storage.statusText,
      rank = rank,
      uniform = storage.crewUniform,
      status = getCurrentStatus(),
      storage = preservedStorage(),
      config = {
          species = npc.species(),
          type = npc.npcType(),
          seed = npc.seed(),
          parameters = parameters
        }
    }
end

function recruitable.generateRecruitInteractAction()
  assert(recruitable.isRecruitable())

  if not entity.uniqueId() then
    world.setUniqueId(entity.id(), sb.makeUuid())
  end

  local action = config.getParameter("crew.recruitInteractAction")
  local args = {
      entity.uniqueId(),
      entity.position(),
      recruitable.generateRecruitInfo(),
      entity.id()
    }
  util.appendLists(args, action.messageArgs or {})

  return {
      "Message",
      {
          messageType = action.messageType,
          messageArgs = args
        }
    }
end

function recruitable.updateStatus(persistentEffects, damageTeam)
  -- We can't take the effects of BOTH the NPC's level AND the player's armor
  -- or we'd be overpowered.
  -- This happens the first time the NPC is recruited, before we've beamed off
  -- the planet and been respawned by the player.
  local takePlayerArmorEffects = npc.level() <= 1

  if persistentEffects and takePlayerArmorEffects then
    -- Approximates using same level weapon and armor
    -- since crew members don't level their weapons
    local powerMultiplier = 1.0
    persistentEffects = util.filter(persistentEffects, function(effect)
      if effect.stat and effect.stat == "powerMultiplier" and effect.baseMultiplier then
        powerMultiplier = powerMultiplier + (effect.baseMultiplier - 1.0)
        return false
      else
        return true
      end
    end)
    table.insert(persistentEffects, {stat = "powerMultiplier", baseMultiplier = powerMultiplier ^ config.getParameter("powerMultiplierExponent", 2.0)})

    status.setPersistentEffects("crew", persistentEffects)
  end
  if damageTeam then
    npc.setDamageTeam(damageTeam)
  end

  local portrait = nil
  if recruitable.portraitChanged then
    recruitable.portraitChanged = false
    portrait = world.entityPortrait(entity.id(), "full")
  end

  return {
      status = getCurrentStatus(),
      storage = preservedStorage(),
      portrait = portrait
    }
end

function recruitable.interact(sourceEntityId)
  if recruitable.isRecruitable() then
    return recruitable.generateRecruitInteractAction()
  end

  local sourceUniqueId = world.entityUniqueId(sourceEntityId)
  if sourceUniqueId and sourceUniqueId == recruitable.ownerUuid() then

    local interactAction = config.getParameter("crew.interactAction")
    if interactAction then
      -- Tailor, etc. offer to update your uniform instead of following you
      -- around.
      local data = config.getParameter("crew.interactData", {})
      data.messageArgs = data.messageArgs or {}
      table.insert(data.messageArgs, recruitable.recruitUuid())
      table.insert(data.messageArgs, entity.id())
      return { interactAction, data }
    else

      -- No role-specific behavior, so just follow/unfollow the player
      if storage.behaviorFollowing then
        if world.getProperty("ephemeral") then
          recruitable.confirmUnfollowBehavior()
          return { "None", {} }
        else
          return recruitable.generateUnfollowInteractAction()
        end
      else
        return recruitable.generateFollowInteractAction()
      end
    end
  end
end

function recruitable.generateUnfollowInteractAction()
  return {
      "Message",
      {
          messageType = "recruits.requestUnfollow",
          messageArgs = {
              entity.uniqueId(),
              recruitable.recruitUuid()
            }
        }
    }
end

function recruitable.generateFollowInteractAction()
  return {
      "Message",
      {
          messageType = "recruits.requestFollow",
          messageArgs = {
              entity.uniqueId(),
              recruitable.recruitUuid(),
              recruitable.generateRecruitInfo()
            }
        }
    }
end

function recruitable.confirmUnfollow(skipNotification)
  if not skipNotification then
    local playerEntityId = world.loadUniqueEntity(recruitable.ownerUuid())
    notify({ type = "unfollow", sourceId = playerEntityId})
  end

  npc.setPersistent(true)
  npc.setKeepAlive(false)
  storage.followingOwner = false
  storage.behaviorFollowing = false
  npc.setDamageTeam(recruitable.defaultDamageTeam)
end

function recruitable.confirmUnfollowBehavior(skipNotification)
  if not skipNotification then
    local playerEntityId = world.loadUniqueEntity(recruitable.ownerUuid())
    notify({ type = "unfollow", sourceId = playerEntityId})
  end

  npc.setPersistent(false)
  npc.setKeepAlive(true)
  storage.followingOwner = true
  storage.behaviorFollowing = false
  if playerEntityId and world.entityExists(playerEntityId) then
    npc.setDamageTeam(recruitable.defaultDamageTeam)
  end
end

function recruitable.confirmFollow(skipNotification)
  if not skipNotification then
    local playerEntityId = world.loadUniqueEntity(recruitable.ownerUuid())
    notify({ type = "follow", sourceId = playerEntityId})
  end

  npc.setPersistent(false)
  npc.setKeepAlive(true)
  storage.followingOwner = true
  storage.behaviorFollowing = true
  if playerEntityId and world.entityExists(playerEntityId) then
    npc.setDamageTeam(recruitable.defaultDamageTeam)
  end
end

function recruitable.isFollowing()
  return storage.behaviorFollowing or false
end

function recruitable.confirmRecruitment(playerUniqueId, recruitUuid, onShip)
  if not recruitable.isRecruitable() then
    return false
  end

  local playerEntityId = world.loadUniqueEntity(playerUniqueId)
  if not world.entityExists(playerEntityId) then
    return false
  end

  tenant.detachFromSpawner()

  notify({ type = "recruited", sourceId = playerEntityId })

  if onShip then
    storage.ownerUuid = playerUniqueId
    storage.recruitUuid = recruitUuid
  else
    recruitable.beamOut()
  end

  return true
end

function recruitable.declineRecruitment(playerUniqueId)
  local playerEntityId = world.loadUniqueEntity(playerUniqueId)
  if not world.entityExists(playerEntityId) then
    playerEntityId = nil
  end

  notify({ type = "recruitDeclined", sourceId = playerEntityId })
end

function recruitable.dyeUniformItem(item)
  local colorIndex = config.getParameter("crew.role.uniformColorIndex")
  if not item or not colorIndex then return item end

  local item = copy(item)
  if type(item) == "string" then item = { name = item, count = 1 } end
  item.parameters = item.parameters or {}
  item.parameters.colorIndex = colorIndex

  return item
end

function recruitable.setUniform(uniform)
  storage.crewUniform = uniform

  local uniformSlots = config.getParameter("crew.uniformSlots")
  if not uniform then
    uniform = {
      slots = uniformSlots,
      items = config.getParameter("crew.defaultUniform")
    }
  end
  for _, slotName in pairs(uniform.slots) do
    if contains(uniformSlots, slotName) then
      setNpcItemSlot(slotName, recruitable.dyeUniformItem(uniform.items[slotName]))
    end
  end

  recruitable.portraitChanged = true
end
