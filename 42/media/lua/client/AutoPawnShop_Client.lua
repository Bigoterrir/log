-- AutoPawnShop_Client.lua (COMPLETO)  ✅ MODIFICADO (MP+SP) + FIX "LINKING" PEGADO EN SP
-- FIXES:
-- 1) SP: Link NO queda pegado en "Linking..." (watchdog + finally)
-- 2) MP/B42: NO llama ISInventoryPaneContextMenu.unequipItem (evita "expected int got Clothing")
-- 3) Refresh tarjeta: busca recurse (bolsos/mochilas)
-- 4) OnGameStart: solo pide sync si isClient()
-- 5) ✅ SP BUY: compra local y deposita en vending cercano + setDropTarget local
-- 6) ✅ Anti-prune: NO sanitiza vendings si contReal == nil (evita allowed=nil)
-- 7) ✅ SP FALLBACK: balance/link/price funcionan aunque APIs estén en /server

require "AutoPawnShop_Util"
require "AutoPawnShop_Config"
require "AutoPawnShop_UI"

AutoPawnShop = AutoPawnShop or {}
AutoPawnShop.ClientState = AutoPawnShop.ClientState or {
  balance = 0,
  hasCard = false,
  linked  = false,
  dropTarget = nil, -- {x,y,z,ctype}

  -- ✅ linking watchdog (SP)
  _linking = false,
  _linkingTicks = 0,
}
print("### APS MARK: CLIENT v999 ###")

-- =========================================================
-- Helpers
-- =========================================================
local function safeCall(fn)
  if type(fn) ~= "function" then return false end
  local ok, err = pcall(fn)
  if not ok then
    print("[APS][CLIENT] safeCall error: " .. tostring(err))
  end
  return ok
end

local function cfg()
  AutoPawnShop.Config = AutoPawnShop.Config or {}
  return AutoPawnShop.Config
end

local function dbg(...)
  if cfg().DebugLoot == true then
    print("[APS][DBG]", ...)
  end
end

local function refreshAPSUI()
  if AutoPawnShopUI and AutoPawnShopUI.shopPanel and AutoPawnShopUI.shopPanel.updateCardStateUI then
    safeCall(function() AutoPawnShopUI.shopPanel:updateCardStateUI() end)
  end
  if AutoPawnShopUI and AutoPawnShopUI.pawnPanel and AutoPawnShopUI.pawnPanel.refreshLists then
    safeCall(function() AutoPawnShopUI.pawnPanel:refreshLists() end)
  end
end

-- =========================================================
-- Linking UI flag helpers (robusto)
-- =========================================================
local function setUILinking(flag)
  safeCall(function()
    AutoPawnShop.ClientState._linking = (flag == true)
    AutoPawnShop.ClientState._linkingTicks = (flag == true) and 120 or 0 -- ✅ 120 ticks failsafe

    if AutoPawnShopUI and AutoPawnShopUI.shopPanel then
      if AutoPawnShopUI.shopPanel.setLinking then
        AutoPawnShopUI.shopPanel:setLinking(flag == true)
      end
      if AutoPawnShopUI.shopPanel.isLinking ~= nil then
        AutoPawnShopUI.shopPanel.isLinking = (flag == true)
      end
    end
  end)
end

local function clearUILinkingSafe()
  setUILinking(false)
end

-- =========================================================
-- Recursive inventory helpers
-- =========================================================
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
      local child = it.getInventory and it:getInventory() or nil
      findAllItemsByFullTypeRecurse(child, fullType, out)
    end
  end
  return out
end

local function getAllItemsOfFullTypeRecurse(inv, fullType)
  if not inv or not fullType then return nil end
  if inv.getAllEvalRecurse ~= nil then
    return inv:getAllEvalRecurse(function(it)
      return it and it.getFullType ~= nil and it:getFullType() == fullType
    end)
  end
  if inv.getItemsFromFullType ~= nil then
    return inv:getItemsFromFullType(fullType)
  end
  return nil
end

local function countItemsLocal(inv, fullType)
  local items = getAllItemsOfFullTypeRecurse(inv, fullType)
  return (items and items.size and items:size()) or 0
end

-- =========================================================
-- ✅ SP FALLBACK APIs (balance / link / price)
-- =========================================================
local function spGetBalance(p)
  if AutoPawnShop.GetBalance then
    return tonumber(AutoPawnShop.GetBalance(p) or 0) or 0
  end
  local md = p and p.getModData and p:getModData() or nil
  return tonumber(md and md.APS_balance) or 0
end

local function spSetBalance(p, v)
  v = tonumber(v) or 0
  if v < 0 then v = 0 end

  if AutoPawnShop.SetBalance then
    pcall(function() AutoPawnShop.SetBalance(p, v) end)
  end

  if p and p.getModData then
    local md = p:getModData()
    md.APS_balance = v
  end
  return v
end

local function spGetJewelPrice(fullType)
  if AutoPawnShop.GetJewelPrice then
    return tonumber(AutoPawnShop.GetJewelPrice(fullType) or 0) or 0
  end
  if AutoPawnShop and AutoPawnShop.Prices and AutoPawnShop.Prices[fullType] then
    return tonumber(AutoPawnShop.Prices[fullType]) or 0
  end
  return 0
end

local function spLinkFirstCardLocal(p)
  if not p or not p.getInventory then return false end
  local inv = p:getInventory()
  if not inv then return false end

  local cardType = cfg().RequireCreditCardItem or "Base.CreditCard"
  if type(cardType) ~= "string" or cardType == "" then cardType = "Base.CreditCard" end

  local cards = findAllItemsByFullTypeRecurse(inv, cardType, {})
  if #cards <= 0 then return false end

  local owner = "Player"
  if p.getUsername ~= nil then owner = p:getUsername() end
  if (not owner or owner == "") and p.getDisplayName ~= nil then owner = p:getDisplayName() end
  if not owner or owner == "" then owner = "Player" end

  for _, it in ipairs(cards) do
    if it and it.getModData then
      local md = it:getModData()
      md.APS_owner = owner
      if it.setName then pcall(function() it:setName("Tarjeta de Credito de " .. owner) end) end
      if it.setCustomName then pcall(function() it:setCustomName(true) end) end
      return true
    end
  end
  return false
end

-- =========================================================
-- Unequip (CLIENT) - SAFE (NO vanilla unequipItem)
-- =========================================================
local function tryUnequipClient(p, item)
  if not p or not item then return end

  safeCall(function()
    if p.isEquipped and p:isEquipped(item) then
      if p.removeFromHands then p:removeFromHands(item) end
    end
  end)

  safeCall(function()
    if p.getWornItems then
      local wi = p:getWornItems()
      if wi and wi.remove then
        wi:remove(item)
      end
    end
  end)
end

local function removeItemsLocalSafe(inv, fullType, wantCount)
  if not inv or not fullType then return 0 end
  local want = tonumber(wantCount) or 0
  if want <= 0 then return 0 end

  local items = getAllItemsOfFullTypeRecurse(inv, fullType)
  local have = items and items:size() or 0
  if have <= 0 then return 0 end

  local take = math.min(have, want)
  local p = getPlayer()

  local removed = 0
  for idx = have - 1, have - take, -1 do
    local it = items:get(idx)
    if it then
      tryUnequipClient(p, it)
      inv:Remove(it)
      removed = removed + 1
    end
  end
  return removed
end

-- =========================================================
-- SAFE inventory refresh
-- =========================================================
local function forceInventoryRefreshSafe()
  refreshAPSUI()

  safeCall(function()
    local page = getPlayerInventory and getPlayerInventory(0) or nil
    if page and page.refreshContainer then
      page:refreshContainer()
    elseif page and page.refreshBackpacks then
      page:refreshBackpacks()
    end
  end)

  safeCall(function()
    local loot = getPlayerLoot and getPlayerLoot(0) or nil
    if loot and loot.refreshContainer then
      loot:refreshContainer()
    elseif loot and loot.refreshBackpacks then
      loot:refreshBackpacks()
    end
  end)
end

-- =========================================================
-- Find container in world by coords + type
-- =========================================================
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

-- =========================================================
-- Local closest vending finder (CLIENT)  ✅
-- =========================================================
local function findNearbyContainerByTypeClosestClient(playerObj, radius, wantedType)
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
-- NEVER leave loot pane pointing to nil
-- =========================================================
local function ensureLootPaneHasValidInventory()
  safeCall(function()
    local loot = getPlayerLoot and getPlayerLoot(0) or nil
    local p = getPlayer()
    if not loot or not p or not p.getInventory then return end

    local inv = p:getInventory()
    if not inv then return end

    if loot.inventoryPane then
      if loot.inventoryPane.inventory == nil then
        if loot.inventoryPane.setInventory then
          loot.inventoryPane:setInventory(inv)
        else
          loot.inventoryPane.inventory = inv
        end
      end
    end
  end)
end

-- =========================================================
-- Detect transfers busy
-- =========================================================
local function isTransferBusy()
  local p = getPlayer()
  if not p then return false end

  local q = ISTimedActionQueue
          and ISTimedActionQueue.getTimedActionQueue
          and ISTimedActionQueue.getTimedActionQueue(p)
          or nil
  if not q or not q.queue then return false end

  for i = 1, #q.queue do
    local a = q.queue[i]
    if a and a.Type == "ISInventoryTransferAction" then
      return true
    end
  end
  return false
end

-- =========================================================
-- Aggressive vending sanitize
-- =========================================================
local function sanitizeLootVending(contReal, wantedTypeLower)
  wantedTypeLower = tostring(wantedTypeLower or ""):lower()
  if wantedTypeLower == "" then return end

  safeCall(function()
    local loot = getPlayerLoot and getPlayerLoot(0) or nil
    if not loot then return end

    local function invFromEntry(entry)
      if not entry then return nil end
      if entry.inventory then return entry.inventory end
      if entry.inv then return entry.inv end
      return entry
    end

    local function isVendingInv(inv)
      if not inv or not inv.getType or not inv:getType() then return false end
      return tostring(inv:getType()):lower() == wantedTypeLower
    end

    local function pruneList(list)
      if not list then return end

      if list.size and list.get and list.remove then
        local keepIdx = -1
        if contReal then
          for i = 0, list:size() - 1 do
            local inv = invFromEntry(list:get(i))
            if inv == contReal then keepIdx = i break end
          end
        end

        for i = list:size() - 1, 0, -1 do
          local inv = invFromEntry(list:get(i))
          if isVendingInv(inv) then
            if (not contReal) or (i ~= keepIdx) then
              dbg("LootPatch removed duplicate vending entry. allowed=", tostring(contReal))
              list:remove(i)
            end
          end
        end
        return
      end

      if type(list) == "table" then
        local keepIndex = nil
        if contReal then
          for i = 1, #list do
            local inv = invFromEntry(list[i])
            if inv == contReal then keepIndex = i break end
          end
        end

        for i = #list, 1, -1 do
          local inv = invFromEntry(list[i])
          if isVendingInv(inv) then
            if (not contReal) or (i ~= keepIndex) then
              dbg("LootPatch removed duplicate vending entry. allowed=", tostring(contReal))
              table.remove(list, i)
            end
          end
        end
      end
    end

    pruneList(loot.backpacks)
    pruneList(loot.lootContainers)
    pruneList(loot.inventoryPanes)

    if contReal and loot.inventoryPane then
      if loot.inventoryPane.setInventory then
        loot.inventoryPane:setInventory(contReal)
      else
        loot.inventoryPane.inventory = contReal
      end
    end

    ensureLootPaneHasValidInventory()
  end)
end

-- =========================================================
-- Card local refresh (recurse)
-- =========================================================
local function refreshCardLocalState()
  local p = getPlayer()
  if not p or not p.getInventory then return end
  local inv = p:getInventory()
  if not inv then return end

  local cardType = cfg().RequireCreditCardItem or "Base.CreditCard"
  if type(cardType) ~= "string" or cardType == "" then return end

  local cards = findAllItemsByFullTypeRecurse(inv, cardType, {})
  local hasCard = (#cards > 0)
  local linked = false

  if hasCard then
    for _, it in ipairs(cards) do
      if it and it.getModData then
        local md = it:getModData()
        if md and md.APS_owner and tostring(md.APS_owner) ~= "" then
          linked = true
          local ownerName = tostring(md.APS_owner)
          if it.setName then pcall(function() it:setName("Tarjeta de Credito de " .. ownerName) end) end
          if it.setCustomName then pcall(function() it:setCustomName(true) end) end
          break
        end
      end
    end
  end

  AutoPawnShop.ClientState.hasCard = hasCard
  AutoPawnShop.ClientState.linked  = linked

  AutoPawnShopUI_SetState(
    AutoPawnShop.ClientState.balance,
    AutoPawnShop.ClientState.hasCard,
    AutoPawnShop.ClientState.linked
  )
  refreshAPSUI()

  -- ✅ si ya linkeó, asegurate de apagar linking UI
  if linked and AutoPawnShop.ClientState._linking == true then
    clearUILinkingSafe()
  end
end

-- =========================================================
-- Card poll
-- =========================================================
local _apsCardPollTicks = 0
local function scheduleCardPoll(ticks)
  _apsCardPollTicks = tonumber(ticks) or 60
end

local function tickCardPoll()
  if _apsCardPollTicks <= 0 then return end
  _apsCardPollTicks = _apsCardPollTicks - 1
  refreshCardLocalState()
  if AutoPawnShop.ClientState.linked then
    _apsCardPollTicks = 0
  end
end

-- =========================================================
-- BUY cleanup retries  ✅ anti-prune nil
-- =========================================================
local _apsCleanupTries = 0
local _apsCleanupTicks = 0

local function scheduleVendingCleanupTicks(ticks)
  _apsCleanupTicks = tonumber(ticks) or 30
  _apsCleanupTries = 0
end

local function tickVendingCleanup()
  if _apsCleanupTicks <= 0 then return end
  _apsCleanupTicks = _apsCleanupTicks - 1

  if _apsCleanupTries >= 10 then
    _apsCleanupTicks = 0
    return
  end

  if isTransferBusy() then
    dbg("cleanup skipped: transfer busy")
    return
  end

  _apsCleanupTries = _apsCleanupTries + 1

  local wantedTypeLower = tostring(cfg().CardShopContainerType or ""):lower()
  if wantedTypeLower == "" then return end

  local dt = AutoPawnShop.ClientState.dropTarget
  local contReal = nil

  if type(dt) == "table" and dt.x and dt.y and dt.z and dt.ctype then
    contReal = findContainerAt(dt.x, dt.y, dt.z, dt.ctype)
  end

  -- ✅ si no tengo contReal, NO sanitizo (evita allowed=nil y romper loot lists)
  if not contReal then
    dbg("cleanup: no contReal yet -> skip sanitize")
    return
  end

  dbg("cleanup try=", _apsCleanupTries, "contReal=", tostring(contReal))
  sanitizeLootVending(contReal, wantedTypeLower)
end

-- =========================================================
-- SELL cleanup (SAFE & decremental)
-- =========================================================
local _apsSellPending = nil
local _apsSellCleanupTicks = 0
local _apsSellCleanupTries = 0

local _apsLastSellSig = nil
local _apsLastSellSigUntilMs = 0

local function makeSellSig(args)
  local b  = tostring(args and args.balance or "")
  local tr = tostring(args and args.totalRemoved or "")
  local tv = tostring(args and args.totalValue or "")
  local r  = args and args.removedByType
  local rstr = ""
  if type(r) == "table" then
    for k,v in pairs(r) do
      rstr = rstr .. "|" .. tostring(k) .. ":" .. tostring(v)
    end
  end
  return b .. "#" .. tr .. "#" .. tv .. rstr
end

local function scheduleSellCleanupSafe(removedByType, ticks)
  if type(removedByType) ~= "table" then
    _apsSellPending = nil
    _apsSellCleanupTicks = 0
    _apsSellCleanupTries = 0
    return
  end

  local pending = {}
  local any = false
  for ft, cnt in pairs(removedByType) do
    local n = math.floor(tonumber(cnt) or 0)
    if n > 0 then
      pending[ft] = n
      any = true
    end
  end

  if not any then
    _apsSellPending = nil
    _apsSellCleanupTicks = 0
    _apsSellCleanupTries = 0
    return
  end

  _apsSellPending = pending
  _apsSellCleanupTicks = tonumber(ticks) or 12
  _apsSellCleanupTries = 0
end

local function tickSellCleanupSafe()
  if _apsSellCleanupTicks <= 0 then return end
  _apsSellCleanupTicks = _apsSellCleanupTicks - 1

  if not (isClient() and not isServer()) then
    _apsSellCleanupTicks = 0
    _apsSellPending = nil
    return
  end

  if isTransferBusy() then
    dbg("sell cleanup skipped: transfer busy")
    return
  end

  if _apsSellCleanupTries >= 10 then
    _apsSellCleanupTicks = 0
    _apsSellPending = nil
    return
  end
  _apsSellCleanupTries = _apsSellCleanupTries + 1

  local p = getPlayer()
  local inv = p and p:getInventory() or nil
  if not inv or type(_apsSellPending) ~= "table" then
    _apsSellCleanupTicks = 0
    _apsSellPending = nil
    return
  end

  local removedThisTick = 0
  local stillPending = 0

  for fullType, remain in pairs(_apsSellPending) do
    local need = tonumber(remain) or 0
    if need > 0 then
      local haveNow = countItemsLocal(inv, fullType)
      local toRemove = math.min(need, haveNow)

      if toRemove > 0 then
        local took = removeItemsLocalSafe(inv, fullType, toRemove)
        removedThisTick = removedThisTick + (tonumber(took) or 0)
        need = need - (tonumber(took) or 0)
      end

      if need > 0 then
        _apsSellPending[fullType] = need
        stillPending = stillPending + need
      else
        _apsSellPending[fullType] = nil
      end
    else
      _apsSellPending[fullType] = nil
    end
  end

  dbg("sell cleanup try=", _apsSellCleanupTries, "removedThisTick=", removedThisTick, "stillPending=", stillPending)

  ensureLootPaneHasValidInventory()
  forceInventoryRefreshSafe()

  safeCall(function()
    local p2 = getPlayer()
    if p2 and p2.resetEquippedHands then p2:resetEquippedHands() end
  end)

  if stillPending <= 0 then
    _apsSellCleanupTicks = 0
    _apsSellPending = nil
  end
end

-- =========================================================
-- ✅ BUY entrypoint (SP local / MP server)
-- =========================================================
local function clampInt(n, minv, maxv)
  n = tonumber(n) or 0
  n = math.floor(n)
  if n < minv then return minv end
  if n > maxv then return maxv end
  return n
end

-- =========================================================
-- ✅ LINK entrypoint (MP server / SP local)  ✅ FIX "LINKING PEGADO"
-- =========================================================
function AutoPawnShop.RequestLinkCard()
  local p = getPlayer()
  if not p then return end

  setUILinking(true)
  AutoPawnShopUI_Toast("Linking card...")

  -- MP: server (cuando vuelva respuesta, refreshCardLocalState lo apaga si linked)
  if isClient() then
    sendClientCommand("AutoPawnShop", "LinkCard", {})
    return
  end

  -- SP: ejecutar link local y SIEMPRE apagar linking (finally)
  local ok = false
  local okRun = pcall(function()
    if AutoPawnShop.LinkFirstCardToPlayer then
      ok = (AutoPawnShop.LinkFirstCardToPlayer(p) == true)
    end
    if not ok then
      ok = (spLinkFirstCardLocal(p) == true)
    end
  end)

  refreshCardLocalState()
  refreshAPSUI()

  if not okRun then
    AutoPawnShopUI_Toast("Failed to link card (error).")
    clearUILinkingSafe()
    return
  end

  if ok then
    AutoPawnShop.ClientState.hasCard = true
    AutoPawnShop.ClientState.linked  = true
    AutoPawnShopUI_SetState(
      AutoPawnShop.ClientState.balance,
      AutoPawnShop.ClientState.hasCard,
      AutoPawnShop.ClientState.linked
    )
    AutoPawnShopUI_Toast("Card linked.")
  else
    AutoPawnShopUI_Toast("Failed to link card.")
  end

  -- ✅ SP: SIEMPRE lo apago acá (no depende del server)
  clearUILinkingSafe()
end

function AutoPawnShop.RequestBuyItem(itemFullType, price, qty)
  local p = getPlayer()
  if not p then return end

  itemFullType = tostring(itemFullType or "")
  price = tonumber(price) or 0
  qty = clampInt(qty, 1, 50)

  if itemFullType == "" or price <= 0 then
    AutoPawnShopUI_Toast("Invalid purchase request.")
    return
  end

  -- MP: server authoritative
  if isClient() then
    sendClientCommand("AutoPawnShop", "BuyItem", { item = itemFullType, price = price, qty = qty })
    return
  end

  -- SP: local buy
  if AutoPawnShop.HasCreditCard and AutoPawnShop.HasCreditCard(p) ~= true then
    AutoPawnShopUI_Toast("Missing Credit Card.")
    return
  end

  -- ✅ SP: si IsCardLinkedToPlayer no existe (server-only), usamos estado local (modData)
  if AutoPawnShop.IsCardLinkedToPlayer then
    if AutoPawnShop.IsCardLinkedToPlayer(p) ~= true then
      AutoPawnShopUI_Toast("Your credit card is not linked.")
      return
    end
  else
    refreshCardLocalState()
    if AutoPawnShop.ClientState.linked ~= true then
      AutoPawnShopUI_Toast("Your credit card is not linked.")
      return
    end
  end

  local bal = spGetBalance(p)
  if bal < 0 then bal = 0 end

  local totalCost = price * qty
  if bal < totalCost then
    AutoPawnShopUI_Toast("Insufficient balance. Need $" .. tostring(totalCost) .. ", you have $" .. tostring(bal) .. ".")
    return
  end

  local radius = tonumber(cfg().DropRadius) or 3
  local wantedType = cfg().CardShopContainerType -- e.g. "vendingsnack"

  local targetInv, targetObj = findNearbyContainerByTypeClosestClient(p, radius, wantedType)

  if not targetInv then
    targetInv = p:getInventory()
    targetObj = nil
    dbg("SP BUY fallback -> player inventory (no vending found type=" .. tostring(wantedType) .. ")")
  end

  local added = 0
  for i = 1, qty do
    local it = targetInv and targetInv.AddItem and targetInv:AddItem(itemFullType) or nil
    if it then added = added + 1 else break end
  end

  if added <= 0 then
    AutoPawnShopUI_Toast("Purchase failed: item '" .. tostring(itemFullType) .. "' not found/failed.")
    return
  end

  local charged = price * added
  local newBal = bal - charged
  if newBal < 0 then newBal = 0 end

  spSetBalance(p, newBal)

  AutoPawnShop.ClientState.balance = newBal
  AutoPawnShopUI_SetState(newBal, AutoPawnShop.ClientState.hasCard, AutoPawnShop.ClientState.linked)

  if targetObj and targetObj.getSquare then
    local sq = targetObj:getSquare()
    if sq then
      AutoPawnShop.ClientState.dropTarget = {
        x = sq:getX(), y = sq:getY(), z = sq:getZ(), ctype = tostring(wantedType or "")
      }
      scheduleVendingCleanupTicks(10)
    end
  end

  ensureLootPaneHasValidInventory()
  forceInventoryRefreshSafe()
  scheduleCardPoll(60)
  refreshCardLocalState()

  AutoPawnShopUI_Toast("Purchased x" .. tostring(added) .. " " .. tostring(itemFullType) .. " for $" .. tostring(charged) .. ".")
end

-- =========================================================
-- SP SELL (local). MP uses server command.
-- =========================================================
function AutoPawnShop.SellSelectedJewelsLocal(playerObj, toSell)
  if not playerObj or type(toSell) ~= "table" then
    return false, "Invalid sell request."
  end
  if not playerObj.getInventory then
    return false, "Inventory not available."
  end

  local inv = playerObj:getInventory()
  if not inv then
    return false, "Inventory not available."
  end

  local function findFirstItemByFullTypeRecurse(inv2, fullType)
    if not inv2 or not fullType then return nil end
    local items = inv2.getItems and inv2:getItems() or nil
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

  local function removeN(fullType, n)
    local removed = 0
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return 0 end

    for i = 1, n do
      local it = findFirstItemByFullTypeRecurse(inv, fullType)
      if not it then break end

      local cont = (it.getContainer and it:getContainer()) or inv
      if cont and cont.Remove then
        pcall(function()
          if playerObj.isEquipped and playerObj:isEquipped(it) and playerObj.removeFromHands then
            playerObj:removeFromHands(it)
          end
        end)

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

  if AutoPawnShop.HasCreditCard and AutoPawnShop.HasCreditCard(playerObj) ~= true then
    return false, "Missing Credit Card."
  end

  -- ✅ SP: si IsCardLinkedToPlayer no existe, usamos local state
  if AutoPawnShop.IsCardLinkedToPlayer then
    if AutoPawnShop.IsCardLinkedToPlayer(playerObj) ~= true then
      return false, "Your credit card is not linked."
    end
  else
    refreshCardLocalState()
    if AutoPawnShop.ClientState.linked ~= true then
      return false, "Your credit card is not linked."
    end
  end

  local totalValue, totalRemoved = 0, 0

  for fullType, reqCount in pairs(toSell) do
    if type(fullType) == "string" then
      local price = spGetJewelPrice(fullType)
      local want = math.floor(tonumber(reqCount) or 0)
      if want > 0 and price > 0 then
        local removed = removeN(fullType, want)
        if removed > 0 then
          totalRemoved = totalRemoved + removed
          totalValue   = totalValue + (price * removed)
        end
      end
    end
  end

  if totalRemoved <= 0 then
    return false, "No jewels were sold (none available or invalid selection)."
  end

  local bal = spGetBalance(playerObj)
  if bal < 0 then bal = 0 end

  local newBal = bal + totalValue
  spSetBalance(playerObj, newBal)

  AutoPawnShop.ClientState.balance = newBal
  if AutoPawnShopUI_SetState then
    AutoPawnShopUI_SetState(newBal, AutoPawnShop.ClientState.hasCard, AutoPawnShop.ClientState.linked)
  end

  pcall(refreshCardLocalState)
  pcall(ensureLootPaneHasValidInventory)
  pcall(forceInventoryRefreshSafe)

  return true, "Sold " .. tostring(totalRemoved) .. ". Added $" .. tostring(totalValue) .. " to card."
end

-- =========================================================
-- Server -> Client
-- =========================================================
local function onServerCommand(module, command, args)
  if module ~= "AutoPawnShop" then return end
  args = args or {}

  if command == "SyncState" then
    AutoPawnShop.ClientState.balance = tonumber(args.balance) or 0
    AutoPawnShop.ClientState.hasCard = args.hasCard == true
    AutoPawnShop.ClientState.linked  = args.linked == true

    AutoPawnShopUI_SetState(
      AutoPawnShop.ClientState.balance,
      AutoPawnShop.ClientState.hasCard,
      AutoPawnShop.ClientState.linked
    )
    refreshAPSUI()

    if AutoPawnShop.ClientState.linked then
      scheduleCardPoll(60)
      -- ✅ si linkeó por MP, apagá linking
      if AutoPawnShop.ClientState._linking == true then clearUILinkingSafe() end
    end

  elseif command == "Toast" then
    AutoPawnShopUI_Toast(args.text or "")

  elseif command == "SetDropTarget" then
    AutoPawnShop.ClientState.dropTarget = {
      x = tonumber(args.x),
      y = tonumber(args.y),
      z = tonumber(args.z),
      ctype = tostring(args.ctype or ""),
    }
    dbg("SetDropTarget", tostring(args.x), tostring(args.y), tostring(args.z), tostring(args.ctype))
    scheduleVendingCleanupTicks(10)

  elseif command == "InvRefresh" then
    local reason = tostring(args.reason or "")
    dbg("InvRefresh reason=", reason)

    ensureLootPaneHasValidInventory()
    forceInventoryRefreshSafe()

    if reason:find("buy") then
      scheduleVendingCleanupTicks(30)
    end

    scheduleCardPoll(60)
    refreshCardLocalState()
  end
end

Events.OnServerCommand.Add(onServerCommand)

-- =========================================================
-- Startup
-- =========================================================
Events.OnGameStart.Add(function()
  safeCall(function()
    if isClient() then
      sendClientCommand("AutoPawnShop", "RequestSync", {})
    else
      local p = getPlayer()
      if p then AutoPawnShop.ClientState.balance = spGetBalance(p) end
      refreshCardLocalState()
      refreshAPSUI()
      clearUILinkingSafe() -- ✅ por las dudas al cargar partida
    end
  end)
end)

-- =========================================================
-- Tick
-- =========================================================
Events.OnTick.Add(function()
  tickVendingCleanup()
  tickCardPoll()
  tickSellCleanupSafe()

  -- ✅ watchdog: si SP quedó pegado por alguna razón, lo apaga solo
  if AutoPawnShop.ClientState._linking == true then
    AutoPawnShop.ClientState._linkingTicks = (tonumber(AutoPawnShop.ClientState._linkingTicks) or 0) - 1
    if AutoPawnShop.ClientState._linkingTicks <= 0 then
      dbg("linking watchdog -> force clear")
      clearUILinkingSafe()
    end
  end
end)

-- =========================================================
-- Fallback: mirror balance from player modData
-- =========================================================
local _apsNextCheck = 0
Events.OnTick.Add(function()
  local t = getTimestampMs and getTimestampMs() or 0
  if t < _apsNextCheck then return end
  _apsNextCheck = t + 2000

  local p = getPlayer()
  if not p or not p.getModData then return end

  local md = p:getModData()
  local bal = tonumber(md and md.APS_balance) or nil
  if bal ~= nil and bal ~= AutoPawnShop.ClientState.balance then
    AutoPawnShop.ClientState.balance = bal
    AutoPawnShopUI_SetState(
      AutoPawnShop.ClientState.balance,
      AutoPawnShop.ClientState.hasCard,
      AutoPawnShop.ClientState.linked
    )
    refreshAPSUI()
  end
end)


-- =========================================================
-- ✅ SELL SHIM (MP + SP) - evita "[AutoPawnShop] Sell function missing (SP)."
-- La UI/Util puede llamar distintos nombres, así que exponemos varios.
-- =========================================================

local function _apsDoSell(toSell)
  local p = getPlayer()
  if not p then
    if AutoPawnShopUI_Toast then AutoPawnShopUI_Toast("No player.") end
    return false
  end

  -- MP: server authoritative
  if isClient() then
    sendClientCommand("AutoPawnShop", "SellJewels", { toSell = toSell })
    if AutoPawnShopUI_Toast then AutoPawnShopUI_Toast("Selling...") end
    return true
  end

  -- SP: local sell
  if AutoPawnShop.SellSelectedJewelsLocal then
    local ok, msg = AutoPawnShop.SellSelectedJewelsLocal(p, toSell)
    if AutoPawnShopUI_Toast and msg then AutoPawnShopUI_Toast(tostring(msg)) end
    return ok == true
  end

  if AutoPawnShopUI_Toast then AutoPawnShopUI_Toast("SellSelectedJewelsLocal missing.") end
  return false
end

-- Nombre “principal” (recomendado)
function AutoPawnShop.RequestSellJewels(toSell)
  if type(toSell) ~= "table" then
    if AutoPawnShopUI_Toast then AutoPawnShopUI_Toast("Invalid sell selection.") end
    return false
  end
  return _apsDoSell(toSell)
end

-- Aliases por compatibilidad (por si tu UI/Util llama otro nombre)
AutoPawnShop.SellJewelsRequest        = AutoPawnShop.RequestSellJewels
AutoPawnShop.RequestSellSelectedJewels= AutoPawnShop.RequestSellJewels
AutoPawnShop.SellSelectedJewels       = AutoPawnShop.RequestSellJewels
AutoPawnShop.SellJewels               = AutoPawnShop.RequestSellJewels
AutoPawnShop.DoSellJewels             = AutoPawnShop.RequestSellJewels


print("[APS][CLIENT] AutoPawnShop_Client.lua LOADED")
