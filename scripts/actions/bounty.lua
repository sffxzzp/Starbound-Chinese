require "/scripts/poly.lua"
require "/scripts/actions/dialog.lua"
require("/scripts/replaceTags.lua")

function getGangProperties(args, board)
  local gang = config.getParameter("gang")
  if gang then
    return true, {name = gang.name, hat = {name = gang.hat, parameters={colorIndex = gang.colorIndex}}}
  else
    return false
  end
end

function sayBountyClueDialog(args, board)
  local dialog = root.assetJson(string.format("%s.%s", args.domain, args.dialog))
  if not dialog then return false end
  dialog = speciesDialog(dialog, args.entityId)
  dialog = staticRandomizeDialog(dialog)
  if not dialog then return false end

  local quest = args.quest
  if type(args.quest) == "table" and args.quest.questId then
    quest = args.quest.questId
  end

  self.dialogTags = self.dialogTags or {}
  if type(quest) == "string" then
    local questTags = util.generateTextTags(self.quest:questDescriptor(quest).parameters.text.tags)
    for k,v in pairs(questTags) do
      self.dialogTags[k] = v
    end
  end
  self.dialogTags.selfname = world.entityName(entity.id())

  local species = util.randomFromList({"human", "apex", "floran", "glitch", "hylotl", "novakid", "avian"})
  local nameGen = root.assetJson(string.format("/species/%s.species:nameGen", species))
  self.dialogTags.randomName = root.generateName(gender == "male" and nameGen[1] or nameGen[2])

  npc.say(sb_replaceTags(sb_replaceTags(dialog, self.dialogTags), tags))
  return true
end

function arrested(args, board, _, dt)
  local oldPrimary = npc.getItemSlot("primary")
  local oldAlt = npc.getItemSlot("alt")

  npc.setItemSlot("alt", nil)
  npc.setItemSlot("primary", "handcuffs")

  while status.statPositive("arrested") do
    mcontroller.controlCrouch()

    coroutine.yield()
  end

  npc.setItemSlot("primary", oldPrimary)
  npc.setItemSlot("alt", oldAlt)

  return true
end