require "/scripts/companions/util.lua"
require "/scripts/achievements.lua"

-- Functions for entities that can be captured with a capturepod
capturable = {}

function capturable.init()
  message.setHandler("pet.attemptCapture", function (_, _, ...)
      return capturable.attemptCapture(...)
    end)
  message.setHandler("pet.attemptRelocate", function (_, _, ...)
      return capturable.attemptRelocate(...)
    end)
  message.setHandler("pet.returnToPod", function(_, _, ...)
      local status = capturable.captureStatus()
      capturable.recall()
      return status
    end)
  message.setHandler("pet.status", function(_, _, persistentEffects, damageTeam)
      if persistentEffects then
        status.setPersistentEffects("owner", persistentEffects)
      end
      if damageTeam then
        monster.setDamageTeam(damageTeam)
      end
      return { status = capturable.captureStatus() }
    end)

  local initialStatus = config.getParameter("initialStatus")
  if initialStatus then
    setCurrentStatus(initialStatus, "owner")
  end

  if capturable.podUuid() then
    capturable.startReleaseAnimation()
  end

  if capturable.wasRelocated() and not storage.spawned then
    status.addEphemeralEffect("monsterrelocatespawn")
    storage = config.getParameter("relocateStorage", {})
    storage.spawned = true
  end
end

function capturable.startReleaseAnimation()
  status.addEphemeralEffect("monsterrelease")
  animator.setAnimationState("releaseParticles", "on")
end

function capturable.update(dt)
  if capturable.ownerUuid() then
    if not capturable.optName() then
      monster.setName("宠物")
    end
    monster.setDisplayNametag(true)
  end

  if config.getParameter("uniqueId") then
    if entity.uniqueId() == nil then
      world.setUniqueId(entity.id(), config.getParameter("uniqueId"))
    else
      assert(entity.uniqueId() == config.getParameter("uniqueId"))
    end
  end

  if capturable.despawnTimer then
    capturable.despawnTimer = capturable.despawnTimer - dt
    if capturable.despawnTimer <= 0 then
      capturable.despawn()
    end
  else
    local spawner = capturable.tetherUniqueId() or capturable.ownerUuid()
    if spawner then
      if not world.entityExists(world.loadUniqueEntity(spawner)) then
        capturable.recall()
      end
    end
  end

  if capturable.confirmRelocate then
    if capturable.confirmRelocate:finished() then
      if capturable.confirmRelocate:result() then
        capturable.despawnTimer = 0.3
      else
        status.removeEphemeralEffect("monsterrelocate")
        status.addEphemeralEffect("monsterrelocatespawn")
      end
      capturable.confirmRelocate = nil
    end
  end
end

function capturable.die()
  if capturable.ownerUuid() and not capturable.justCaptured then
    local podUuid = capturable.podUuid()
    if podUuid then
      local uniqueId = entity.uniqueId()
      local status = capturable.captureStatus()
      status.dead = true
      capturable.messageOwner("pets.updatePet", podUuid, uniqueId, status, true)
    end
    monster.setDropPool(nil)
  end
end

-- Extricate this pet from its pod until the next time the pod is 'healed'.
function capturable.disassociate()
  local podUuid = capturable.podUuid()
  if capturable.ownerUuid() and podUuid then
    capturable.messageOwner("pets.disassociatePet", podUuid, entity.uniqueId())
    capturable.disassociated = true
  end
end

-- Associate another monster with this monster's pod.
function capturable.associate(pet)
  assert(capturable.ownerUuid())
  local podUuid = config.getParameter("podUuid")
  capturable.messageOwner("pets.associatePet", podUuid, pet)
end

function capturable.tetherUniqueId()
  return config.getParameter("tetherUniqueId")
end

function capturable.ownerUuid()
  return config.getParameter("ownerUuid")
end

function capturable.podUuid()
  if capturable.disassociated then
    return nil
  end
  return config.getParameter("podUuid")
end

function capturable.messageOwner(message, ...)
  world.sendEntityMessage(capturable.tetherUniqueId() or capturable.ownerUuid(), message, ...)
end

function capturable.captureStatus()
  local currentStatus = getCurrentStatus()
  -- Compute some artificial stats for displaying in the inventory, next to the
  -- pet slot:
  local stats = currentStatus.stats
  stats.defense = stats.protection
  stats.attack = 0
  local touchDamageConfig = config.getParameter("touchDamage")
  if touchDamageConfig then
    stats.attack = touchDamageConfig.damage
    stats.attack = stats.attack * (config.getParameter("touchDamageMultiplier") or 1)
    stats.attack = stats.attack * root.evalFunction("monsterLevelPowerMultiplier", monster.level())
    stats.attack = stats.attack * stats.powerMultiplier
  end

  return currentStatus
end

function capturable.recall()
  animator.burstParticleEmitter("captureParticles")
  status.addEphemeralEffect("monstercapture")
  capturable.despawnTimer = 0.5
end

function capturable.despawn()
  monster.setDropPool(nil)
  monster.setDeathParticleBurst(nil)

  local projectileTarget = capturable.tetherUniqueId() or capturable.ownerUuid()
  if projectileTarget then
    projectileTarget = world.loadUniqueEntity(projectileTarget)
    if not projectileTarget or not world.entityExists(projectileTarget) then
      projectileTarget = nil
    end
  end
  if projectileTarget then
    local projectiles = 5
    for i = 1, projectiles do
      local angle = math.pi * 2 / projectiles * i
      local direction = { math.sin(angle), math.cos(angle) }
      world.spawnProjectile("monstercaptureenergy", entity.position(), entity.id(), direction, false, {
          target = projectileTarget
        })
    end
  end

  capturable.justCaptured = true
end

function capturable.attemptCapture(podOwner)
  -- Try to capture the monster. If successful, the monster is killed and the
  -- pet configuration is returned.
  if capturable.capturable() then
    local petInfo = capturable.generatePet()

    recordEvent(podOwner, "captureMonster", entityEventFields(entity.id()), worldEventFields(), {
        monsterLevel = monster.level()
      })

    capturable.recall()
    return petInfo
  end
  return nil
end

function capturable.wasRelocated()
  return config.getParameter("wasRelocated", false)
end

function capturable.attemptRelocate(sourceEntity)
  if config.getParameter("relocatable", false) and not capturable.confirmRelocate then
    --The point that the monster will scale toward
    local scaleOffsetPart = config.getParameter("scaleOffsetPart", "body")
    local attachPoint = vec2.div(animator.partPoint(scaleOffsetPart, "offset") or {0, 0}, 2) -- divide by two because partPoint adds offset to offset
    local petInfo = {
      monsterType = monster.type(),
      collisionPoly = mcontroller.collisionPoly(),
      parameters = monster.uniqueParameters(),
      attachPoint = attachPoint
    }
    for k,v in pairs(config.getParameter("relocateParameters", {})) do
      petInfo.parameters[k] = v
    end
    petInfo.parameters.relocateStorage = storage
    petInfo.parameters.seed = monster.seed()

    status.addEphemeralEffect("monsterrelocate")
    capturable.confirmRelocate = world.sendEntityMessage(sourceEntity, "confirmRelocate", entity.id(), petInfo)
    return true
  end
end

function capturable.capturable(capturer)
  if capturable.ownerUuid() or storage.respawner then
    return false
  end

  local isCapturable = config.getParameter("capturable")
  if not isCapturable then
    return false
  end

  local captureHealthFraction = config.getParameter("captureHealthFraction", 0.5)
  local healthFraction = status.resource("health") / status.resourceMax("health")
  if healthFraction > captureHealthFraction then
    return false
  end

  return true
end

function capturable.optName()
  local name = world.entityName(entity.id())
  if name == "" then
    return nil
  end
  return name
end

function capturable.generatePet()
  local parameters = monster.uniqueParameters()
  parameters.aggressive = true

  parameters.seed = monster.seed()
  parameters.level = monster.level()

  local poly = mcontroller.collisionPoly()
  if #poly <= 0 then poly = nil end

  local monsterType = config.getParameter("capturedMonsterType", monster.type())
  local name = config.getParameter("capturedMonsterName", capturable.optName())
  local captureCollectables = config.getParameter("captureCollectables")

  return {
      name = name,
      description = world.entityDescription(entity.id()),
      portrait = world.entityPortrait(entity.id(), "full"),
      collisionPoly = poly,
      status = capturable.captureStatus(),
      collectables = captureCollectables,
      config = {
        type = monsterType,
        parameters = parameters
      }
    }
end
