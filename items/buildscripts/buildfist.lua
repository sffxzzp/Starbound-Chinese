require "/scripts/util.lua"

function build(directory, config, parameters, level)
  -- load and merge combo finisher
  local comboFinisher = parameters.comboFinisher or config.comboFinisher
  if comboFinisher then
    local comboFinisherConfig = root.assetJson(comboFinisher)
    util.mergeTable(config, comboFinisherConfig)
  end

  -- calculate damage level multiplier
  config.damageLevelMultiplier = root.evalFunction("weaponDamageLevelMultiplier", parameters.level or config.level or 1)

  config.tooltipFields = {}
  config.tooltipFields.subtitle = "Fist Weapon"
  config.tooltipFields.speedLabel = util.round(1 / config.primaryAttack.fireTime, 1)
  config.tooltipFields.damagePerShotLabel = util.round(config.primaryAttack.baseDps * config.primaryAttack.fireTime * config.damageLevelMultiplier, 1)
  if config.comboFinisher then
    config.tooltipFields.comboFinisherTitleLabel = "终结技："
    config.tooltipFields.comboFinisherLabel = config.comboFinisher.name or "unknown"
  end

  return config, parameters
end