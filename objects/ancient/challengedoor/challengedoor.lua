function init()
  self.detectArea = entity.configParameter("detectArea")
  self.detectArea[1] = entity.toAbsolutePosition(self.detectArea[1])
  self.detectArea[2] = entity.toAbsolutePosition(self.detectArea[2])

  entity.setAnimationState("portal", "off")
  entity.setLightColor({0, 0, 0, 0})

  storage.uuid = storage.uuid or sb.makeUuid()
  entity.setInteractive(true)

  message.setHandler("onTeleport", function(message, isLocal, data)
      if not entity.configParameter("returnDoor") and not storage.vanishTime then
        storage.vanishTime = world.time() + entity.configParameter("vanishTime")
        if not (entity.animationState("portal") == "open" or entity.animationState("portal") == "on") then
          entity.setAnimationState("portal", "open")
        end
      end
    end)
end

function update(dt)
  if entity.animationState("portal") == "gone" then
    entity.smash()
    return
  elseif storage.vanishTime and world.time() > storage.vanishTime then
    entity.setAnimationState("portal", "vanish")
  end

  local players = world.entityQuery(self.detectArea[1], self.detectArea[2], {
      includedTypes = {"player"},
      boundMode = "CollisionArea"
    })

  if #players > 0 and entity.animationState("portal") == "off" then
    entity.setAnimationState("portal", "open")
    entity.playSound("on");
    entity.setLightColor(entity.configParameter("lightColor", {255, 255, 255}))
  elseif #players == 0 and entity.animationState("portal") == "on" and not storage.vanishTime then
    entity.setAnimationState("portal", "close")
    entity.playSound("off");
    entity.setLightColor({0, 0, 0, 0})
  end
end

function onInteraction(args)
  if entity.configParameter("returnDoor") then
    return { "OpenTeleportDialog", {
        canBookmark = false,
        includePlayerBookmarks = false,
        destinations = { {
          name = "出口传送门",
          planetName = "回到原来的世界…但愿如此！",
          icon = "return",
          warpAction = "Return"
        } }
      }
    }
  else
    return { "OpenTeleportDialog", {
        canBookmark = false,
        includePlayerBookmarks = false,
        destinations = { {
          name = "挑战传送门",
          planetName = "不稳定的口袋空间",
          icon = "default",
          warpAction = string.format("InstanceWorld:challengerooms:%s:%s", storage.uuid, world.threatLevel())
        } }
      }
    }
  end
end