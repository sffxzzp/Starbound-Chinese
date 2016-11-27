require("/scripts/replaceTags.lua")

function context()
  return _ENV[entity.entityType()]
end

function entityVariant()
  if entity.entityType() == "monster" then
    return monster.type()
  elseif entity.entityType() == "npc" then
    return npc.npcType()
  elseif entity.entityType() == "object" then
    return world.entityName(entity.id())
  end
end

function loadDialog(dialogKey)
  local configEntry = config.getParameter(dialogKey)
  if type(configEntry) == "string" then
    self.dialog[dialogKey] = root.assetJson(configEntry)
  elseif type(configEntry) == "table" then
    self.dialog[dialogKey] = configEntry
  else
    self.dialog[dialogKey] = false
  end
end

function queryDialog(dialogKey, targetId)
  if self.dialog == nil then self.dialog = {} end
  if self.dialog[dialogKey] == nil then loadDialog(dialogKey) end

  local dialog = self.dialog[dialogKey]
  if dialog then
    return speciesDialog(dialog, targetId)
  end
end

function speciesDialog(dialog, targetId)
  local species = context().species and context().species() or "default"
  dialog = dialog[species] or dialog.default

  local targetDialog
  if targetId then
    targetDialog = dialog[world.entitySpecies(targetId)] or dialog.default
  else
    targetDialog = dialog.default
  end

  if dialog.generic then
    targetDialog = util.mergeLists(dialog.generic, targetDialog)
  end

  return targetDialog
end

function staticRandomizeDialog(list)
  math.randomseed(context().seed())
  return list[math.random(1, #list)]
end

function sequenceDialog(list, sequenceKey)
  self.dialogSequence = self.dialogSequence or {}
  self.dialogSequence[sequenceKey] = (self.dialogSequence[sequenceKey] or -1) + 1
  return list[(self.dialogSequence[sequenceKey] % #list) + 1]
end

function randomizeDialog(list)
  return list[math.random(1, #list)]
end

function randomChatSound()
  local chatSounds = config.getParameter("chatSounds", {})

  local speciesSounds = chatSounds[npc.species()] or chatSounds.default
  if not speciesSounds then return nil end

  local genderSounds = speciesSounds[npc.gender()] or speciesSounds.default
  if not genderSounds then return nil end
  if type(genderSounds) ~= "table" then return genderSounds end
  if #genderSounds == 0 then return nil end

  return genderSounds[math.random(#genderSounds)]
end

-- output dialog
-- output source
function receiveClueDialog(args, output)
  args = parseArgs(args, {})

  local notification = util.find(self.notifications, function(n) return n.type == "giveClue" end)
  if notification then
    local dialog = root.assetJson(notification.dialog)
    BData:setTable(output.dialog, dialog)
    BData:setEntity(output.source, notification.sourceId)

    local dialogLine = staticRandomizeDialog(speciesDialog(dialog, notification.sourceId))
    world.sendEntityMessage(notification.sourceId, "dialogClueReceived", dialogLine)
    return true
  else
    return false
  end
end

-- param dialogType
-- param entity
function sayToEntity(args, output)
  args = parseArgs(args, {
    dialogType = "converse.dialog",
    dialog = nil,
    entity = "target",
    tags = {}
  })
  local entityId = BData:getEntity(args.entity)
  
  local dialog = BData:getTable(args.dialog)
  if dialog then
    dialog = speciesDialog(dialog, entityId)
  else
    dialog = queryDialog(args.dialogType, entityId)
  end
  local dialogMode = config.getParameter("dialogMode", "static")

  if dialog == nil then
    error(string.format("Dialog type %s not specified in %s", args.dialogType, entityVariant()))
  end

  if dialogMode == "static" then
    dialog = staticRandomizeDialog(dialog)
  elseif dialogMode == "sequence" then
    dialog = sequenceDialog(dialog, args.dialogType)
  else
    dialog = randomizeDialog(dialog)
  end
  if dialog == nil then return false end

  args.tags.selfname = world.entityName(entity.id())
  if entityId then args.tags.entityname = world.entityName(entityId) end

  local options = {}

  -- Only NPCs have sound support
  if entity.entityType() == "npc" then
    options.sound = randomChatSound()
  end
  dialog = sb_replaceTags(dialog, args.tags)
  context().say(dialog, args.tags, options)
  return true
end

-- param entity
function inspectEntity(args, output)
  args = parseArgs(args, {
    entity = "target"
  })
  local entityId = BData:getEntity(args.entity)
  if not entityId or not world.entityExists(entityId) then return false end

  local options = {}
  local species = nil
  if entity.entityType() == "npc" then
    species = npc.species()
    options.sound = randomChatSound()
  end

  local dialog = world.entityDescription(entityId, species)
  if not dialog then return false end

  context().say(dialog, {}, options)
  return true
end

-- param dialogType
-- param entity
function getDialog(args, output)
  args = parseArgs(args, {
    dialogType = "converse.dialog",
    entity = nil
  })
  local entityId = BData:getEntity(args.entity)
  self.currentDialog = copy(queryDialog(args.dialogType, entityId))
  self.currentDialogTarget = entityId
  if self.currentDialog == nil then
    return false
  end

  return true
end

-- param content
function say(args, output)
  args = parseArgs(args, {
    content = "nil",
    tags = {}
  })

  local portrait = config.getParameter("chatPortrait")

  args.tags.selfname = world.entityName(entity.id())

  local options = {}
  if entity.entityType() == "npc" then
    options.sound = randomChatSound()
  end

  if portrait == nil then
    args.content = sb_replaceTags(args.content, args.tags)
    context().say(args.content, args.tags, options)
  else
    args.content = sb_replaceTags(args.content, args.tags)
    context().sayPortrait(args.content, portrait, args.tags, options)
  end

  return true
end

function sayNext(args, output)
  args = parseArgs(args, {
    tags = {}
  })

  if self.currentDialog == nil or #self.currentDialog == 0 then return false end

  local portrait = config.getParameter("chatPortrait")

  args.tags.selfname = world.entityName(entity.id())
  if self.currentDialogTarget then args.tags.entityname = world.entityName(self.currentDialogTarget) end

  local options = {}
  if entity.entityType() == "npc" then
    options.sound = randomChatSound()
  end

  if portrait == nil then
    self.currentDialog[1] = sb_replaceTags(self.currentDialog[1], args.tags)
    context().say(self.currentDialog[1], args.tags, options)
  else
    if #self.currentDialog > 1 then
      options.drawMoreIndicator = true
    end
    self.currentDialog[1] = sb_replaceTags(self.currentDialog[1], args.tags)
    context().sayPortrait(self.currentDialog[1], portrait, args.tags, options)
  end

  table.remove(self.currentDialog, 1)
  return true
end

function hasMoreDialog(args, output)
  args = parseArgs(args, {
    tags = {}
  })

  if self.currentDialog == nil or #self.currentDialog == 0 then return false end

  return true
end