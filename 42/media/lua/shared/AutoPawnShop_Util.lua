AutoPawnShop = AutoPawnShop or {}
AutoPawnShop.Config = AutoPawnShop.Config or {}
print("### APS MARK: UTIL v999 ###")

-- =========================================================
-- BOOT / SENTINEL (detecta pisadas y orden de carga)
-- =========================================================
AutoPawnShop.__util_loaded = true
AutoPawnShop.__util_loaded_at = tostring(getTimestampMs and getTimestampMs() or "no-ts")

local function apsTag()
  return tostring(AutoPawnShop) .. " utilLoaded=" .. tostring(AutoPawnShop.__util_loaded)
end

print("[APS][UTIL] LOADED tag=" .. apsTag())
print("[APS][UTIL] SellSelectedJewelsLocal =", tostring(AutoPawnShop.SellSelectedJewelsLocal))
print("[APS][UTIL] LinkFirstCardToPlayer   =", tostring(AutoPawnShop.LinkFirstCardToPlayer))


-- =========================================================
-- Debug helper
-- =========================================================
local function dbg(...)
  local cfg = AutoPawnShop.Config or {}
  if cfg.DebugCard then
    print("[APS][DBG]", ...)
  end
end

print("[APS] AutoPawnShop_Util LOADED from client")


-- =========================================================
-- Safe isClient/isServer wrappers (avoid nil in odd contexts)
-- =========================================================
local function _isClient()
  return (type(isClient) == "function") and isClient() or false
end

local function _isServer()
  return (type(isServer) == "function") and isServer() or false
end

-- Singleplayer: no client/server split
local function isSP()
  return (not _isClient()) and (not _isServer())
end

-- =========================================================
-- Username safe
-- =========================================================
local function getUsernameSafe(playerObj)
  if not playerObj then return "Player" end
  if playerObj.getUsername then
    local u = playerObj:getUsername()
    if u and u ~= "" then return u end
  end
  if playerObj.getDisplayName then
    local d = playerObj:getDisplayName()
    if d and d ~= "" then return d end
  end
  return "Player"
end

-- Base.CreditCard -> CreditCard
local function typeFromFullType(fullType)
  if type(fullType) ~= "string" then return nil end
  local dot = string.find(fullType, "%.")
  if not dot then return fullType end
  return string.sub(fullType, dot + 1)
end

-- =========================================================
-- ✅ Jewel price resolver (explicit + prefix fallback)
-- =========================================================
local function startsWith(str, prefix)
  if type(str) ~= "string" or type(prefix) ~= "string" then return false end
  return string.sub(string.lower(str), 1, #prefix) == string.lower(prefix)
end

-- Returns price or nil if unknown
function AutoPawnShop.GetJewelPrice(fullType)
  local cfg = AutoPawnShop.Config or {}
  if type(fullType) ~= "string" or fullType == "" then return nil end

  -- 1) Explicit list wins
  local jp = cfg.JewelPrices
  if type(jp) == "table" then
    local p = jp[fullType]
    if p ~= nil then
      p = tonumber(p)
      if p and p > 0 then return math.floor(p) end
      return nil
    end
  end

  -- 2) Prefix defaults (if not explicitly listed)
  local rules = cfg.JewelPrefixDefaultPrices
  if type(rules) == "table" then
    for _, r in ipairs(rules) do
      local pref = r and r.prefix
      local price = r and r.price
      if pref and startsWith(fullType, pref) then
        local p = tonumber(price)
        if p and p > 0 then
          return math.floor(p)
        end
      end
    end
  end

  return nil
end

-- Alias (por si en otro archivo ya llamabas algo así)
function AutoPawnShop.ResolveJewelPrice(fullType)
  return AutoPawnShop.GetJewelPrice(fullType)
end

-- =========================================================
-- Recursive inventory search (FIRST)
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

-- =========================================================
-- Recursive inventory search (ALL)
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
      local childInv = it.getInventory and it:getInventory() or nil
      findAllItemsByFullTypeRecurse(childInv, fullType, out)
    end
  end

  return out
end

-- =========================================================
-- Balance (persistente)
-- =========================================================
function AutoPawnShop.GetBalance(playerObj)
  local key = AutoPawnShop.Config.BalanceKey or "APS_Balance"
  local md = playerObj and playerObj.getModData and playerObj:getModData() or nil
  if not md then return 0 end
  local v = tonumber(md[key]) or 0
  if v < 0 then v = 0 end
  return math.floor(v)
end

function AutoPawnShop.SetBalance(playerObj, value)
  local key = AutoPawnShop.Config.BalanceKey or "APS_Balance"
  local md = playerObj and playerObj.getModData and playerObj:getModData() or nil
  if not md then return end

  local v = tonumber(value) or 0
  if v < 0 then v = 0 end
  md[key] = math.floor(v)

  -- MP: replicate modData
  if playerObj.transmitModData then
    playerObj:transmitModData()
  elseif playerObj.sendObjectChange then
    playerObj:sendObjectChange("modData")
  end
end

-- =========================================================
-- Credit card detection
-- =========================================================
function AutoPawnShop.HasCreditCard(playerObj)
  if not playerObj or not playerObj.getInventory then return false end
  local inv = playerObj:getInventory()
  if not inv then return false end

  local fullType = AutoPawnShop.Config.RequireCreditCardItem or "Base.CreditCard"

  if findFirstItemByFullTypeRecurse(inv, fullType) then
    return true
  end

  local t = typeFromFullType(fullType)
  if t and inv.containsTypeRecurse and inv:containsTypeRecurse(t) then
    return true
  end

  return false
end

function AutoPawnShop.GetAllCreditCards(playerObj)
  if not playerObj or not playerObj.getInventory then return {} end
  local inv = playerObj:getInventory()
  if not inv then return {} end
  local fullType = AutoPawnShop.Config.RequireCreditCardItem or "Base.CreditCard"
  return findAllItemsByFullTypeRecurse(inv, fullType, {})
end

function AutoPawnShop.GetFirstUnlinkedCreditCard(playerObj)
  local cards = AutoPawnShop.GetAllCreditCards(playerObj)
  if not cards or #cards == 0 then return nil end

  local uname = getUsernameSafe(playerObj)
  for _, card in ipairs(cards) do
    local md = card.getModData and card:getModData() or {}
    local owner = md.APS_owner
    if not owner or tostring(owner) ~= tostring(uname) then
      return card
    end
  end

  return cards[1]
end

function AutoPawnShop.IsCardLinkedToPlayer(playerObj)
  local cards = AutoPawnShop.GetAllCreditCards(playerObj)
  if not cards or #cards == 0 then return false end

  local uname = getUsernameSafe(playerObj)
  for _, card in ipairs(cards) do
    local md = card.getModData and card:getModData() or {}
    if md.APS_owner and tostring(md.APS_owner) == tostring(uname) then
      return true
    end
  end

  return false
end

-- =========================================================
-- Inventory/UI refresh helpers (SP + MP)
-- =========================================================
local function markContainerDirty(container)
  if container and container.setDrawDirty then
    pcall(function() container:setDrawDirty(true) end)
  end
end

local function forceInventoryRefresh(playerObj, card)
  -- Mark player inventory dirty
  if playerObj and playerObj.getInventory then
    local inv = playerObj:getInventory()
    markContainerDirty(inv)
  end

  -- Mark the card's container dirty (if any)
  if card and card.getContainer then
    local c = card:getContainer()
    markContainerDirty(c)
  end

  -- Try common events (safe if missing)
  if type(triggerEvent) == "function" then
    pcall(function() triggerEvent("OnContainerUpdate") end)
    pcall(function() triggerEvent("OnRefreshInventoryWindowContainers") end)
  end
end

-- =========================================================
-- Card rename helper (and replicate modData in MP)
-- =========================================================
local function applyCardDisplayName(card, newName)
  if not card then return end

  local md = card.getModData and card:getModData() or {}
  md.APS_displayName = tostring(newName)

  if card.setCustomName then
    pcall(function() card:setCustomName(true) end)
  end

  if card.setName then
    pcall(function() card:setName(tostring(newName)) end)
  end

  -- MP: replicate item modData (name/owner)
  if card.transmitModData then
    pcall(function() card:transmitModData() end)
  end

  dbg("Rename card ->", tostring(newName))
end

-- =========================================================
-- ✅ SELL (Singleplayer / Host local)
-- =========================================================
function AutoPawnShop.SellSelectedJewelsLocal(playerObj, toSell)
  if not playerObj or type(toSell) ~= "table" then
    return false, "Invalid sell request."
  end

  -- Requisitos
  if not AutoPawnShop.HasCreditCard(playerObj) then
    return false, "You need a Credit Card to deposit the money."
  end
  if not AutoPawnShop.IsCardLinkedToPlayer(playerObj) then
    return false, "Your credit card is not linked."
  end

  local inv = playerObj:getInventory()
  if not inv then return false, "Inventory not available." end

  local totalEarned = 0
  local removed = 0

  -- remover items del inventario (soporta items dentro de contenedores)
  local function removeOne(fullType)
    local it = findFirstItemByFullTypeRecurse(inv, fullType) -- usa tu helper local del util
    if not it then return false end

    -- Remover de su container real
    local c = it.getContainer and it:getContainer() or inv
    if c and c.Remove then
      c:Remove(it)
      return true
    end

    -- fallback
    if inv.Remove then
      inv:Remove(it)
      return true
    end

    return false
  end

  for fullType, cnt in pairs(toSell) do
    local qty = math.floor(tonumber(cnt) or 0)
    if qty > 0 then
      local price = tonumber(AutoPawnShop.GetJewelPrice(fullType)) or 0
      if price > 0 then
        for i = 1, qty do
          if removeOne(fullType) then
            removed = removed + 1
            totalEarned = totalEarned + price
          else
            -- si no lo encuentra, corta para ese tipo
            break
          end
        end
      end
    end
  end

  if removed <= 0 or totalEarned <= 0 then
    return false, "No jewels were removed (not found in inventory)."
  end

  -- Depositar al balance
  local cur = AutoPawnShop.GetBalance(playerObj) or 0
  AutoPawnShop.SetBalance(playerObj, cur + totalEarned)

  -- refrescar inventario/UI en SP
  forceInventoryRefresh(playerObj, nil)

  return true, ("Sold %d item(s) for $%d."):format(removed, totalEarned)
end


-- =========================================================
-- Link ONE card only (SP + MP safe)
-- - SP: local change + forceInventoryRefresh
-- - MP client: ask server via sendClientCommand
-- - MP server/host: apply changes + replicate
-- =========================================================
function AutoPawnShop.LinkFirstCardToPlayer(playerObj)
  if not playerObj then
    dbg("LinkFirstCardToPlayer: missing playerObj")
    return false
  end

  -- guard: must have a card
  if not AutoPawnShop.HasCreditCard(playerObj) then
    dbg("LinkFirstCardToPlayer: player has no card")
    return false
  end

  -- if already linked to THIS player, do nothing
  if AutoPawnShop.IsCardLinkedToPlayer(playerObj) then
    dbg("LinkFirstCardToPlayer: already linked")
    return true
  end

-- MP client path (server authoritative)
if _isClient() and (not _isServer()) then
  if type(sendClientCommand) == "function" then
    local owner = getUsernameSafe(playerObj)
    dbg("MP client: requesting server link for", owner)

    sendClientCommand("AutoPawnShop", "LinkFirstCard", {
      owner = owner,
      playerNum = playerObj.getPlayerNum and playerObj:getPlayerNum() or 0
    })

    return true
  end
end


  -- Local/server path
  local card = AutoPawnShop.GetFirstUnlinkedCreditCard(playerObj)
  if not card then
    dbg("LinkFirstCardToPlayer: no card found (unlinked)")
    return false
  end

  local owner = getUsernameSafe(playerObj)
  local md = card.getModData and card:getModData() or nil
  if not md then
    dbg("LinkFirstCardToPlayer: card has no modData")
    return false
  end

  md.APS_owner = owner

  local newName = "Tarjeta de Credito de " .. tostring(owner)
  applyCardDisplayName(card, newName)

  if isSP() then
    forceInventoryRefresh(playerObj, card)
    dbg("Card linked OK (SP) ->", owner)
    return true
  end

  -- MP server/host: replicate item + player containers
  if card.transmitModData then
    pcall(function() card:transmitModData() end)
  end
  if playerObj.sendObjectChange then
    pcall(function()
      playerObj:sendObjectChange("modData")
      playerObj:sendObjectChange("containers")
    end)
  end

  dbg("Card linked OK (MP server/host) ->", owner)
  return true
end

-- =========================================================
-- Wrappers que usa la UI (RequestLinkCard / RequestBuyItem)
-- =========================================================

function AutoPawnShop.RequestLinkCard()
  local p = getPlayer()
  if not p then return false end

  -- MP client: pedir al server
  if _isClient() and (not _isServer()) and type(sendClientCommand) == "function" then
    local owner = getUsernameSafe(p)
    sendClientCommand("AutoPawnShop", "LinkFirstCard", {
      owner = owner,
      playerNum = p.getPlayerNum and p:getPlayerNum() or 0
    })
    return true
  end

  -- SP o Host: link local
  return AutoPawnShop.LinkFirstCardToPlayer(p)
end

function AutoPawnShop.RequestBuyItem(fullType, price, qty)
  qty = math.floor(tonumber(qty) or 1)
  if qty < 1 then return false end

  -- MP client: pedir al server
  if _isClient() and (not _isServer()) and type(sendClientCommand) == "function" then
    sendClientCommand("AutoPawnShop", "BuyItem", {
      item = fullType,
      price = tonumber(price) or 0,
      qty = qty
    })
    return true
  end

  -- SP o Host: si tenés compra local, llamala
  if AutoPawnShop.BuyItemLocal then
    local p = getPlayer()
    if not p then return false end
    return AutoPawnShop.BuyItemLocal(p, fullType, price, qty)
  end

  return false
end

print("[APS][UTIL] END tag=" .. apsTag())
print("[APS][UTIL] END SellSelectedJewelsLocal =", tostring(AutoPawnShop.SellSelectedJewelsLocal))
print("[APS][UTIL] END LinkFirstCardToPlayer   =", tostring(AutoPawnShop.LinkFirstCardToPlayer))
-- =========================================================
-- Anti-pisado: si otro archivo hace AutoPawnShop = {} lo detectamos
-- =========================================================
local _aps_last_tbl = AutoPawnShop
local _aps_next_check = 0

Events.OnTick.Add(function()
  local t = getTimestampMs and getTimestampMs() or 0
  if t < _aps_next_check then return end
  _aps_next_check = t + 1000

  if AutoPawnShop ~= _aps_last_tbl then
    print("[APS][UTIL][WARN] AutoPawnShop TABLE CHANGED! old=" .. tostring(_aps_last_tbl) .. " new=" .. tostring(AutoPawnShop))
    -- actualizo referencia para no spamear infinito
    _aps_last_tbl = AutoPawnShop
  end

  if not AutoPawnShop.__util_loaded then
    print("[APS][UTIL][WARN] __util_loaded missing! Someone overwrote AutoPawnShop table.")
  end
end)
print("[APS][UTIL] END AutoPawnShop table=", tostring(AutoPawnShop))
print("[APS][UTIL] END SellSelectedJewelsLocal=", tostring(AutoPawnShop.SellSelectedJewelsLocal))
