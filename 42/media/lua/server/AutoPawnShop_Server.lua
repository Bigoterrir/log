-- AutoPawnShop_Server.lua
require "AutoPawnShop_Util"
require "AutoPawnShop_Config"

print("[APS][SERVER] AutoPawnShop_Server.lua LOADED")

AutoPawnShop = AutoPawnShop or {}
local Cfg = AutoPawnShop.Config

-- =========================================================
-- Helpers (server-safe)
-- =========================================================
local function sendToast(playerObj, text)
  sendServerCommand(playerObj, "AutoPawnShop", "Toast", { text = tostring(text or "") })
end

local function mirrorBalanceToPlayerModData(playerObj, balance)
  if not playerObj or not playerObj.getModData then return end
  local md = playerObj:getModData()
  md.APS_balance = tonumber(balance) or 0

  if playerObj.transmitModData then
    playerObj:transmitModData()
  elseif playerObj.sendObjectChange then
    playerObj:sendObjectChange("modData")
  end
end

-- Force container replication so host-client sees AddItem/Remove immediately.
local function forceContainerSync(playerObj, reason)
  if not playerObj then return end
  if playerObj.sendObjectChange then
    playerObj:sendObjectChange("containers")
  end
  sendServerCommand(playerObj, "AutoPawnShop", "InvRefresh", { reason = tostring(reason or "") })
end

local function forceWorldObjectContainerSync(worldObj, playerObj, reason)
  if worldObj then
    if worldObj.sendObjectChange then
      worldObj:sendObjectChange("containers")
    end
    if worldObj.transmitCompleteItemToClients then
      worldObj:transmitCompleteItemToClients()
    end
  end
  if playerObj then
    sendServerCommand(playerObj, "AutoPawnShop", "InvRefresh", { reason = tostring(reason or "worldContainer") })
  end
end

-- ---------------------------------------------------------
-- Username safe (server)
-- ---------------------------------------------------------
local function getUsernameSafe(p)
  if not p then return "Player" end
  local u = nil
  if p.getUsername ~= nil then u = p:getUsername() end
  if (not u or u == "") and p.getDisplayName ~= nil then u = p:getDisplayName() end
  if not u or u == "" then u = "Player" end
  return u
end

-- ---------------------------------------------------------
-- Card fullType from config (NO HARDCODE)
-- ---------------------------------------------------------
local function getCardFullType()
  return (Cfg and Cfg.RequireCreditCardItem) or "Base.CreditCard"
end

-- =========================================================
-- Inventory recurse helpers (SERVER)
-- =========================================================
local function findFirstItemByFullTypeRecurse(inv, fullType)
  if not inv or not fullType then return nil end

  local items = inv.getItems and inv:getItems() or nil
  if not items then return nil end

  for i = 0, items:size() - 1 do
    local it = items:get(i)

    if it and it.getFullType and it:getFullType() == fullType then
      return it
    end

    if it and it.IsInventoryContainer and it:IsInventoryContainer() then
      local childInv = it.getInventory and it:getInventory() or nil
      local found = findFirstItemByFullTypeRecurse(childInv, fullType)
      if found then return found end
    end
  end

  return nil
end

local function findAllItemsByFullTypeRecurse(inv, fullType, out)
  out = out or {}
  if not inv or not fullType then return out end

  local items = inv.getItems and inv:getItems() or nil
  if not items then return out end

  for i = 0, items:size() - 1 do
    local it = items:get(i)

    if it and it.getFullType and it:getFullType() == fullType then
      table.insert(out, it)
    end

    if it and it.IsInventoryContainer and it:IsInventoryContainer() then
      local childInv = it.getInventory and it:getInventory() or nil
      findAllItemsByFullTypeRecurse(childInv, fullType, out)
    end
  end

  return out
end

-- ---------------------------------------------------------
-- Find credit cards (recursive) - CONFIG AWARE
-- ---------------------------------------------------------
local function getAllCreditCards(playerObj)
  if not playerObj or not playerObj.getInventory then return {} end
  local inv = playerObj:getInventory()
  if not inv then return {} end
  return findAllItemsByFullTypeRecurse(inv, getCardFullType(), {})
end

local function findFirstCreditCard(playerObj)
  if not playerObj or not playerObj.getInventory then return nil end
  local inv = playerObj:getInventory()
  if not inv then return nil end
  return findFirstItemByFullTypeRecurse(inv, getCardFullType())
end

local function findFirstUnlinkedCreditCard(playerObj)
  local cards = getAllCreditCards(playerObj)
  if not cards or #cards == 0 then return nil end

  local username = getUsernameSafe(playerObj)

  -- Prioriza una que NO sea del jugador (o no tenga owner)
  for _, card in ipairs(cards) do
    local md = card.getModData and card:getModData() or {}
    local owner = md.APS_owner
    if (not owner) or tostring(owner) ~= tostring(username) then
      return card
    end
  end

  return cards[1]
end

-- ---------------------------------------------------------
-- Apply link data to card (SERVER AUTHORITATIVE)
-- ---------------------------------------------------------
local function applyLinkToCard(playerObj, cardItem)
  if not playerObj or not cardItem then return false end

  local username = getUsernameSafe(playerObj)
  local md = cardItem.getModData and cardItem:getModData() or nil
  if not md then return false end

  -- idempotent: already linked
  if md.APS_owner and tostring(md.APS_owner) == tostring(username) then
    return true
  end

  md.APS_owner = username
  md.APS_displayName = "Tarjeta de Credito de " .. tostring(username)

  -- Rename best-effort
  if cardItem.setCustomName then
    pcall(function() cardItem:setCustomName(true) end)
  end
  if cardItem.setName then
    pcall(function() cardItem:setName(md.APS_displayName) end)
  end

  -- replicate item modData
  if cardItem.transmitModData then
    pcall(function() cardItem:transmitModData() end)
  end

  -- replicate player containers/modData so UI updates fast
  if playerObj.sendObjectChange then
    pcall(function()
      playerObj:sendObjectChange("modData")
      playerObj:sendObjectChange("containers")
    end)
  elseif playerObj.transmitModData then
    pcall(function() playerObj:transmitModData() end)
  end

  return true
end

local function syncState(playerObj)
  if not playerObj then return end

  local bal = AutoPawnShop.GetBalance(playerObj) or 0
  local has = AutoPawnShop.HasCreditCard(playerObj) == true
  local lnk = AutoPawnShop.IsCardLinkedToPlayer(playerObj) == true

  mirrorBalanceToPlayerModData(playerObj, bal)

  sendServerCommand(playerObj, "AutoPawnShop", "SyncState", {
    balance = bal,
    hasCard = has,
    linked  = lnk,
  })
end

local function clampInt(n, minv, maxv)
  n = tonumber(n) or 0
  n = math.floor(n)
  if n < minv then return minv end
  if n > maxv then return maxv end
  return n
end

local function getAllItemsOfFullTypeRecurse(inv, fullType)
  if not inv or not fullType then return nil end

  if inv.getAllEvalRecurse then
    return inv:getAllEvalRecurse(function(it)
      return it and it.getFullType and it:getFullType() == fullType
    end)
  end

  if inv.getItemsFromFullType then
    return inv:getItemsFromFullType(fullType)
  end

  return nil
end

local function hasCardAndLinked(playerObj, mustBeLinked)
  if not AutoPawnShop.HasCreditCard(playerObj) then
    return false, "Missing credit card."
  end
  if mustBeLinked and not AutoPawnShop.IsCardLinkedToPlayer(playerObj) then
    return false, "Your credit card is not linked. Right-click it and Link."
  end
  return true, nil
end

-- =========================================================
-- World container finder (by ContainerType) - closest
-- =========================================================
local function findNearbyContainerByTypeClosest(playerObj, radius, wantedType)
  radius = tonumber(radius) or 2
  wantedType = tostring(wantedType or ""):lower()
  if wantedType == "" then return nil, nil end
  if not playerObj or not playerObj.getSquare then return nil, nil end

  local sq = playerObj:getSquare()
  if not sq then return nil, nil end

  local cell = getCell()
  if not cell then return nil, nil end

  local cx, cy, cz = sq:getX(), sq:getY(), sq:getZ()
  local bestCont, bestObj, bestDist2 = nil, nil, 999999

  for dx = -radius, radius do
    for dy = -radius, radius do
      local s2 = cell:getGridSquare(cx + dx, cy + dy, cz)
      if s2 then
        local objs = s2:getObjects()
        if objs then
          for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if obj and obj.getContainer then
              local cont = obj:getContainer()
              if cont and cont.getType and cont:getType() then
                if tostring(cont:getType()):lower() == wantedType then
                  local dist2 = dx*dx + dy*dy
                  if dist2 < bestDist2 then
                    bestDist2 = dist2
                    bestCont = cont
                    bestObj  = obj
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return bestCont, bestObj
end

-- =========================================================
-- Cached drop target (per player) -> keep SAME vending
-- =========================================================
local function getCachedDropTarget(playerObj)
  if not playerObj or not playerObj.getModData then return nil, nil end
  local md = playerObj:getModData()
  local drop = md and md.APS_drop
  if type(drop) ~= "table" then return nil, nil end
  if drop.x == nil or drop.y == nil or drop.z == nil or drop.type == nil then return nil, nil end

  local cell = getCell()
  if not cell then return nil, nil end
  local s = cell:getGridSquare(drop.x, drop.y, drop.z)
  if not s then return nil, nil end

  local objs = s:getObjects()
  if not objs then return nil, nil end

  local wanted = tostring(drop.type):lower()
  for i = 0, objs:size() - 1 do
    local obj = objs:get(i)
    if obj and obj.getContainer then
      local cont = obj:getContainer()
      if cont and cont.getType and cont:getType() then
        if tostring(cont:getType()):lower() == wanted then
          return cont, obj
        end
      end
    end
  end

  return nil, nil
end

local function setCachedDropTarget(playerObj, worldObj, wantedType)
  if not playerObj or not playerObj.getModData or not worldObj then return end
  local sq = worldObj.getSquare and worldObj:getSquare() or nil
  if not sq then return end
  local md = playerObj:getModData()
  md.APS_drop = { x = sq:getX(), y = sq:getY(), z = sq:getZ(), type = tostring(wantedType or "") }
end

local function sendDropTarget(playerObj, worldObj, wantedType)
  if not playerObj or not worldObj then return end
  local sq = worldObj.getSquare and worldObj:getSquare() or nil
  if not sq then return end

  sendServerCommand(playerObj, "AutoPawnShop", "SetDropTarget", {
    x = sq:getX(),
    y = sq:getY(),
    z = sq:getZ(),
    ctype = tostring(wantedType or ""),
  })
end

-- =========================================================
-- SELL (SERVER) - deterministic remove (no over-remove)
-- =========================================================
local function sellSelectedJewels(playerObj, args)
  if not playerObj then return end
  args = args or {}

  if type(args.toSell) ~= "table" then
    sendToast(playerObj, "Invalid sell request.")
    syncState(playerObj)
    return
  end

  local ok, err = hasCardAndLinked(playerObj, true)
  if not ok then
    sendToast(playerObj, err or "You need a Credit Card to deposit the money.")
    syncState(playerObj)
    return
  end

  local inv = playerObj:getInventory()
  if not inv then
    sendToast(playerObj, "Inventory not available.")
    syncState(playerObj)
    return
  end

  local totalValue, totalRemoved = 0, 0
  local removedByType = {}

  local function removeN(fullType, n)
    local removed = 0
    for i = 1, n do
      local it = findFirstItemByFullTypeRecurse(inv, fullType)
      if not it then break end

      local cont = it.getContainer and it:getContainer() or inv
      if cont and cont.Remove then
        local okRemove = false
        pcall(function()
          cont:Remove(it)
          okRemove = true
        end)
        if okRemove then
          removed = removed + 1
        else
          break
        end
      else
        break
      end
    end
    return removed
  end

for fullType, reqCount in pairs(args.toSell) do
  if type(fullType) == "string" then
    local price = (AutoPawnShop and AutoPawnShop.GetJewelPrice) and AutoPawnShop.GetJewelPrice(fullType) or nil
    price = tonumber(price) or 0

    if price > 0 then
      local want = clampInt(reqCount, 0, 500)
      if want > 0 then
        local removed = removeN(fullType, want)
        if removed > 0 then
          totalRemoved = totalRemoved + removed
          totalValue   = totalValue + (price * removed)
          removedByType[fullType] = (removedByType[fullType] or 0) + removed
        end
      end
    end
  end
end


  if totalRemoved <= 0 then
    sendToast(playerObj, "No jewels were sold (none available or invalid selection).")
    syncState(playerObj)
    return
  end

  local bal = AutoPawnShop.GetBalance(playerObj) or 0
  if bal < 0 then bal = 0 end
  local newBal = bal + totalValue

  AutoPawnShop.SetBalance(playerObj, newBal)
  mirrorBalanceToPlayerModData(playerObj, newBal)

  sendServerCommand(playerObj, "AutoPawnShop", "SellResult", {
    removedByType = removedByType,
    totalRemoved  = totalRemoved,
    totalValue    = totalValue,
    balance       = newBal,
  })

  if playerObj.sendObjectChange then
    playerObj:sendObjectChange("wornItems")
    playerObj:sendObjectChange("containers")
  end

  forceContainerSync(playerObj, "sell")
  sendToast(playerObj, "Sold " .. tostring(totalRemoved) .. ". Added $" .. tostring(totalValue) .. " to card.")
  syncState(playerObj)
end

-- =========================================================
-- BUY (deposit into CardShopContainerType)
-- =========================================================
local function isCatalogEntry(itemFullType, price)
  if type(itemFullType) ~= "string" then return false end
  if type(price) ~= "number" or price <= 0 then return false end
  if type(Cfg.ShopCatalog) ~= "table" then return false end

  for _, entry in ipairs(Cfg.ShopCatalog) do
    if entry and entry.item == itemFullType and tonumber(entry.price) == price then
      return true
    end
  end
  return false
end

local function buyItem(playerObj, args)
  if not playerObj then return end
  args = args or {}

  local item  = args.item
  local price = tonumber(args.price) or 0
  local qty   = clampInt(args.qty, 1, 50)

  if type(item) ~= "string" or price <= 0 then
    sendToast(playerObj, "Invalid purchase request.")
    syncState(playerObj)
    return
  end

  local ok, err = hasCardAndLinked(playerObj, true)
  if not ok then
    sendToast(playerObj, err or "You need a Credit Card to buy here.")
    syncState(playerObj)
    return
  end

  if not isCatalogEntry(item, price) then
    sendToast(playerObj, "Item not in catalog.")
    syncState(playerObj)
    return
  end

  local bal = AutoPawnShop.GetBalance(playerObj) or 0
  if bal < 0 then bal = 0 end

  local totalCost = price * qty
  if bal < totalCost then
    sendToast(playerObj, "Insufficient balance. Need $" .. tostring(totalCost) .. ", you have $" .. tostring(bal) .. ".")
    syncState(playerObj)
    return
  end

  local radius = tonumber(Cfg.DropRadius) or 3
  local wantedType = Cfg.CardShopContainerType

  local targetInv, targetObj = getCachedDropTarget(playerObj)

  if not targetInv then
    targetInv, targetObj = findNearbyContainerByTypeClosest(playerObj, radius, wantedType)
    if targetObj then
      setCachedDropTarget(playerObj, targetObj, wantedType)
    end
  end

  if not targetInv then
    targetInv = playerObj:getInventory()
    targetObj = nil
  end

  if not targetInv then
    sendToast(playerObj, "No valid container found to deposit items.")
    syncState(playerObj)
    return
  end

  local added = 0
  for i = 1, qty do
    local it = targetInv:AddItem(item)
    if it then added = added + 1 else break end
  end

  if added <= 0 then
    sendToast(playerObj, "Purchase failed: item '" .. tostring(item) .. "' not found/failed.")
    syncState(playerObj)
    return
  end

  local charged = price * added
  local newBal = bal - charged
  if newBal < 0 then newBal = 0 end

  AutoPawnShop.SetBalance(playerObj, newBal)
  mirrorBalanceToPlayerModData(playerObj, newBal)

  if targetObj then
    sendDropTarget(playerObj, targetObj, wantedType)
    forceWorldObjectContainerSync(targetObj, playerObj, "buy->cardshop(" .. tostring(wantedType) .. ")")
  else
    forceContainerSync(playerObj, "buy->inventory")
  end

  sendToast(playerObj, "Purchased x" .. tostring(added) .. " " .. tostring(item) .. " for $" .. tostring(charged) .. ". Delivered to vending.")
  syncState(playerObj)
end

-- =========================================================
-- LINK CARD (SERVER AUTHORITATIVE)
-- Commands supported:
--   LinkCard (old)
--   LinkFirstCardToPlayer (old)
--   LinkFirstCard (new from updated client)
-- =========================================================
local function linkCard(playerObj, args)
  if not playerObj then return end

  if AutoPawnShop.IsCardLinkedToPlayer and AutoPawnShop.IsCardLinkedToPlayer(playerObj) == true then
    sendToast(playerObj, "You already have a linked card.")
    syncState(playerObj)
    return
  end

  local card = findFirstUnlinkedCreditCard(playerObj) or findFirstCreditCard(playerObj)
  if not card then
    sendToast(playerObj, "No credit card in your inventory.")
    syncState(playerObj)
    return
  end

  local ok = applyLinkToCard(playerObj, card)
  if not ok then
    sendToast(playerObj, "Failed to link card (server).")
    syncState(playerObj)
    return
  end

  forceContainerSync(playerObj, "link")
  sendToast(playerObj, "Card linked to you.")
  syncState(playerObj)
end

-- =========================================================
-- COMMAND ROUTER
-- =========================================================
local function onClientCommand(module, command, playerObj, args)
  if module ~= "AutoPawnShop" then return end

  if command == "RequestSync" then
    syncState(playerObj)

  elseif command == "SellSelectedJewels" then
    sellSelectedJewels(playerObj, args)

  elseif command == "BuyItem" then
    buyItem(playerObj, args)

  elseif command == "LinkCard"
      or command == "LinkFirstCardToPlayer"
      or command == "LinkFirstCard" then
    linkCard(playerObj, args)

  else
    sendToast(playerObj, "Unknown command: " .. tostring(command))
    syncState(playerObj)
  end
end

Events.OnClientCommand.Add(onClientCommand)
