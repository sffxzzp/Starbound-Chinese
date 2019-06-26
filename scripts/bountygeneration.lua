require "/interface/cockpit/cockpitutil.lua"
require "/scripts/rect.lua"
require "/scripts/util.lua"
require("/scripts/replaceTags.lua")

function findAssignmentArea(fromPosition, systemTypes, rand)
  local maxSize = root.assetJson("/quests/bounty/generator.config:assignmentMaxSize")
  local bountyData = player.getProperty("bountyData") or {}
  bountyData = bountyData[player.serverUuid()] or {}
  local assignmentLog = bountyData.assignmentLog or {}
  rand = rand or sb.makeRandomSource()

  local worlds, systems
  local distance = 0
  local startAngle = rand:randf() * math.pi * 2
  local angleStep = math.pi * 2 / 8
  while true do
    local dir = math.random() > 0.5 and 1 or -1
    for i = 0, 7 do
      if distance > 0 or i == 0 then
        local newPosition = vec2.add(fromPosition, vec2.withAngle(startAngle + (i * dir * angleStep), distance))
        worlds, systems = findWorlds(newPosition, systemTypes, maxSize)

        if worlds ~= nil then
          local previouslyAssigned = false
          for _, s in ipairs(systems) do
            if contains(assignmentLog, s) then
              previouslyAssigned = true
            end
          end
          if not previouslyAssigned then
            local avgPos = vec2.div(util.fold(util.map(systems, systemPosition), {0, 0}, vec2.add), #systems)
            table.sort(systems, function(a, b)
                return vec2.mag(vec2.sub(systemPosition(a), avgPos)) < vec2.mag(vec2.sub(systemPosition(b), avgPos))
              end)
            return systems[1], worlds, systems
          end
        end
      end
    end

    distance = maxSize
    fromPosition = vec2.add(fromPosition, vec2.withAngle(startAngle, distance))
    coroutine.yield()
  end
end

function findWorlds(startPosition, systemTypes, maxSize)
  local position = startPosition
  local config = root.assetJson("/quests/bounty/generator.config")
  local minWorlds, minSystems, excludePlanets = config.assignmentMinWorlds, config.assignmentMinSystems, config.excludePlanetTypes

  minCount = minCount or 1
  maxSize = maxSize or 100
  local size = {10, 10}
  local region = rect.withCenter(position, size)

  local systems = {}
  local worlds = {}
  local maybeAddWorld = function(w)
    local parameters = celestialWrap.planetParameters(w)
    if parameters.worldType ~= "Terrestrial" then
      return
    end
    local visitable = celestialWrap.visitableParameters(w)
    if visitable and not contains(excludePlanets, visitable.typeName) then
      table.insert(worlds, w)
    end
  end

  while #worlds < minWorlds or #systems < minSystems do
    if size[1] > maxSize then
      sb.logInfo("%s worlds, %s systems, found at %s", #worlds, #systems, position)
      return nil, systems
    end

    systems = celestialWrap.scanSystems(region, systemTypes)
    worlds = {}
    for _,s in ipairs(systems) do
      for _, planet in ipairs(celestialWrap.children(s)) do
        maybeAddWorld(planet)
        for _, moon in ipairs(celestialWrap.children(planet)) do
          maybeAddWorld(moon)
        end
      end
    end
    size = vec2.mul(size, math.sqrt(2))
    if #systems > 0 and not compare(position, startPosition) then
      position = systemPosition(systems[1])
      sb.logInfo("Look around star at %s", position)
    end
    region = rect.withCenter(position, size)
  end

  return worlds, systems
end

function generateGang(seed)
  local rand = sb.makeRandomSource(seed)
  local gangConfig = root.assetJson("/quests/bounty/gang.config")

  -- collect a map of hats, and their supported name segments
  local hats = {}
  for k, _ in pairs(gangConfig.hatPrefix) do
    hats[k] = {"prefix"}
  end
  for k, _ in pairs(gangConfig.hatMid) do
    hats[k] = util.mergeLists(hats[k] or {}, {"mid"})
  end

  -- pick a hat
  local hatName = util.randomFromList(util.orderedKeys(hats), rand)
  local hatSegment = util.randomFromList(hats[hatName], rand)

  local prefixList = hatSegment == "prefix" and gangConfig.hatPrefix[hatName] or gangConfig.genericPrefix
  local midList = hatSegment == "mid" and gangConfig.hatMid[hatName] or gangConfig.genericMid

  local prefix = util.randomFromList(prefixList, rand)
  local mid = util.randomFromList(midList, rand)
  local suffix = util.randomFromList(gangConfig.suffix, rand)

  local majorColor, capstoneColor = math.random(1, 11), math.random(1, 11)
  while capstoneColor == majorColor do
    capstoneColor = math.random(1, 11)
  end
  return {
    name = string.format("%s%s%s", prefix, mid, suffix),
    hat = hatName,
    majorColor = majorColor,
    capstoneColor = capstoneColor,
  }
end

BountyGenerator = {}

function BountyGenerator.new(...)
  local instance = {}

  setmetatable(instance, {__index = BountyGenerator})
  instance:init(...)
  return instance
end

function BountyGenerator:init(seed, position, systemTypes, categories, endStepName)
  self.seed = seed
  self.rand = sb.makeRandomSource(seed)
  self.position = position
  self.stepCount = {4, 4}
  self.systemTypes = systemTypes
  self.config = root.assetJson("/quests/bounty/generator.config")
  self.clueItems = root.assetJson("/quests/bounty/clue_items.config")
  self.clueScans = root.assetJson("/quests/bounty/clue_scans.config")
  self.categories = categories or self.config.categories
  self.endStep = endStepName

  self.rewards = {
    money = 0,
    rank = 0,
    credits = 0
  }
end

function BountyGenerator:generateBountyMonster()
  local bountyConfig = root.assetJson("/quests/bounty/bounty_monsters.config")

  local monsterSeed = self.rand:randu64()
  local monsterType = util.randomFromList(util.keys(bountyConfig.monsters), self.rand)
  local monsterConfig = bountyConfig.monsters[monsterType]
  local name = root.generateName(bountyConfig.nameSource, monsterSeed)

  return {
    type = "monster",
    name = name,
    monster = {
      monsterType = monsterType,
      parameters = {
        shortdescription = name
      }
    },
    portraitCenter = monsterConfig.portraitCenter,
    portraitScale = monsterConfig.portraitScale
  }
end

function BountyGenerator:generateBountyNpc(gang, colorIndex, withTitle)
  local bountyConfig = root.assetJson("/quests/bounty/bounty.config")
  local npcConfig = bountyConfig.npc
  local speciesPool = npcConfig.species
  if gang and gang.species then
    speciesPool = gang.species
  end
  local species = util.randomFromList(speciesPool, self.rand)

  local npcSeed = self.rand:randu64()
  local npcVariant = root.npcVariant(species, npcConfig.typeName, 1.0, npcSeed, npcConfig.parameters)

  local nameGen = root.assetJson(string.format("/species/%s.species:nameGen", species))
  local gender = npcVariant.humanoidIdentity.gender
  local name = root.generateName(gender == "male" and nameGen[1] or nameGen[2], npcSeed)

  if withTitle then
    if self.rand:randf() < 0.5 then
      -- name prefix
      name = string.format("%s%s", util.randomFromList(bountyConfig.prefix, self.rand), name)
    else
      -- name suffix
      name = string.format("%s%s", name, util.randomFromList(bountyConfig.suffix, self.rand))
    end
  end

  local modifierNames = util.orderedKeys(bountyConfig.behaviorModifiers)
  local behaviorModifier = bountyConfig.behaviorModifiers[util.randomFromList(modifierNames, self.rand)]

  if gang then
    -- copy in gang parameters used in the NPC
    gang = {
      name = gang.name,
      hat = gang.hat,
      colorIndex = colorIndex,
      species = gang.species,
    }
  end
  local bounty = {
    type = "npc",
    name = name,
    species = species,
    typeName = npcConfig.typeName,
    seed = npcSeed,
    gang = gang,
    parameters = sb.jsonMerge(npcConfig.parameters, {
      identity = {
        gender = gender,
        name = name
      },
      scriptConfig = {
        gang = gang
      }
    }),
    behaviorOverrides = behaviorModifier
  }
  return bounty
end

function BountyGenerator:generateGangMember(gang)
  local species = util.randomFromList(gang.species or {"human", "hylotl", "avian", "glitch", "novakid", "apex", "floran"}, self.rand)
  if gang then
    gang = {
      name = gang.name,
      hat = gang.hat
    }
  end
  local bounty = {
    type = "npc",
    species = species,
    typeName = "gangmember",
    gang = gang,
    parameters = {
      scriptConfig = {
        gang = gang
      }
    }
  }
  return bounty
end

function BountyGenerator:pickEdge(fromStep, toStep, toClueType, questId, previousSteps)
  local options
  if toStep then
    options = util.filter(self.config.edges, function(edge)
        return edge.next.step == toStep
      end)

    if fromStep and fromStep.clueType then
      -- If there are no existing edges to fulfill this edge, insert an
      -- edge from fromStep to toStep
      local existing = util.find(options, function(e)
          return e.prev.clueType == fromStep.clueType
            and (fromStep.step == nil or e.prev.step == fromStep.step)
            and e.next.step == toStep
            and (toClueType == nil or e.next.clueType == toClueType)
            and e.mid == nil
        end)
      if existing == nil then
        table.insert(options, {
          source = "fromStep",
          prev = {
            step = fromStep.step,
            clueType = fromStep.clueType
          },
          next = {
            step = toStep,
            clueType = toClueType
          }
        })
      end
    end

    -- generate options for edges with no prev step defined
    -- this requires that they have a clue type defined for the prev step
    -- Don't generate options for edges that have a mid step, they will have their prev step generated later
    -- when picking the prev->mid edge
    local generated = {}
    for _,o in ipairs(options) do
      if not o.mid and not o.prev.step then
        if not o.prev.clueType then
          error(string.format("Edge with target step '%s' and no previous step must have a clueType", o.next.step))
        end

        -- Gather potential steps to use that can produce the clue
        local stepNames = util.filter(util.orderedKeys(self.config.steps), function(stepName)
            local step = self.config.steps[stepName]
            if step.clueTypes and contains(step.clueTypes, o.prev.clueType) then
              return true
            end
            return false
          end)
        local generatedSteps = util.map(stepNames, function(stepName)
            return {
              source = "stepClueType",
              prev = {
                step = stepName
              }
            }
          end)

        -- Also get potential steps to use from existing edges
        util.appendLists(generatedSteps, util.map(util.filter(self.config.edges, function(e)
            if e.mid then
              return false
            end
            if e.next.step == nil or e.next.clueType ~= o.prev.clueType then
              return false
            end
            return true
          end), function(e)
            return {
              source = "fromEdge",
              weight = e.weight,
              prev = e.next
            }
          end))
        if #generatedSteps == 0 then
          error(string.format("No steps found for clue type '%s'", o.prev.clueType))
        end
        for _,step in ipairs(generatedSteps) do
          local newOption = sb.jsonMerge(copy(o), step)
          newOption.weight = newOption.weight or self.config.steps[step.prev.step].weight
          table.insert(generated, newOption)
        end
      end
    end

    -- remove the options without specified steps, except ones that also have a mid step
    -- those with a mid step are still valid as the prev step is picked later
    options = util.filter(options, function(o)
        return o.prev.step ~= nil or o.mid ~= nil
      end)

    -- add in the options with generated steps
    options = util.mergeLists(options, generated)
    
    -- filter options by whether they support bridging to the required clue type
    if toClueType then
      options = util.filter(options, function(edge)
          local clueType = edge.next.clueType
          if not clueType then
            local clueTypes = self.config.steps[edge.next.step].clueTypes
            return contains(clueTypes, toClueType)
          end
          return edge.next.clueType == toClueType
        end)
    end

    if fromStep then
      options = util.filter(options, function(edge)
          return edge.mid == nil
        end)
      if fromStep.step then
        options = util.filter(options, function(edge)
            return edge.prev.step == fromStep.step
          end)
      end
      if fromStep.clueType then
        options = util.filter(options, function(edge)
            return edge.prev.clueType == fromStep.clueType
          end)
      end
    end
  elseif self.endStep then
    options = {
      {
        prev = {
          step = self.endStep
        },

        next = nil
      }
    }
  else
    options = util.map(self.config.ends, function(step)
        return {
          prev = {
            step = step
          },

          next = nil
        }
      end)
  end

  -- filter edges by allowed step categories
  options = util.filter(options, function(o)
      if o.prev and not o.mid then
        if not contains(self.categories, self.config.steps[o.prev.step].category) then
          return false
        end
      end

      if o.next then
        if not contains(self.categories, self.config.steps[o.next.step].category) then
          return false
        end
      end

      return true
    end)

  if #options == 0 then
    error(string.format("No options available for finding edge from '%s' to '%s'. Clue type: '%s'", fromStep and (fromStep.step or fromStep.clueType), toStep or self.endStep, toClueType))
  end

  --sb.logInfo("Options: %s", sb.printJson(options, 1))

  -- make a weighted pool of the options
  options = util.map(options, function(o)
      local weight = o.weight
      if weight == nil and o.prev.step then
        -- if edge is not weighted, use the weight of the prev step, if any
        weight = self.config.steps[o.prev.step].weight
      end
      weight = weight or 1.0

      -- reduce weight each time the step has appeared in previous steps
      for _,p in pairs(previousSteps) do
        if o.prev.step == p.name then
          weight = weight * 0.1
        end
      end
      return {weight, o}
    end)
  local option = util.weightedRandom(options, self.rand:randu64())
  option.prev.questId = questId or sb.makeUuid()

  return option
end

function BountyGenerator:generateStepsTo(toStep, fromStep, previousSteps)
  local steps = {}
  local merge = {}

  function stepMerge(questId, step)
    return {
      from = questId,
      questParameters = step.questParameters,
      coordinate = step.coordinate,
      locations = step.locations,
      spawns = step.spawns,
      text = step.text,
      clueType = step.clueType,
      password = step.password,
    }
  end

  local edge
  local prevQuestId
  while true do
    edge = self:pickEdge(fromStep, toStep and toStep.name, toStep and toStep.clueType, prevQuestId, previousSteps)
    if not edge then
      return nil
    end
    if edge.next and toStep then
      edge.next.questId = toStep.questId
    end

    if toStep then
      table.insert(merge, 1, stepMerge(toStep.questId, edge.prev))

      if edge.next then
        table.insert(toStep.merge, 1, stepMerge(edge.prev.questId, edge.next))
      end
    end

    requirePrev = nil
    -- If edge calls for inserting a mid quest
    if edge.mid then
      -- generate steps from the mid quest to the end quest
      prevQuestId = edge.prev.questId
      steps = self:generateStepsTo(toStep, edge.mid, previousSteps)
      if steps == nil then
        error(string.format("Failed to insert mid steps, no chain from %s to %s available", toStep.name, edge.next.step))
      end

      -- next find a new edge from the first step the mid step in the next iteration of the loop
      previousSteps = util.mergeLists(steps, previousSteps)
      fromStep = edge.prev
      toStep = steps[1]
      toClueType = edge.mid.clueType

      -- merge mid parameters
      table.insert(toStep.merge, 1, stepMerge(prevQuestId, edge.mid))
    else
      break
    end
  end

  table.insert(steps, 1, {
    name = edge.prev.step,
    questId = edge.prev.questId,
    clueType = edge.prev.clueType,
    merge = merge
  })
  return steps
end

-- takes generated quest chain steps, returns quest arc
-- handles merging of parameters, finding worlds, and generating text
function BountyGenerator:processSteps(steps, bounty, planetPool)
  local coordinateConfigs = {}
  local coordinates = {}
  local locations = {}
  local spawns = {}
  local systemSpawns = {}
  local passwords = {}

  local usedCoordinates = {} -- keep track of used coordinates to return with steps

  -- create coordinate, location, and spawn parameter tables for each step
  for _,step in pairs(steps) do
    local stepConfig = copy(self.config.steps[step.name])
    step.questParameters = stepConfig.questParameters or {}
    coordinateConfigs[step.questId] = stepConfig.coordinate or {}
    locations[step.questId] = stepConfig.locations or {}
    spawns[step.questId] = stepConfig.spawns or {}
    systemSpawns[step.questId] = stepConfig.systemSpawn or nil
  end

  -- Apply parameters from edges to the steps
  for _,step in pairs(steps) do
    for _,merge in pairs(step.merge) do
      step.questParameters = sb.jsonMerge(step.questParameters, merge.questParameters)

      local rhs = merge.coordinate or {}
      local lhs = coordinateConfigs[step.questId] or {}
      if rhs.type == "previous" then
        coordinateConfigs[step.questId] = {
          type = "previous",
          previousQuest = merge.from,
          questParameter = rhs.questParameter
        }
      else
        coordinateConfigs[step.questId] = sb.jsonMerge(lhs, rhs)
      end

      for k,rhs in pairs(merge.locations or {}) do
        local lhs = locations[step.questId][k] or {}
        if rhs.type == "previous" then
          -- Set location for this step to the previous location
          locations[step.questId][k] = {
            type = "previous",
            previousQuest = merge.from,
            previousLocation = rhs.previousLocation,
          }
        else
          locations[step.questId][k] = sb.jsonMerge(lhs, rhs)
        end
      end

      for k,rhs in pairs(merge.spawns or {}) do
        local lhs = spawns[step.questId][k] or {}
        if rhs.type == "otherStep" then
          rhs = {
            type = "otherQuest",
            spawn = rhs.spawn,
            location = rhs.location,
            questId = merge.from
          }
        end
        spawns[step.questId][k] = sb.jsonMerge(lhs, rhs)
      end

      if merge.password then
        if merge.password == "previous" then
          passwords[step.questId] = {
            type = "previous",
            step = merge.from
          }
        elseif merge.password == "generate" then
          passwords[step.questId] = {
            type = "generate"
          }
        end
      end

      step.clueType = step.clueType or merge.clueType
      step.text = sb.jsonMerge(step.text, merge.text or {})
    end
  end

  -- Generate quest parameters from step parameters
  for i,step in pairs(steps) do
    local lastQuestId = steps[i-1] and steps[i-1].questId
    if lastQuestId then
      while coordinateConfigs[lastQuestId].type == "previous" do
        lastQuestId = coordinateConfigs[lastQuestId].previousQuest
      end
    end

    local coordinateConfig = coordinateConfigs[step.questId]
    if coordinateConfig.type == "world" then
      local worldIndex = 1
      if coordinateConfig.prevSystem then
        local s = coordinateSystem(coordinates[lastQuestId])
        for i, w in ipairs(planetPool) do
          if compare(coordinateSystem(w), s) then
            worldIndex = i
            break
          end
        end
      else
        -- try not to place the quest in a previously used system
        local usedSystems = util.map(usedCoordinates, coordinateSystem)
        for i,w in ipairs(planetPool) do
          if not contains(usedSystems, coordinateSystem(w)) then
            worldIndex = i
            break
          end
        end
      end
      local world = table.remove(planetPool, worldIndex)
      if world == nil then
        error("Not enough worlds in the planet pool")
      end
      table.insert(usedCoordinates, world)
      step.questParameters[coordinateConfig.questParameter] = {
        type = "coordinate",
        coordinate = world
      }
      coordinates[step.questId] = world
    elseif coordinateConfig.type == "system" then
      local system
      if coordinateConfig.prevSystem then
        system = coordinateSystem(coordinates[lastQuestId])
        for i, w in ipairs(planetPool) do
          if compare(coordinateSystem(w), s) then
            worldIndex = i
            break
          end
        end
      else
        local worldIndex = 1
        local usedSystems = util.map(usedCoordinates, coordinateSystem)
        for i,w in ipairs(planetPool) do
          if not contains(usedSystems, coordinateSystem(w)) then
            worldIndex = i
            break
          end
        end
        local world = table.remove(planetPool, 1)
        if world == nil then
          error("Not enough worlds in the planet pool to use for system")
        end
        system = coordinateSystem(world)
      end

      table.insert(usedCoordinates, system)
      if self.debug then
        system = celestial.currentSystem()
      end
      step.questParameters[coordinateConfig.questParameter] = {
        type = "coordinate",
        coordinate = system
      }
      coordinates[step.questId] = system
    elseif coordinateConfig.type == "previous" then
      local coordinate = coordinates[coordinateConfig.previousQuest]
      step.questParameters[coordinateConfig.questParameter] = {
        type = "coordinate",
        coordinate = coordinate
      }
      coordinates[step.questId] = coordinate
    end

    for k,locationConfig in pairs(locations[step.questId]) do
      step.questParameters.locations = step.questParameters.locations or {
        type = "json",
        locations = {}
      }
      local worldTags = {
        questId = step.questId,
        threatLevel = self.level,
      }
      local worldId = locationConfig.worldId and sb_replaceTags(locationConfig.worldId, worldTags)
      if locationConfig.type == "dungeon" then
        step.questParameters.locations.locations[k] = {
          type = "dungeon",
          tags = locationConfig.tags,
          biome = celestialWrap.visitableParameters(coordinates[step.questId]).primaryBiome,
          worldId = worldId
        }
      elseif locationConfig.type == "stagehand" then
        step.questParameters.locations.locations[k] = {
          type = "stagehand",
          stagehand = locationConfig.stagehand,
          worldId = worldId
        }
      elseif locationConfig.type == "previous" then
        step.questParameters.locations.locations[k] = {
          type = "previous",
          quest = locationConfig.previousQuest,
          location = locationConfig.previousLocation,
        }
      else
        error(string.format("Unable to produce quest parameter for location type '%s'", locationConfig.type))
      end
    end

    -- generate passwords before spawns that may use them
    local codeConfig = passwords[step.questId]
    if codeConfig then
      local code
      if codeConfig.type == "generate" then
        code = util.weightedRandom(self.config.passwords, self.rand:randu64())
        if code == "random" then
          code = string.format("%04d", self.rand:randInt(0, 9999))
        end
      elseif codeConfig.type == "previous" then
        while (type(codeConfig) == "table" and codeConfig.type == "previous") do
          codeConfig = passwords[codeConfig.step]
        end
        code = codeConfig
      end
      passwords[step.questId] = code
    end

    for k,spawnConfig in pairs(spawns[step.questId]) do
      step.questParameters.spawns = step.questParameters.spawns or {
        type = "json",
        spawns = {}
      }

      if spawnConfig.type == "clueNpc" or spawnConfig.type == "clueBounty" then
        local clueConfig
        local spawnType
        if spawnConfig.type == "clueNpc" then
          clueConfig = root.assetJson("/quests/bounty/clue_npcs.config")
          spawnType = "npc"
        elseif spawnConfig.type == "clueBounty" then
          clueConfig = root.assetJson("/quests/bounty/clue_bounties.config")
          spawnType = "bounty"
        end
        -- Get clue NPC types that support the clue type
        local names = util.filter(util.orderedKeys(clueConfig), function(name)
            return clueConfig[name].clues[step.clueType] ~= nil
          end)
        if #names == 0 then
          error(string.format("No clue NPC of type %s found with clue type %s", spawnType, step.clueType))
        end
        clueConfig = clueConfig[util.randomFromList(names, self.rand)] -- random clue NPC
        spawnConfig = {
          type = spawnType,
          stagehand = spawnConfig.stagehand,
          location = spawnConfig.location,
          useBountyGang = clueConfig.useBountyGang,
          npc = sb.jsonMerge(clueConfig.npc or {}, spawnConfig.npc or {}),
          behaviorOverrides = spawnConfig.behaviorOverrides or clueConfig.behaviorOverrides
        }

        step.text = step.text or {}
        local clueMessage = clueConfig.clues[step.clueType].message
        if clueMessage then
          step.text.message = clueMessage
        end
      end

      if spawnConfig.type == "bounty" then
        if bounty.type == "npc" then
          spawnConfig = {
            type = "npc",
            location = spawnConfig.location,
            stagehand = spawnConfig.stagehand,
            npc = sb.jsonMerge({
              species = bounty.species,
              typeName = bounty.typeName,
              seed = bounty.seed,
              parameters = bounty.parameters
            }, spawnConfig.npc or {}),
            behaviorOverrides = spawnConfig.behaviorOverrides or bounty.behaviorOverrides
          }
        elseif bounty.type == "monster" then
          spawnConfig = {
            type = "monster",
            location = spawnConfig.location,
            stagehand = spawnConfig.stagehand,
            monster = bounty.monster
          }
        else
          error(string.format("No bounty type '%s'", bounty.type))
        end
      end

      if spawnConfig.type == "clueItem" then
        local itemNames = util.filter(util.orderedKeys(self.clueItems), function(itemName)
          return self.clueItems[itemName][step.clueType] ~= nil
        end)
        local itemName = util.randomFromList(itemNames, self.rand)
        local clue = util.randomFromList(self.clueItems[itemName][step.clueType], self.rand)

        step.text = step.text or {}
        if clue.message then
          step.text.message = clue.message
        end
        spawnConfig = {
          type = "item",
          location = spawnConfig.location,
          stagehand = spawnConfig.stagehand,
          item = {
            name = itemName,
            parameters = sb.jsonMerge(clue.parameters, {
              questId = step.questId
            })
          }
        }
      end

      if spawnConfig.type == "clueObject" then
        step.questParameters.spawns.spawns[k] = {
          type = "object",
          location = spawnConfig.location,
          clueType = step.clueType
        }
      elseif spawnConfig.type == "clueScan" then
        step.questParameters.spawns.spawns[k] = {
          type = "scan",
          location = spawnConfig.location,
          uuid = sb.makeUuid(),
          clueType = step.clueType
        }
      elseif spawnConfig.type == "item" then
        local item = spawnConfig.item
        step.questParameters.spawns.spawns[k] = {
          type = "item",
          location = spawnConfig.location,
          stagehand = spawnConfig.stagehand,
          item = item
        }
      elseif spawnConfig.type == "npc" then
        -- Generate a bounty target NPC
        local generated
        if spawnConfig.gangMember then
          generated = self:generateGangMember(bounty.gang)
        else
          local gang
          if spawnConfig.useBountyGang then
            gang = bounty.gang
          end
          generated = self:generateBountyNpc(gang)
        end
        spawnConfig.npc = sb.jsonMerge({
          species = generated.species,
          typeName = generated.typeName,
          parameters = generated.parameters,
          level = self.level
        }, spawnConfig.npc)

        local behaviorOverrides
        if spawnConfig.behaviorOverrides then
          behaviorOverrides = {
            [step.questId] = spawnConfig.behaviorOverrides
          }
        end
        local spawn = {
          type = "npc",
          location = spawnConfig.location,
          stagehand = spawnConfig.stagehand,
          npc = spawnConfig.npc,
          multiple = spawnConfig.multiple,
          behaviorOverrides = behaviorOverrides,
        }

        if spawn.behaviorOverrides then
          for _, overrides in pairs(spawn.behaviorOverrides) do
            for _, override in ipairs(overrides) do
              for k,v in pairs(override.behavior.parameters or {}) do
                local tags = {
                  questId = step.questId,
                  clueType = step.clueType
                }
                if type(v) == "string" then
                  override.behavior.parameters[k] = sb_replaceTags(v, tags)
                end
              end
            end
          end
        end

        step.questParameters.spawns.spawns[k] = spawn
      elseif spawnConfig.type == "stagehand" then
        step.questParameters.spawns.spawns[k] = {
          type = "stagehand",
          location = spawnConfig.location,
          stagehandUniqueId = spawnConfig.stagehandUniqueId or sb.makeUuid()
        }
      elseif spawnConfig.type == "keypad" then
        step.questParameters.spawns.spawns[k] = {
          type = "keypad",
          skipSteps = spawnConfig.skipSteps,
          location = spawnConfig.location,
          objectType = spawnConfig.objectType,
          password = passwords[step.questId]
        }
      elseif spawnConfig.type == "otherQuest" then
        -- pre-emptively spawn a thing that's getting spawned in the next step
        step.questParameters.spawns.spawns[k] = {
          type = "otherQuest",
          location = spawnConfig.location,
          spawn = spawnConfig.spawn,
          quest = spawnConfig.questId
        }
      elseif spawnConfig.type == "monster" then
        spawnConfig.monster.level = spawnConfig.monster.level or self.level
        step.questParameters.spawns.spawns[k] = {
          type = "monster",
          location = spawnConfig.location,
          stagehand = spawnConfig.stagehand,
          monster = spawnConfig.monster
        }
      else
        error(string.format("Unable to produce quest parameter for spawn type '%s'", spawnConfig.type))
      end
    end
    
    local systemSpawn = systemSpawns[step.questId]
    if systemSpawn then
      step.questParameters.systemSpawn = {
        type = "json",
        objectType = systemSpawn.objectType,
        uuid = sb.makeUuid(),
      }
    end

    local text = step.text or {}
    step.questParameters.text = {
      type = "json",
      completeMessage = step.text.message,
      skipMessage = step.text.skipMessage,
      questLog = step.text.questLog
    }
  end

  -- Text tag generation
  local questTextTags = {}
  for _,step in pairs(steps) do
    local tags = {
      coordinate = {}
    }
    local coordinateConfig = coordinateConfigs[step.questId]
    while coordinateConfig.type == "previous" do
      coordinateConfig = coordinateConfigs[coordinateConfig.previousQuest]
    end
    if coordinateConfig.type == "world" then
      tags.coordinate.preposition = "on"
    elseif coordinateConfig.type == "system" then
      tags.coordinate.preposition = "in"
    else
      --error(string.format("No preposition available for coordinate type '%s'", coordinateConfig.type))
    end

    local coordinate = coordinates[step.questId]
    if coordinate then
      tags.coordinate.name = celestialWrap.planetName(coordinate)
      tags.coordinate.systemName = celestialWrap.planetName(coordinateSystem(coordinate))
    end

    tags.password = passwords[step.questId]

    questTextTags[step.questId] = tags
  end

  -- Link tags between prev/next quests, and add common text tags
  local linkedTextTags = {}
  for i = 1, #steps do
    local step = steps[i]
    local tags = copy(questTextTags[step.questId])

    local prevStep = steps[i - 1]
    if prevStep then
      tags.prev = copy(questTextTags[prevStep.questId])
    end

    local nextStep = steps[i + 1]
    if nextStep then
      tags.next = copy(questTextTags[nextStep.questId])
    end

    tags.bounty = {
      name = bounty.name
    }

    linkedTextTags[step.questId] = tags
    step.questParameters.text.tags = tags
  end

  -- Text tag replacement
  for _,step in pairs(steps) do
    local tags = util.generateTextTags(linkedTextTags[step.questId])

    if step.questParameters.spawns then
      for _,spawn in pairs(step.questParameters.spawns.spawns) do
        if spawn.type == "item" then
          util.recReplaceTags(spawn.item.parameters or {}, tags)
        end
      end
    end

    local text = step.questParameters.text
    if text then
      if text.completeMessage then
        text.completeMessage = sb_replaceTags(text.completeMessage, tags)
      end
      if text.skipMessage then
        text.skipMessage = sb_replaceTags(text.skipMessage, tags)
      end
    end
  end

  local quests = {}
  for _,step in pairs(steps) do
    local stepConfig = self.config.steps[step.name]
    table.insert(quests, {
      questId = step.questId,
      templateId = stepConfig.quest,
      parameters = step.questParameters
    })
  end

  return quests, usedCoordinates
end


function BountyGenerator:questArc(steps, bountyTarget, planetPool)
  self.rand = sb.makeRandomSource(self.seed)
  local arc = {
    quests = {},
    stagehandUniqueId = sb.makeUuid()
  }

  local lastStep = steps[#steps]
  table.insert(lastStep.merge, {
    questParameters = {
      rewards = {
        type = "json",
        money = self.rewards.money,
        rank = self.rewards.rank,
        credits = self.rewards.credits
      }
    }
  })

  sb.logInfo("Steps: %s", sb.printJson(util.map(steps, function(s) return s.name end), 1))
  local usedCoordinates
  arc.quests, usedCoordinates = self:processSteps(steps, bountyTarget, planetPool)

  local preBountyParameters = {
    portraits = {
      type = "json",
      target = self.targetPortrait
    },
    text = {
      type = "json",
      tags = {
        coordinate = arc.quests[1].parameters.text.tags.coordinate,
        bounty = {
          name = bountyTarget.name,
          gang = bountyTarget.gang,
          species = bountyTarget.species
        },
        rewards = self.rewards
      }
    }
  }

  table.insert(arc.quests, 1, {
      templateId = self.preBountyQuest,
      questId = sb.makeUuid(),
      parameters = preBountyParameters
    })

  return arc, usedCoordinates
end

function BountyGenerator:generateBountyArc(bountyTarget, planetPool)
  self.rand = sb.makeRandomSource(self.seed)

  local arc = {
    quests = {},
    stagehandUniqueId = sb.makeUuid()
  }
  local stepCount = 0
  local minStepCount = self.rand:randInt(self.stepCount[1], self.stepCount[2])
  local steps = {}
  while stepCount < minStepCount do
    stepCount = stepCount + 1
    local newSteps = self:generateStepsTo(steps[1], nil, steps)
    if not newSteps then break end

    steps = util.mergeLists(newSteps or {}, steps)
  end

  bountyTarget = bountyTarget or self:generateBountyNpc()
  return self:questArc(steps, bountyTarget, planetPool)
end

function BountyGenerator:generateMinorBounty(bountyTarget, planetPool)
  self.rand = sb.makeRandomSource(self.seed)

  local step = {
    questId = sb.makeUuid(),
    name = util.randomFromList(self.config.minor, self.rand),
    merge = {}
  }
  local steps = { step }

  bountyTarget = bountyTarget or self:generateBountyMonster()
  return self:questArc(steps, bountyTarget, planetPool)
end
