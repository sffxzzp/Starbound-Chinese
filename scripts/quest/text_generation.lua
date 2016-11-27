require("/scripts/util.lua")
require("/scripts/rect.lua")
require("/scripts/replaceTags.lua")
require("/scripts/quest/paramtext.lua")
require("/scripts/quest/directions.lua")

QuestTextGenerator = {}
QuestTextGenerator.__index = QuestTextGenerator

function QuestTextGenerator.new(...)
  local self = setmetatable({}, QuestTextGenerator)
  self:init(...)
  return self
end

function QuestTextGenerator:init(templateId, parameters, seed, arcPosition)
  self.templateId = templateId
  self.parameters = parameters or {}
  self.seed = seed
  assert(self.seed ~= nil)
  self.random = sb.makeRandomSource(self.seed)

  if arcPosition then
    if #quest.questArcDescriptor().quests == 1 then
      self.positionKey = "solo"
    elseif arcPosition == 0 then
      self.positionKey = "first"
    elseif arcPosition == #quest.questArcDescriptor().quests - 1 then
      self.positionKey = "last"
    else
      self.positionKey = "next"
    end
  end

  self.config = root.questConfig(self.templateId).scriptConfig

  self.tags = questParameterTags(self.parameters)
  util.mergeTable(self.tags, self:generateExtraTags())
end

function generateFluffTags(fluff, seed)
  local random = sb.makeRandomSource(seed)
  local tags = {}
  for _, entry in ipairs(fluff) do
    local varName, pool = table.unpack(entry)
    local value = pool[random:randUInt(1, #pool)]
    tags[varName] = value
  end
  return tags
end

local function paramHumanoidIdentity(paramValue)
  local level = paramValue.parameters.level or 1
  local npcVariant = root.npcVariant(paramValue.species, paramValue.typeName, level, paramValue.seed, paramValue.parameters)
  return npcVariant.humanoidIdentity
end

local function pronounGender(species, gender)
  gender = gender or "neutral"
  local genderOverrides = root.assetJson("/quests/quests.config:pronounGenders")
  if species and genderOverrides[species] and genderOverrides[species][gender] then
    gender = genderOverrides[species][gender]
  end
  return gender
end

function QuestTextGenerator:generateExtraTags()
  local tags = {}
  local pronouns = root.assetJson("/quests/quests.config:pronouns")

  for paramName, paramValue in pairs(self.parameters) do
    if paramValue.region then
      tags[paramName .. ".direction"] = describeDirection(rect.center(paramValue.region))
    end

    local gender = nil
    if paramValue.type == "npcType" then
      local identity = paramHumanoidIdentity(paramValue)
      tags[paramName .. ".name"] = identity.name
      tags[paramName .. ".gender"] = identity.gender
      gender = pronounGender(identity.species, identity.gender)
    elseif paramValue.type == "entity" then
      tags[paramName .. ".gender"] = paramValue.gender
      gender = pronounGender(paramValue.species, paramValue.gender)
    end

    if gender then
      for pronounType, pronounText in pairs(pronouns[gender]) do
        tags[paramName .. ".pronoun." .. pronounType] = pronounText
      end
    end
  end

  local fluff = self.config.generatedText and self.config.generatedText.fluff
  if fluff then
    util.mergeTable(tags, generateFluffTags(fluff, self.seed))
  end

  return tags
end

function QuestTextGenerator:generateText(textField, speakerField)
  local speakers = self.config.portraits
  local speaker = speakers[speakerField] or speakers.default
  local species = nil
  if type(speaker) == "string" then
    local speakerParamValue = self.parameters[speaker]
    if speakerParamValue then
      species = speakerParamValue.species
    end
  elseif speaker then
    species = speaker.species
  end

  local variants = self.config.generatedText[textField]
  if not variants then return "" end
  if self.positionKey then
    variants = variants[self.positionKey] or variants.default
  end
  if not variants then return "" end
  if not variants[1] then
    variants = variants[species or "default"] or variants.default
  end
  if not variants then return "" end

  local text = variants[self.random:randUInt(1, #variants)]
  return self:substituteTags(text)
end

function QuestTextGenerator:substituteTags(text)
  -- Substitute into the text until no further changes are made.
  -- (Enables recursive use of fluff variables and parameters within fluff.)
  local lastText
    text = sb_replaceTags(text, self.tags)
  return text
end

function currentQuestTextGenerator()
  return QuestTextGenerator.new(quest.templateId(), quest.parameters(), quest.seed(), quest.questArcPosition())
end

function questTextGenerator(questDesc)
  return QuestTextGenerator.new(questDesc.templateId, questDesc.parameters, questDesc.seed)
end

function generateQuestText()
  local arc = quest.questArcDescriptor()
  local finalQuestDesc = arc.quests[#arc.quests]
  local finalGenerator = QuestTextGenerator.new(finalQuestDesc.templateId, finalQuestDesc.parameters, finalQuestDesc.seed)
  local currentGenerator = currentQuestTextGenerator()

  quest.setTitle(finalGenerator:generateText("title", "questStarted"))
  quest.setCompletionText(currentGenerator:generateText("completionText", "questComplete"))
  quest.setFailureText(finalGenerator:generateText("failureText", "questFailed"))

  local goalText = finalGenerator:generateText("goalText", "questStarted")
  local mainText = currentGenerator:generateText("text", "questStarted")
  local join = goalText and goalText ~= "" and root.assetJson("/quests/quests.config:goalTextSeparator") or ""
  local text = goalText .. join .. mainText
  quest.setText(text)
end

function generateNoteItem(templates, title, textGenerator)
  local template = templates[math.random(#templates)]
  local description = textGenerator:substituteTags(template)
  return {
      name = "secretnote",
      count = 1,
      parameters = {
        shortdescription = title,
        description = "\""..description.."\""
      }
    }
end

function questNoteTemplates(templateId, configPath)
  local questConfig = root.questConfig(templateId).scriptConfig
  return sb.jsonQuery(questConfig, configPath)
end
