require("/scripts/util.lua")
require("/scripts/quest/paramtext.lua")
require("/scripts/quest/participant.lua")
require("/scripts/questgen/generator.lua")
require("/scripts/quest/text_generation.lua")
require("/scripts/replaceTags.lua")

-- param eventName
-- pararm source can be an EntityId depending on the event, e.g. the player who
--   interacted with this NPC.
function fireQuestEvent(args, output)
  args = parseArgs(args, {
    eventName = "",
    source = "",
    table = ""
  })

  local source = BData:getEntity(args.source)
  local table = BData:getTable(args.table)
  self.quest:fireEvent(args.eventName, source, table)
  return true
end

function updateQuestPortrait(args, output)
  args = parseArgs(args, { })

  local portrait = world.entityPortrait(entity.id(), "full")
  self.quest:fireEvent("updatePortrait", portrait)
  return true
end

function cancelQuest(args, output)
  args = parseArgs(args, { })

  self.quest:cancelQuest()
  return true
end

function questItem(args, output)
  args = parseArgs(args, {
    parameterName = "",
    quest = ""
  })
  local quest = BData:getTable(args.quest)
  if not quest or not quest.questId then return false end

  local paramValue = self.quest:questParameter(quest.questId, args.parameterName)
  if paramValue.type ~= "item" then
    return false
  end

  if output.table then
    local descriptor = paramValue.item
    if type(descriptor) == "string" then
      descriptor = { name = descriptor }
    end
    BData:setTable(output.table, descriptor)
  end
  return true
end

function questEntity(args, output)
  args = parseArgs(args, {
    parameterName = "",
    quest = ""
  })
  local quest = BData:getTable(args.quest)
  if not quest or not quest.questId then return false end

  local paramValue = self.quest:questParameter(quest.questId, args.parameterName)
  if paramValue.type ~= "entity" or not paramValue.uniqueId then
    return false
  end

  local entityId = world.loadUniqueEntity(paramValue.uniqueId)
  if not world.entityExists(entityId) then
    return false
  end

  if output.entity then
    BData:setEntity(output.entity, entityId)
  end
  return true
end

function sayQuestDialog(args, output)
  args = parseArgs(args, {
    quest = "override",
    dialogType = "",
    entity = "target",
    extraTags = {}
  })
  local entityId = BData:getEntity(args.entity)
  local dialog = root.assetJson("/dialog/quest.config:"..args.dialogType)
  if not dialog then return false end
  dialog = speciesDialog(dialog, entityId)
  dialog = staticRandomizeDialog(dialog)
  if not dialog then return false end

  local quest = BData:getTable(args.quest)
  if type(quest) == "table" and quest.questId then
    quest = quest.questId
  end

  local tags = {}
  if type(quest) == "string" then
    local textGenerator = questTextGenerator(self.quest:questDescriptor(quest))
    tags = textGenerator.tags
  end

  for tag, value in pairs(args.extraTags) do
    tags[tag] = value
  end

  tags.selfname = world.entityName(entity.id())
  dialog = sb_replaceTags(dialog, tags)
  npc.say(dialog, tags)
  return true
end

function isGivingQuest(args, output)
  args = parseArgs(args, { })
  return self.quest.isOfferingQuests
end

function hasQuest(args, output)
  args = parseArgs(args, { })
  return self.quest:hasQuest()
end

local function tooManyQuestsNearby()
  local searchRadius = config.getParameter("questGenerator.nearbyQuestRange", 50)
  local questManagers = 0
  local entities = world.entityQuery(entity.position(), searchRadius)
  for _,entity in pairs(entities) do
    if world.entityName(entity) == "questgentest" then
      -- Testing object suppresses automatic quest generation
      return true
    end

    if world.entityType(entity) == "stagehand" and world.stagehandType(entity) == "questmanager" then
      questManagers = questManagers + 1
    end
  end

  if questManagers >= config.getParameter("questGenerator.nearbyQuestLimit", 2) then
    return true
  end
  return false
end

function generateNewArc()
  if not self.questGenerator then
    self.questGenerator = QuestGenerator.new()
  end
  self.questGenerator.debug = self.debug or false
  self.questGenerator.abortQuestCallback = tooManyQuestsNearby
  return self.questGenerator:generateStep()
end

local function decideWhetherToGenerateQuest(rolls)
  if not config.getParameter("questGenerator.enableParticipation") then
    return false
  end

  if world.getProperty("ephemeral") then
    return false
  end

  if self.quest:hasRole() then
    return false
  end

  local baseChance = config.getParameter("questGenerator.chance", 0.1)
  -- If we're supposed to make a decision every 30 seconds, and 4 minutes have
  -- passed, we have 8 decisions to make.
  -- 'chance' is equal to the chance of at least one of these decisions (each
  -- with probability 'baseChance') being positive.
  local maxChance = config.getParameter("questGenerator.maxBoostedChance", 0.5)
  local chance = math.min(1.0 - (1.0 - baseChance) ^ rolls, maxChance)
  util.debugLog("rolls = %s, baseChance = %s, chance = %s", rolls, baseChance, chance)
  if chance < math.random() then
    return false
  end

  if tooManyQuestsNearby() then
    return false
  end

  return true
end

-- Determine how many times, since the last time we decided whether to generate
-- a quest, we 'should' have made another decision.
-- For example, if we're supposed to decide every 30 seconds, and 4 minutes
-- have elapsed, we should have made 8 rolls (decisions).
local function getDecisionRolls()
  if not storage.lastQuestGenDecisionTime then
    return 1
  end
  local elapsed = world.time() - storage.lastQuestGenDecisionTime
  local period = config.getParameter("questGenerator.timeLimit", 30)
  return math.floor(elapsed / period)
end

function maybeGenerateQuest(args, output)
  args = parseArgs(args, { })

  if self.quest:hasRole() then
    self.isGeneratingQuest = false
    return false
  end

  local rolls = getDecisionRolls()
  if rolls > 0 then
    self.isGeneratingQuest = decideWhetherToGenerateQuest(rolls)
    storage.lastQuestGenDecisionTime = world.time()

    if self.isGeneratingQuest then
      util.debugLog("Decided to generate a quest.")
    else
      util.debugLog("Decided not to generate a quest.")
    end
  end

  if not self.isGeneratingQuest then
    return false
  end

  local arc = generateNewArc()
  if not arc then
    return false
  end

  self.isGeneratingQuest = false

  local position = entity.position()
  world.spawnStagehand(position, "questmanager", {
      uniqueId = arc.questArc.stagehandUniqueId,
      quest = {
          arc = storeQuestArcDescriptor(arc.questArc),
          participants = arc.participants
        },
      plugins = arc.managerPlugins
    })
  return true
end

-- param quest
-- param name
-- output list/number/bool/etc.
function getQuestValue(args, output)
  args = parseArgs(args, {
    quest = "",
    name = ""
  })

  local quest = BData:getTable(args.quest)
  if not quest then return false end
  local questId = quest.questId or quest

  local value = self.quest:getQuestValue(questId, args.name)
  if not value then return false end

  local setType, index = BData.findType(output)
  if setType then
    BData:set(setType, index, value)
  end
  return true
end

-- param quest
-- param name
-- param list/number/bool/etc.
function setQuestValue(args, output)
  args = parseArgs(args, {
    quest = "",
    name = ""
  })

  local quest = BData:getTable(args.quest)
  if not quest then return false end
  local questId = quest.questId or quest

  local getType,index = BData.findType(args)
  local value = type(index) ~= "string" and index or BData:get(getType, index)
  if value == nil then return false end

  self.quest:setQuestValue(questId, args.name, value)
  return true
end

-- param quest
-- param name
function unsetQuestValue(args, output)
  args = parseArgs(args, {
    quest = "",
    name = ""
  })

  local quest = BData:getTable(args.quest)
  if not quest then return false end
  local questId = quest.questId or quest

  self.quest:setQuestValue(questId, args.name, nil)
  return true
end
