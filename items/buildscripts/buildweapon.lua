require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/versioningutils.lua"
require "/scripts/staticrandom.lua"

function build(directory, config, parameters, level)
  if level then
    parameters.level = level
  end

  -- initialize randomization
  local seed = parameters.seed or config.seed
  if not seed then
    seed = math.random(1, 4294967295)
    parameters.seed = seed
  end

  -- select the generation profile to use
  local builderConfig = {}
  if config.builderConfig then
    builderConfig = randomFromList(config.builderConfig, seed, "builderConfig")
  end

  -- select alt ability
  if not parameters.altAbilitySource and builderConfig.altAbilities and #builderConfig.altAbilities > 0 then
    parameters.altAbilitySource = randomFromList(builderConfig.altAbilities, seed, "altAbilitySource")
  end

  -- load and merge alt ability
  local altAbilitySource = parameters.altAbilitySource or config.altAbilitySource
  if altAbilitySource then
    local altAbilityConfig = root.assetJson(altAbilitySource)
    util.mergeTable(config, altAbilityConfig)
  end

  -- elemental type
  if not parameters.elementalType and builderConfig.elementalType then
    parameters.elementalType = randomFromList(builderConfig.elementalType, seed, "elementalType")
  end
  local elementalType = parameters.elementalType or config.elementalType

  -- elemental config
  if builderConfig.elementalConfig then
    util.mergeTable(config, builderConfig.elementalConfig[elementalType])
  end
  if config.altAbility and config.altAbility.elementalConfig then
    util.mergeTable(config.altAbility, config.altAbility.elementalConfig[elementalType])
  end

  -- elemental tag
  replacePatternInData(config, nil, "<elementalType>", elementalType)

  -- name
  if not parameters.shortdescription and builderConfig.nameGenerator then
    parameters.shortdescription = root.generateName(util.absolutePath(directory, builderConfig.nameGenerator), seed)
  end

  -- merge damage properties
  if builderConfig.damageConfig then
    util.mergeTable(config.damageConfig or {}, builderConfig.damageConfig)
  end

  -- preprocess shared primary attack config
  parameters.primaryAttack = parameters.primaryAttack or {}
  parameters.primaryAttack.fireTimeFactor = valueOrRandom(parameters.primaryAttack.fireTimeFactor, seed, "fireTimeFactor")
  parameters.primaryAttack.baseDpsFactor = valueOrRandom(parameters.primaryAttack.baseDpsFactor, seed, "baseDpsFactor")
  parameters.primaryAttack.energyUsageFactor = valueOrRandom(parameters.primaryAttack.energyUsageFactor, seed, "energyUsageFactor")

  config.primaryAttack.fireTime = scaleConfig(parameters.primaryAttack.fireTimeFactor, config.primaryAttack.fireTime)
  config.primaryAttack.baseDps = scaleConfig(parameters.primaryAttack.baseDpsFactor, config.primaryAttack.baseDps)
  config.primaryAttack.energyUsage = scaleConfig(parameters.primaryAttack.energyUsageFactor, config.primaryAttack.energyUsage) or 0

  -- preprocess melee primary attack config
  if config.primaryAttack.damageConfig then
    config.primaryAttack.damageConfig.knockback = scaleConfig(parameters.primaryAttack.fireTimeFactor, config.primaryAttack.damageConfig.knockback)
  end

  -- preprocess ranged primary attack config
  if config.primaryAttack.projectileParameters then
    config.primaryAttack.projectileType = randomFromList(config.primaryAttack.projectileType, seed, "projectileType")
    config.primaryAttack.projectileCount = randomIntInRange(config.primaryAttack.projectileCount, seed, "projectileCount") or 1
    config.primaryAttack.fireType = randomFromList(config.primaryAttack.fireType, seed, "fireType") or "auto"
    config.primaryAttack.burstCount = randomIntInRange(config.primaryAttack.burstCount, seed, "burstCount")
    config.primaryAttack.burstTime = randomInRange(config.primaryAttack.burstTime, seed, "burstTime")
    config.primaryAttack.projectileParameters.knockback = scaleConfig(parameters.primaryAttack.fireTimeFactor, config.primaryAttack.projectileParameters.knockback)
  end
  
  -- calculate damage level multiplier
  config.damageLevelMultiplier = root.evalFunction("weaponDamageLevelMultiplier", parameters.level or config.level or 1)

  -- build palette swap directives
  config.paletteSwaps = ""
  if builderConfig.palette then
    local palette = root.assetJson(util.absolutePath(directory, builderConfig.palette))
    local selectedSwaps = randomFromList(palette.swaps, seed, "paletteSwaps")
    for k, v in pairs(selectedSwaps) do
      config.paletteSwaps = string.format("%s?replace=%s=%s", config.paletteSwaps, k, v)
    end
  end

  -- merge extra animationCustom
  if builderConfig.animationCustom then
    util.mergeTable(config.animationCustom or {}, builderConfig.animationCustom)
  end

  -- animation parts
  if builderConfig.animationParts then
    if parameters.animationParts == nil then parameters.animationParts = {} end
    for k, v in pairs(builderConfig.animationParts) do
      if parameters.animationParts[k] == nil then
        if type(v) == "table" then
          parameters.animationParts[k] = util.absolutePath(directory, string.gsub(v.path, "<variant>", randomIntInRange({1, v.variants}, seed, "animationPart"..k)))
          if v.paletteSwap then
            parameters.animationParts[k] = parameters.animationParts[k]
          end
        else
          parameters.animationParts[k] = v
        end
      end
    end
  end

  -- set gun part offsets
  local partImagePositions = {}
  if builderConfig.gunParts then
    construct(config, "animationCustom", "animatedParts", "parts")
    local imageOffset = {0,0}
    local gunPartOffset = {0,0}
    for _,part in ipairs(builderConfig.gunParts) do
      local imageSize = root.imageSize(parameters.animationParts[part])
      construct(config.animationCustom.animatedParts.parts, part, "properties")

      imageOffset = vec2.add(imageOffset, {imageSize[1] / 2, 0})
      config.animationCustom.animatedParts.parts[part].properties.offset = {config.baseOffset[1] + imageOffset[1] / 8, config.baseOffset[2]}
      partImagePositions[part] = copy(imageOffset)
      imageOffset = vec2.add(imageOffset, {imageSize[1] / 2, 0})
    end
    config.muzzleOffset = vec2.add(config.baseOffset, vec2.add(config.muzzleOffset or {0,0}, vec2.div(imageOffset, 8)))
  end

  -- elemental fire sounds
  if config.fireSounds then
    construct(config, "animationCustom", "sounds", "fire")
    local sound = randomFromList(config.fireSounds, seed, "fireSound")
    config.animationCustom.sounds.fire = type(sound) == "table" and sound or { sound }
  end

  -- build inventory icon
  if not config.inventoryIcon and parameters.animationParts then
    config.inventoryIcon = jarray()
    local parts = builderConfig.iconDrawables or {}
    for _,partName in pairs(parts) do
      local drawable = {
        image = parameters.animationParts[partName] .. config.paletteSwaps,
        position = partImagePositions[partName]
      }
      table.insert(config.inventoryIcon, drawable)
    end
  end

  -- populate tooltip fields
  config.tooltipFields = {}
  local fireTime = parameters.primaryAttack.fireTime or config.primaryAttack.fireTime
  local baseDps = parameters.primaryAttack.baseDps or config.primaryAttack.baseDps
  local energyUsage = parameters.primaryAttack.energyUsage or config.primaryAttack.energyUsage
  config.tooltipFields.subtitle = parameters.weaponType or config.weaponType
  config.tooltipFields.levelLabel = util.round(parameters.level or config.level or 1, 1)
  config.tooltipFields.dpsLabel = util.round(baseDps * config.damageLevelMultiplier, 1)
  config.tooltipFields.speedLabel = util.round(1 / fireTime, 1)
  config.tooltipFields.damagePerShotLabel = util.round(baseDps * fireTime * config.damageLevelMultiplier, 1)
  config.tooltipFields.energyPerShotLabel = util.round(energyUsage * fireTime, 1)
  if elementalType ~= "physical" then
    config.tooltipFields.damageKindImage = "/interface/elements/"..elementalType..".png"
  end
  if config.altAbility then
    config.tooltipFields.altAbilityTitleLabel = "特殊："
    config.tooltipFields.altAbilityLabel = config.altAbility.name or "unknown"
  end

  -- set price
  config.price = (config.price or 0) * root.evalFunction("itemLevelPriceMultiplier", parameters.level or config.level or 1)

  return config, parameters
end

function scaleConfig(ratio, value)
  if type(value) == "table" then
    return util.lerp(ratio, value[1], value[2])
  else
    return value
  end
end