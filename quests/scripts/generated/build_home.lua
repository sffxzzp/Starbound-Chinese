require("/quests/scripts/generated/common.lua")
require("/scripts/replaceTags.lua")

function colonyTags(item)
  local config = root.itemConfig(item).config
  return config.colonyTags or {}
end

function onInit()
  message.setHandler("colonyDeed.newHome", onNewHome)

  local textGenerator = currentQuestTextGenerator()
  local objectText = config.getParameter("objectListText")
  local furnitureNeeded = quest.parameters().furnitureSet.items

  local haveDoor = false
  local haveLight = false

  for _,item in ipairs(furnitureNeeded) do
    local tags = colonyTags(item)
    if contains(tags, "door") then
      haveDoor = true
    end
    if contains(tags, "light") then
      haveLight = true
    end
    addObjective(Objective:new(textGenerator, {
        id = "object-"..item.name,
       text = sb_replaceTags(objectText, {
            count = item.count,
            itemName = itemShortDescription(item)
          })
      }))
  end

  if not haveLight then
    addObjective(Objective:new(textGenerator, {
        id = "lightsource",
        text = config.getParameter("lightSourceText")
      }))
  end
  if not haveDoor then
    addObjective(Objective:new(textGenerator, {
        id = "door",
        text = config.getParameter("doorText")
      }))
  end
end

function onNewHome(_, _, tenants, furniture, boundary)
  local furnitureNeeded = quest.parameters().furnitureSet.items
  for _,item in ipairs(furnitureNeeded) do
    if (furniture[item.name] or 0) < item.count then
      return
    end
  end

  quest.complete()
end
