require "/scripts/util.lua"
require "/quests/bounty/bounty_portraits.lua"
require("/scripts/replaceTags.lua")

function init()
    setText()

    local params = quest.parameters()

    setBountyPortraits()

    quest.setPortrait("Objective", params.portraits.target)
    quest.setPortraitTitle("Objective", params.text.tags.bounty.name)
end

function questStart()
    quest.complete()
end

function setText()
  local tags = util.generateTextTags(quest.parameters().text.tags)
  quest.setTitle(sb_replaceTags("^orange;赏金：^green;<bounty.name>", tags))

  local textCons
  for i, q in pairs(quest.questArcDescriptor().quests) do
    local questConfig = root.questConfig(q.templateId).scriptConfig
    local text = ""
    if i > 1 then
      text = util.randomFromList(questConfig.generatedText.text.prev or questConfig.generatedText.text.default)
    else
      text = util.randomFromList(questConfig.generatedText.text.default)
    end

    local tags = util.generateTextTags(q.parameters.text.tags)
    if textCons then
      textCons = string.format("%s\n\n%s", textCons, sb_replaceTags(text, tags))
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

  quest.setText(textCons)
end