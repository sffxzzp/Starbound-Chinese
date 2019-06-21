require "/interface/cockpit/cockpitutil.lua"
require "/scripts/messageutil.lua"
require "/scripts/quest/player.lua"
require "/scripts/quest/text_generation.lua"
require "/quests/bounty/bounty_portraits.lua"
require "/quests/bounty/stages.lua"
require("/scripts/replaceTags.lua")

function init()
  local parameters = quest.parameters()

  storage.pending = storage.pending or {}
  storage.spawned = storage.spawned or {}
  storage.killed = storage.killed or {}
  storage.event = storage.event or {}

  message.setHandler(quest.questId().."entitySpawned", function(_, _, param, uniqueId)
      storage.spawned[param] = uniqueId
      storage.pending[param] = nil
    end)
  message.setHandler(quest.questId().."entityPending", function(_, _, param, position)
      storage.pending[param] = position
    end)
  message.setHandler(quest.questId().."entityDied", function(_, _, param, uniqueId)
      storage.killed[param] = uniqueId
    end)
  message.setHandler(quest.questId()..".participantEvent", function(_, _, uniqueId, eventName, ...)
      storage.event[eventName] = true
    end)
  message.setHandler(quest.questId().."setCompleteMessage", function(_, _, text)
      storage.completeMessage = text
    end)
  message.setHandler(quest.questId().."keepAlive", function() end)
  
  message.setHandler(quest.questId()..".complete", function(_, _, text)
      storage.event["captured"] = true
      quest.complete()
    end)
  message.setHandler(quest.questId()..".fail", function(_, _, text)
      quest.fail()
    end)

  storage.scanObjects = storage.scanObjects or nil
  self.scanClue = nil
  message.setHandler("objectScanned", function(message, isLocal, objectName)
    if storage.scanObjects ~= nil then
      storage.scanObjects = copyArray(util.filter(storage.scanObjects, function(n) return n ~= objectName end))
    end
    if self.scanClue and objectName == self.scanClue then
      storage.event["scannedClue"] = true
    end
  end)
  message.setHandler("interestingObjects", function(...)
    return storage.scanObjects or jarray()
  end)

  self.stages = util.map(config.getParameter("stages"), function(stageName)
    return _ENV[stageName]
  end)

  self.radioMessageConfig = {
    default = {
      messageId = "bounty_message",
      unique = false,
      senderName = "诺布尔队长",
      portraitImage = "/interface/chatbubbles/captain.png:<frame>"
    },
    angry = {
      messageId = "bounty_message",
      unique = false,
      senderName = "诺布尔队长",
      portraitImage = "/interface/chatbubbles/captainrage.png:<frame>"
    }
  }

  self.defaultSkipMessages = {
    "你确定不要任何线索解决问题？干的漂亮！"
  }

  self.managerPosition = nil

  self.skipMessage = nil
  local textParameter = quest.parameters().text
  if textParameter then
    if not storage.completeMessage then
      storage.completeMessage = textParameter.completeMessage
    end
    self.skipMessage = textParameter.skipMessage or util.randomFromList(self.defaultSkipMessages)
  end

  self.bountyType = nil
  local firstTemplate = quest.questArcDescriptor().quests[1].templateId
  if firstTemplate == "pre_bounty" or firstTemplate == "pre_bounty_capstone" then
    self.bountyType = "major"
  else
    self.bountyType = "minor"
  end

  storage.stage = storage.stage or 1
  setStage(storage.stage)

  setText()

  setBountyPortraits()

  self.tasks = {}

  table.insert(self.tasks, coroutine.create(function()
      if self.bountyName == nil then
        return true
      end
      while true do
        local setBounty = util.await(world.sendEntityMessage(entity.id(), "setBountyName", self.bountyName))
        if setBounty:succeeded() then
          break
        end
        coroutine.yield()
      end
      return true
    end))

  table.insert(self.tasks, coroutine.create(function()
    while storage.spawned["inertScans"] == nil do
      coroutine.yield(false)
    end
    storage.scanObjects = copyArray(storage.spawned["inertScans"].uuids)
    return true
  end))

  setupEarlyCompletion()
end

function update(dt)
  if not self.managerPosition then
    if self.findManager then
      local status, result = coroutine.resume(self.findManager)
      if not status then
        error(result)
      end
      if result then
        self.managerPosition = result
        self.findManager = nil
      end
    elseif questInvolvesWorld() then
      sb.logInfo("Find bounty manager")
      self.findManager = coroutine.create(loadBountyManager)
    elseif quest.worldId() == nil then
      -- the quest takes place on an unknown world, try to find a bounty manager for this world, potentially spawned by another player
      sb.logInfo("Maybe find bounty manager")
      self.findManager = coroutine.create(maybeLoadBountyManager)
    end
  end

  if self.stage then
    local status, result = coroutine.resume(self.stage)
    if not status then
      error(result)
    end
  end

  self.tasks = util.filter(self.tasks, function(t)
      local status, result = coroutine.resume(t)
      if not status then
        error(result)
      end
      return not result
    end)
end

function questInvolvesWorld()
  local locationsParameter = quest.parameters().locations
  if locationsParameter then
    local locationWorlds = util.map(util.tableValues(locationsParameter.locations), function(location)
        local tags = {
          questId = quest.questId()
        }
        return sb_replaceTags(location.worldId or quest.worldId() or "", tags)
      end)
    if contains(locationWorlds, player.worldId()) then
      return true
    end
  end
  return onQuestWorld()
end

function onQuestWorld()
  return player.worldId() == quest.worldId() and player.serverUuid() == quest.serverUuid()
end

function stopMusic()
  world.sendEntityMessage(player.id(), "stopBountyMusic")
end

function questStart()
  local associatedMission = config.getParameter("associatedMission")
  if associatedMission then
    player.enableMission(associatedMission)
    player.playCinematic(config.getParameter("missionUnlockedCinema"))
  end
end

function questComplete()
  stopMusic()

  local quests = quest.questArcDescriptor().quests
  -- rewards on last step of the chain
  if quest.questId() == quests[#quests].questId then
    local rewards = quest.parameters().rewards
    local text = config.getParameter("generatedText.complete")
    text = text.capture or text.default

    modifyQuestEvents("Captured", rewards.money, rewards.rank, rewards.credits)

    local tags = util.generateTextTags(quest.parameters().text.tags)
    tags.bountyPoints = rewards.rank
    text = sb_replaceTags(util.randomFromList(text), tags)
    quest.setCompletionText(text)
  end

  sb.logInfo("Complete message: %s", storage.completeMessage)
  if storage.completeMessage then
    player.radioMessage(radioMessage(storage.completeMessage))
  end

  if questInvolvesWorld() then
    sb.logInfo("Send playerCompleted message")
    world.sendEntityMessage(quest.questArcDescriptor().stagehandUniqueId, "playerCompleted", player.uniqueId(), quest.questId())
  end

  if self.bountyType == "major" then
    world.sendEntityMessage(entity.id(), "setBountyName", nil)
  end

  local associatedMission = config.getParameter("associatedMission")
  if associatedMission then
    player.completeMission(associatedMission)
  end

  quest.setWorldId(nil)
  quest.setLocation(nil)
end

function questFail(abandoned)
  stopMusic()

  modifyQuestEvents("Failed", 0, 0, 0)

  if questInvolvesWorld() then
    world.sendEntityMessage(quest.questArcDescriptor().stagehandUniqueId, "playerFailed", player.uniqueId(), quest.questId())
  end

  if self.bountyType == "major" then
    world.sendEntityMessage(entity.id(), "setBountyName", nil)
  end
  -- local failureText = config.getParameter("generatedText.failure")
  -- if failureText then
  --   quest.setCompletionText(failureText)
  -- end
end

function setupEarlyCompletion()
  local questIndices = {}
  local quests = quest.questArcDescriptor().quests
  for i,q in pairs(quests) do
    questIndices[q.questId] = i
  end

  for i,q in pairs(quests) do
    local spawnsParameter = q.parameters.spawns
    if spawnsParameter then
      for name,spawnConfig in pairs(spawnsParameter.spawns) do
        if spawnConfig.type == "keypad"
            and spawnConfig.skipSteps
            and spawnConfig.skipSteps > 0
            and i <= questIndices[quest.questId()]
            and i + spawnConfig.skipSteps > questIndices[quest.questId()] then

          message.setHandler(q.questId.."keypadUnlocked", function(_, _, _, _)
              storage.completeMessage = self.skipMessage
              local followup = questIndices[q.questId] + spawnConfig.skipSteps
              quest.complete(followup - 1) -- Lua is 1-indexed, callback takes index starting at 0
            end)
        end
      end
    end
  end
end

function questInteract(entityId)
  if self.onInteract then
    return self.onInteract(entityId)
  end
end

function loadBountyManager()
  while true do
    local findManager = world.findUniqueEntity(quest.questArcDescriptor().stagehandUniqueId)
    while not findManager:finished() do
      coroutine.yield()
    end
    if findManager:succeeded() then
      world.sendEntityMessage(quest.questArcDescriptor().stagehandUniqueId, "playerStarted", player.uniqueId(), quest.questId())
      return findManager:result()
    else
      world.spawnStagehand(entity.position(), "bountymanager", {
          tryUniqueId = quest.questArcDescriptor().stagehandUniqueId,
          questArc = quest.questArcDescriptor(),
          worldId = player.worldId(),
          questId = quest.questId(),
        })
    end
    coroutine.yield()
  end
end

function maybeLoadBountyManager()
  local stagehandId = quest.questArcDescriptor().stagehandUniqueId
  while true do
    local findManager = util.await(world.findUniqueEntity(stagehandId))
    if findManager:succeeded() then
      sb.logInfo("Involves this world: %s", util.await(world.sendEntityMessage(stagehandId, "involvesQuest", quest.questId())):result())
      if util.await(world.sendEntityMessage(stagehandId, "involvesQuest", quest.questId())):result() then
        world.sendEntityMessage(stagehandId, "playerStarted", player.uniqueId(), quest.questId())
        return findManager:result()
      end
    end

    util.wait(3.0)
  end
end

function nextStage()
  if storage.stage == #self.stages then
    return quest.complete()
  end
  setStage(storage.stage + 1)
end

function previousStage()
  if storage.state == 1 then
    error("Cannot go to previous stage from first stage")
  end
  setStage(storage.stage - 1)
end

function setStage(i)
  if storage.stage ~= i then
    stopMusic()
  end
  
  storage.stage = i
  
  self.onInteract = nil
  self.stage = coroutine.create(self.stages[storage.stage])
  local status, result = coroutine.resume(self.stage)
  if not status then
    error(result)
  end
end

function setText()
  local tags = util.generateTextTags(quest.parameters().text.tags)
  self.bountyName = tags["bounty.name"]
  local title
  if self.bountyType == "major" then
    title = sb_replaceTags("^yellow; ^orange;赏金：^green;<bounty.name>", tags)
  else
    title = sb_replaceTags("^orange;赏金：^green;<bounty.name>", tags)
  end
  quest.setTitle(title)

  local textCons
  for i, q in pairs(quest.questArcDescriptor().quests) do
    if i > 1 then -- skip the first quest, it's fake
      local questConfig = root.questConfig(q.templateId).scriptConfig

      if i > 2 and q.questId == quest.questId() then
        break
      end

      local text = q.parameters.text.questLog
      if not text then
        if q.questId ~= quest.questId() then
          text = util.randomFromList(questConfig.generatedText.text.prev or questConfig.generatedText.text.default)
        else
          text = util.randomFromList(questConfig.generatedText.text.default)
        end
      end

      local tags = util.generateTextTags(q.parameters.text.tags)
      if textCons then
        textCons = string.format("%s%s", textCons, sb_replaceTags(text, tags))
      else
        textCons = sb_replaceTags(text, tags)
      end

      if q.questId == quest.questId() then
        if questConfig.generatedText.failureText then
          local failureText = util.randomFromList(questConfig.generatedText.failureText.default)
          failureText = sb_replaceTags(failureText, tags)
          quest.setFailureText(failureText)
        end
        
        break
      end
    end
  end

  quest.setText(textCons)
end

function radioMessage(text, portraitType)
  portraitType = portraitType or "default"
  local message = copy(self.radioMessageConfig[portraitType])
  local tags = util.generateTextTags(quest.parameters().text.tags)
  message.text = sb_replaceTags(text, tags)
  return message
end

function modifyQuestEvents(status, money, rank, credits)
  local newBountyEvents = player.getProperty("newBountyEvents", {})
  local thisQuestEvents = newBountyEvents[quest.questId()] or {}
  thisQuestEvents.status = status
  thisQuestEvents.money = (thisQuestEvents.money or 0) + money
  thisQuestEvents.rank = (thisQuestEvents.rank or 0) + rank
  thisQuestEvents.credits = (thisQuestEvents.credits or 0) + credits
  thisQuestEvents.cinematic = config.getParameter("bountyCinematic")
  newBountyEvents[quest.questId()] = thisQuestEvents
  player.setProperty("newBountyEvents", newBountyEvents)
end