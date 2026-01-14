-- AutoPawnShop_Context.lua (FULL)
-- World context: detect kiosk/vending by container type and open UI passing target object
-- Inventory context: Credit Card Info + Link via AutoPawnShop.RequestLinkCard (SP-safe + MP-safe)

require "AutoPawnShop_Config"
require "AutoPawnShop_UI"
require "AutoPawnShop_Util"

AutoPawnShop = AutoPawnShop or {}
local Cfg = AutoPawnShop.Config or {}

print("### APS MARK: CONTEXT v999 ###")

-- =========================================================
-- Helpers
-- =========================================================
local function getUsernameSafe(p)
  if not p then return "Player" end
  local u = nil
  if p.getUsername ~= nil then u = p:getUsername() end
  if (not u or u == "") and p.getDisplayName ~= nil then u = p:getDisplayName() end
  if not u or u == "" then u = "Player" end
  return u
end

local function isTargetContainer(obj, wantedType)
  if not obj or not wantedType or wantedType == "" then return false end

  -- sprite name contains wantedType
  local sprite = obj.getSprite and obj:getSprite() or nil
  local sprName = sprite and sprite.getName and sprite:getName() or nil
  if sprName and string.find(string.lower(sprName), string.lower(wantedType), 1, true) then
    return true
  end

  -- container type match
  if obj.getContainer then
    local c = obj:getContainer()
    if c and c.getType and string.lower(c:getType()) == string.lower(wantedType) then
      return true
    end
  end

  -- object name contains wantedType
  local name = obj.getName and obj:getName() or nil
  if name and string.find(string.lower(name), string.lower(wantedType), 1, true) then
    return true
  end

  return false
end

local function findInteraction(worldobjects)
  if not worldobjects then return nil, nil end
  for _, obj in ipairs(worldobjects) do
    if isTargetContainer(obj, Cfg.PawnKioskContainerType) then
      return "pawn", obj
    end
    if isTargetContainer(obj, Cfg.CardShopContainerType) then
      return "shop", obj
    end
  end
  return nil, nil
end

-- =========================================================
-- WORLD CONTEXT MENU (kiosk / vending)
-- =========================================================
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
  if test then return end

  local kind, target = findInteraction(worldobjects)
  if not kind then return end

  if kind == "pawn" then
    context:addOption("Pawn Shop (Sell Jewels)", nil, function()
      if AutoPawnShopUI_OpenPawn then
        AutoPawnShopUI_OpenPawn(playerNum, target)
      else
        print("[APS][CTX] AutoPawnShopUI_OpenPawn missing")
      end
    end)

  elseif kind == "shop" then
    context:addOption("Vending (Buy)", nil, function()
      if AutoPawnShopUI_OpenShop then
        AutoPawnShopUI_OpenShop(playerNum, target)
      else
        print("[APS][CTX] AutoPawnShopUI_OpenShop missing")
      end
    end)
  end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- =========================================================
-- INVENTORY CONTEXT MENU (Credit Card: Link / Info)
-- =========================================================

-- items param puede venir como:
-- 1) InventoryItem directo
-- 2) table con entry.items (cuando seleccionás varios)
-- 3) lista de wrappers
local function extractFirstInventoryItem(items)
  if not items then return nil end

  -- caso: un item directo
  if type(items) ~= "table" then
    return items
  end

  -- caso: { {items=...}, {items=...} }
  local first = items[1]
  if first and type(first) == "table" and first.items then
    -- first.items puede ser array o single
    if type(first.items) == "table" then
      return first.items[1]
    else
      return first.items
    end
  end

  -- caso: lista de InventoryItem
  if first and first.getFullType then return first end

  return nil
end

local function isCreditCardItem(item)
  if not item or not item.getFullType then return false end
  local want = (Cfg and Cfg.RequireCreditCardItem) or "Base.CreditCard"
  return item:getFullType() == want
end

local function onFillInventoryObjectContextMenu(playerNum, context, items)
  local playerObj = getSpecificPlayer(playerNum)
  if not playerObj then return end

  local item = extractFirstInventoryItem(items)
  if not item or not isCreditCardItem(item) then return end

  -- Info
  context:addOption("Credit Card: Info", nil, function()
    if AutoPawnShopUI_ShowCardInfoModal then
      AutoPawnShopUI_ShowCardInfoModal(item)
    else
      print("[APS][CTX] AutoPawnShopUI_ShowCardInfoModal missing")
    end
  end)

  -- Link (SP-safe + MP-safe via util wrapper)
  context:addOption("Credit Card: Link", nil, function()
    if AutoPawnShop and AutoPawnShop.RequestLinkCard then
      AutoPawnShop.RequestLinkCard()
      if AutoPawnShopUI_Toast then
        AutoPawnShopUI_Toast("Linking card...")
      end
    else
      print("[APS][CTX] RequestLinkCard missing (Util/Client not loaded?)")
    end
  end)
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

print("[APS][CLIENT] AutoPawnShop_Context.lua LOADED (world+inventory menu hooks ok)")
