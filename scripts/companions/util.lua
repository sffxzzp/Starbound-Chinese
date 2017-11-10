require "/scripts/util.lua"
require "/scripts/pathutil.lua"

function getStatusSettings()
  if monster then
    return config.getParameter("statusSettings")
  elseif npc then
    return root.npcConfig(npc.npcType()).statusControllerSettings
  else
    assert(false)
  end
end

function getCurrentStatus()
  local resources = {}
  local resourceMax = {}
  for _,resourceName in pairs(status.resourceNames()) do
    resources[resourceName] = status.resource(resourceName)
    resourceMax[resourceName] = status.resourceMax(resourceName)
  end

  local stats = {}
  for statName,_ in pairs(getStatusSettings().stats) do
    stats[statName] = status.stat(statName)
  end

  return {
      resources = resources,
      resourceMax = resourceMax,
      stats = stats,
      effects = status.activeUniqueStatusEffectSummary(),
      dead = status.resource("health") == 0
    }
end

function setCurrentStatus(statusSummary, statEffectCategory)
  if statusSummary.persistentEffects then
    status.setPersistentEffects(statEffectCategory, statusSummary.persistentEffects)
  end

  for _,effect in pairs(statusSummary.effects or {}) do
    if effect[1] ~= "" then
      status.addEphemeralEffect(effect[1], effect[2])
    end
  end

  for resourceName, resourceValue in pairs(statusSummary.resources or {}) do
    if statusSummary.resourceMax[resourceName] then
      -- Restore the percentage of the resource the monster/npc had, as opposed
      -- to its absolute value, in case persistent effects applied by the
      -- player have changed the maximum.
      local fraction = resourceValue / statusSummary.resourceMax[resourceName]
      status.setResource(resourceName, fraction * status.resourceMax(resourceName))
    else
      status.setResource(resourceName, resourceValue)
    end
  end
end

-- Finds a position to spawn a (potentially large) entity near the given
-- position that doesn't collide with the terrain.
function findCompanionSpawnPosition(nearPosition, collisionPoly)
  if not world.polyCollision(collisionPoly, nearPosition, {"Null", "Block"}) then
    return nearPosition
  end

  local bounds = util.boundBox(collisionPoly)
  local height = bounds[4] - bounds[2]
  local collisionSet = {"Null", "Block", "Platform"}
  local position = findGroundPosition(nearPosition, -height, height, false, collisionSet, bounds)
  if position then
    position = vec2.add(position, {0, 1})
  end
  return position or nearPosition
end

function createFilledPod(pet)
  return {
      name = "filledcapturepod",
      count = 1,
      parameters = {--下面是强制将写在exe里的Some indescribable horror替换的语句。但是若文本不是Some indescribable horror则保持不变）
          description = modifySomeTags(pet.description),
          tooltipFields = {
              subtitle = pet.name or "不明生物",
              objectImage = pet.portrait
            },
          podUuid = sb.makeUuid(),
          collectablesOnPickup = pet.collectables,
          pets = {pet}
        }
    }
end

function modifySomeTags(inputDescription)
    if inputDescription == "Some indescribable horror" then
        return "某种不可名状的恐怖"
    else
        return inputDescription
    end
end