require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/versioningutils.lua"

function build(directory, config, parameters, level)
  -- load and merge alt ability
  local altAbilitySource = parameters.altAbilitySource or config.altAbilitySource
  if altAbilitySource then
    local altAbilityConfig = root.assetJson(altAbilitySource)
    util.mergeTable(config, altAbilityConfig)
  end

  -- elemental type and config (for alt ability)
  replacePatternInData(config, nil, "<elementalType>", config.elementalType)
  if config.altAbility and config.altAbility.elementalConfig then
    util.mergeTable(config.altAbility, config.altAbility.elementalConfig[config.elementalType])
  end

  -- calculate damage level multiplier
  config.damageLevelMultiplier = root.evalFunction("weaponDamageLevelMultiplier", config.level or 1)

  -- palette swaps
  config.paletteSwaps = ""
  if config.palette then
    local palette = root.assetJson(util.absolutePath(directory, config.palette))
    local selectedSwaps = palette.swaps[parameters.colorIndex or config.colorIndex or 1]
    for k, v in pairs(selectedSwaps) do
      config.paletteSwaps = string.format("%s?replace=%s=%s", config.paletteSwaps, k, v)
    end
  end
  config.inventoryIcon = config.inventoryIcon .. config.paletteSwaps

  -- gun offsets
  if config.baseOffset then
    construct(config, "animationCustom", "animatedParts", "parts", "middle", "properties")
    config.animationCustom.animatedParts.parts.middle.properties.offset = config.baseOffset
    if config.muzzleOffset then
      config.muzzleOffset = vec2.add(config.muzzleOffset, config.baseOffset)
    end
  end

  -- populate tooltip fields
  config.tooltipFields = {}
  config.tooltipFields.subtitle = parameters.weaponType or config.weaponType
  config.tooltipFields.levelLabel = util.round(config.level or 1, 1)
  config.tooltipFields.dpsLabel = util.round(config.primaryAttack.baseDps * config.damageLevelMultiplier, 1)
  config.tooltipFields.speedLabel = util.round(1 / config.primaryAttack.fireTime, 1)
  config.tooltipFields.damagePerShotLabel = util.round(config.primaryAttack.baseDps * config.primaryAttack.fireTime * config.damageLevelMultiplier, 1)
  config.tooltipFields.energyPerShotLabel = util.round((config.primaryAttack.energyUsage or 0) * config.primaryAttack.fireTime, 1)
  if config.elementalType ~= "physical" then
    config.tooltipFields.damageKindImage = "/interface/elements/"..config.elementalType..".png"
  end
  if config.altAbility then
    config.tooltipFields.altAbilityTitleLabel = "特殊："
    config.tooltipFields.altAbilityLabel = config.altAbility.name or "unknown"
  end

  -- set price
  -- TODO: should this be handled elsewhere?
  config.price = (config.price or 0) * root.evalFunction("itemLevelPriceMultiplier", config.level or 1)

  return config, parameters
end