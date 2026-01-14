require "AutoPawnShop_Config"

AutoPawnShop = AutoPawnShop or {}
AutoPawnShop.ClientState = AutoPawnShop.ClientState or { dropTarget = nil }

local function dbg(...)
  local cfg = AutoPawnShop.Config or {}
  if cfg.DebugLoot then
    print("[APS][DBG]", ...)
  end
end

local function safeCall(fn)
  local ok, err = pcall(fn)
  if not ok then
    print("[APS][CLIENT] LootPatch error: " .. tostring(err))
  end
end

-- Find container by coords+type (same as tu helper)
local function findContainerAt(x, y, z, wantedType)
  wantedType = tostring(wantedType or ""):lower()
  if wantedType == "" then return nil end

  local cell = getCell()
  if not cell then return nil end
  local sq = cell:getGridSquare(x, y, z)
  if not sq then return nil end

  local objs = sq:getObjects()
  if not objs then return nil end

  for i = 0, objs:size() - 1 do
    local obj = objs:get(i)
    if obj and obj.getContainer then
      local cont = obj:getContainer()
      if cont and cont.getType and cont:getType() then
        if tostring(cont:getType()):lower() == wantedType then
          return cont
        end
      end
    end
  end
  return nil
end

local function entryInv(entry)
  if not entry then return nil end
  if entry.inventory then return entry.inventory end
  if entry.inv then return entry.inv end
  return entry
end

local function removeVendingDuplicates(page, wantedType)
  wantedType = tostring(wantedType or ""):lower()
  if wantedType == "" then return end
  if not page or not page.backpacks then return end

  local allowed = nil
  local dt = AutoPawnShop.ClientState and AutoPawnShop.ClientState.dropTarget or nil
  if type(dt) == "table" and dt.x and dt.y and dt.z and dt.ctype then
    allowed = findContainerAt(dt.x, dt.y, dt.z, dt.ctype)
  end

  local removed = 0
  local bp = page.backpacks

  -- ArrayList
  if bp.size and bp.get and bp.remove then
    for i = bp:size() - 1, 0, -1 do
      local inv = entryInv(bp:get(i))
      if inv and inv.getType and inv:getType() then
        local t = tostring(inv:getType()):lower()
        if t == wantedType then
          if allowed and inv == allowed then
            -- keep
          else
            bp:remove(i)
            removed = removed + 1
          end
        end
      end
    end
  end

  -- Lua table
  if type(bp) == "table" then
    for i = #bp, 1, -1 do
      local inv = entryInv(bp[i])
      if inv and inv.getType and inv:getType() then
        local t = tostring(inv:getType()):lower()
        if t == wantedType then
          if allowed and inv == allowed then
            -- keep
          else
            table.remove(bp, i)
            removed = removed + 1
          end
        end
      end
    end
  end

  if removed > 0 then
    dbg("LootPatch removed", removed, "duplicate vending entries. allowed=", tostring(allowed))
  end
end

-- Hook global refreshBackpacks (esto es lo que lo hace “persistente”)
Events.OnGameStart.Add(function()
  safeCall(function()
    if not ISInventoryPage or not ISInventoryPage.refreshBackpacks then
      print("[APS][CLIENT] LootPatch: ISInventoryPage.refreshBackpacks not found")
      return
    end

    if ISInventoryPage._APS_patched then
      return
    end
    ISInventoryPage._APS_patched = true

    local _old = ISInventoryPage.refreshBackpacks
    ISInventoryPage.refreshBackpacks = function(self, ...)
      local r = _old(self, ...)
      local cfg = AutoPawnShop.Config or {}
      local wantedType = cfg.CardShopContainerType or "vendingsnack"
      removeVendingDuplicates(self, wantedType)
      return r
    end

    dbg("LootPatch installed (refreshBackpacks hooked)")
  end)
end)
