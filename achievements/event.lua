require "/scripts/util.lua"
require("/scripts/replaceTags.lua")

local tagFieldTypes = { "number", "string", "boolean" }
local operators = {}

function event(name, fields)
  for _,stat in ipairs(config.getParameter("stats")) do

    local fieldNames = util.stringTags(stat.name)
    if allFieldsExist(fields, fieldNames, tagFieldTypes) and fieldValuesPresent(fields, stat.requiredValues) then

      local statName = generateStatName(stat.name, fields)
      local op = operators[stat.op]
      assert(stat.type ~= nil)
      assert(op ~= nil)

      local currentValue = statistics.stat(statName)
      local newValue = op(stat, currentValue, fields)
      statistics.setStat(statName, stat.type, newValue)
    end
  end
end

function fieldValuesPresent(fields, requiredValues)
  for key, value in pairs(requiredValues or {}) do
    if not compare(fields[key], value) then
      return false
    end
  end
  return true
end

function allFieldsExist(fields, fieldNames, validTypes)
  for _,fieldName in ipairs(fieldNames) do
    local fieldValue = fields[fieldName]
    if fieldValue == nil then
      return false
    end
    if validTypes and not contains(validTypes, type(fieldValue)) then
      return false
    end
  end
  return true
end

function generateStatName(statNameTemplate, eventFields)
  local tags = util.map(eventFields, bind(string.format, "%s"))
  return sb_replaceTags(statNameTemplate, tags)
end

function makeOperator(defaults, op)
  defaults = parseArgs(defaults, {
      default = 0,
      field = nil,
      value = nil
    })
  return function (args, currentValue, fields)
    args = parseArgs(args, defaults)
    currentValue = currentValue or args.default

    if args.field and fields[args.field] ~= nil then
      return op(args, currentValue, fields[args.field])
    end

    if args.value then
      return op(args, currentValue, args.value)
    end

    return currentValue
  end
end

operators.increment = makeOperator({ value = 1 }, function (args, a, b)
  return a + b
end)

operators.decrement = makeOperator({ value = 1, minimum = nil }, function (args, a, b)
  local result = a - b
  if not args.minimum then
    return result
  end
  return math.max(result, args.minimum)
end)

operators.sum = makeOperator({}, function (args, a, b)
  return a + b
end)

operators.max = makeOperator({}, function (args, a, b)
  return math.max(a, b)
end)

operators.min = makeOperator({}, function (args, a, b)
  return math.min(a, b)
end)

operators.set = makeOperator({}, function (args, currentValue, newValue)
  return newValue
end)

operators.insert = makeOperator({ default = {} }, function (args, currentValue, newValue)
  currentValue = currentValue or {}
  if not contains(currentValue, newValue) then
    table.insert(currentValue, newValue)
  end
  return currentValue
end)
