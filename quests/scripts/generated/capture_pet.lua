require("/scripts/util.lua")
require("/quests/scripts/generated/common.lua")
require("/scripts/companions/util.lua")

function onInit()
  self.questClient:setMessageHandler("entitiesDead", function() end)
  self.questClient:setMessageHandler("entitiesSpawned", function() end)

  if not storage.rewardAdded then
    local textGenerator = currentQuestTextGenerator()
    local tradedMonster = quest.parameters().tradedMonster

    local pet = {
        name = root.generateName("/quests/generated/petnames.config:names", quest.seed()),
        description = textGenerator:substituteTags("这是一份礼物，来自<questGiver>。"),
        portrait = tradedMonster.portrait,
        config = {
            type = tradedMonster.typeName,
            parameters = tradedMonster.parameters
          }
      }
    quest.addReward(createFilledPod(pet))
    storage.rewardAdded = true
  end
end

function questInteract(entityId)
  if world.entityUniqueId(entityId) ~= quest.parameters().questGiver.uniqueId then return end
  if not hasRequiredItem() then return end

  local textGenerator = currentQuestTextGenerator()
  local dialogConfig = root.assetJson("/interface/confirmation/monstertradeconfirmation.config")
  for key, value in pairs(dialogConfig) do
    if type(value) == "string" then
      value = textGenerator:substituteTags(value)
      dialogConfig[key] = value
    end
  end

  local monster = quest.parameters().monster
  dialogConfig.images.portrait = monster.portrait

  promises:add(player.confirm(dialogConfig), function (agree)
      if agree then
        quest.complete()
      end
    end)
  return true
end

function hasRequiredItem()
  return player.hasItemWithParameter("pets[0].config.type", quest.parameters().monster.typeName)
end

function onUpdate()
  if not objective("capture"):isComplete() then
    if hasRequiredItem() then
      objective("capture"):complete()
    end
  else
    if hasRequiredItem() then
      setIndicators({"questGiver"})
    else
      setIndicators({})
    end
  end
end

function conditionsMet()
  return objective("capture"):isComplete()
end

function onQuestComplete()
  player.consumeItemWithParameter("pets[0].config.type", quest.parameters().monster.typeName, 1)
end

function onQuestStart()
  player.giveItem({ name = "capturepod", count = 1})
end
