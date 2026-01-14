-- AutoPawnShop_UI.lua (COMPLETO)
-- FIXES:
-- 1) Boton "Link Card" usa AutoPawnShop.RequestLinkCard() (SP no queda "Linking...")
-- 2) MP: sendClientCommand sin player param (forma correcta B41/B42)
-- 3) Mantiene: ALL solo en Pawn, header centrado/espaciado, resize custom, etc.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "ISUI/ISTextEntryBox"

require "AutoPawnShop_Util"
require "AutoPawnShop_Config"

AutoPawnShopUI = AutoPawnShopUI or {}
AutoPawnShop = AutoPawnShop or {}
local Cfg = AutoPawnShop.Config

print("### APS MARK: UI v999 ###")

-- =========================================================
-- UI State
-- =========================================================
local state = { balance = 0, hasCard = false, linked = false }

local function getClientState()
  if AutoPawnShop and AutoPawnShop.ClientState then return AutoPawnShop.ClientState end
  return state
end

local function fmtMoney(n)
  n = tonumber(n) or 0
  return "$" .. tostring(math.floor(n))
end

local function getUsernameSafe(p)
  if not p then return "Player" end
  local u = nil
  if p.getUsername ~= nil then u = p:getUsername() end
  if (not u or u == "") and p.getDisplayName ~= nil then u = p:getDisplayName() end
  if not u or u == "" then u = "Player" end
  return u
end

local function getTextW(font, text)
  local tm = getTextManager()
  if not tm or not tm.MeasureStringX then return #tostring(text or "") * 7 end
  return tm:MeasureStringX(font, tostring(text or ""))
end

local function cardStatusText(st)
  if not st.hasCard then return "Credit Card: MISSING" end
  if not st.linked  then return "Credit Card: UNLINKED" end
  return "Credit Card: OK"
end

local function setHeader(panel, leftLabel, rightLabel)
  if panel._apsBalanceLabel then panel._apsBalanceLabel:setName(leftLabel) end
  if panel._apsCardLabel then panel._apsCardLabel:setName(rightLabel) end

  local pad = 12
  local cardW = 0
  if panel._apsCardLabel then
    cardW = getTextW(UIFont.Medium, panel._apsCardLabel.name or "")
    panel._apsCardLabel:setX(panel.width - pad - cardW)
  end

  if panel._apsTotalTopLabel then
    local totalW = getTextW(UIFont.Medium, panel._apsTotalTopLabel.name or "")
    local gap = 12
    local x = (panel.width - pad - cardW) - gap - totalW
    if x < pad then x = pad end
    panel._apsTotalTopLabel:setX(x)
  end
end

function AutoPawnShopUI_SetState(balance, hasCard, linked)
  state.balance = tonumber(balance) or 0
  state.hasCard = hasCard == true
  state.linked  = linked == true

  AutoPawnShop.ClientState = AutoPawnShop.ClientState or {}
  AutoPawnShop.ClientState.balance = state.balance
  AutoPawnShop.ClientState.hasCard = state.hasCard
  AutoPawnShop.ClientState.linked  = state.linked

  if AutoPawnShopUI and AutoPawnShopUI.shopPanel and AutoPawnShopUI.shopPanel.onStateChanged then
    AutoPawnShopUI.shopPanel:onStateChanged()
  end
  if AutoPawnShopUI and AutoPawnShopUI.pawnPanel and AutoPawnShopUI.pawnPanel.onStateChanged then
    AutoPawnShopUI.pawnPanel:onStateChanged()
  end
end

function AutoPawnShopUI_Toast(text)
  local p = getPlayer()
  if p and p.Say then p:Say(tostring(text)) end
  print("[AutoPawnShop] " .. tostring(text))
end

-- =========================================================
-- Per-user UI size persistence
-- =========================================================
local function apsGetGlobalUI()
  if ModData and ModData.getOrCreate then
    return ModData.getOrCreate("APS_UI")
  end
  return nil
end

local function apsGetPlayerUI()
  local p = getPlayer()
  if not p or not p.getModData then return nil end
  local md = p:getModData()
  md.APS_UI = md.APS_UI or {}
  return md.APS_UI
end

local function apsLoadSize(key, defaultW, defaultH)
  local user = getUsernameSafe(getPlayer())

  local g = apsGetGlobalUI()
  if g and g[user] and g[user][key] then
    local s = g[user][key]
    local w = tonumber(s.w) or defaultW
    local h = tonumber(s.h) or defaultH
    return w, h
  end

  local pui = apsGetPlayerUI()
  if pui and pui[user] and pui[user][key] then
    local s = pui[user][key]
    local w = tonumber(s.w) or defaultW
    local h = tonumber(s.h) or defaultH
    return w, h
  end

  return defaultW, defaultH
end

local function apsSaveSize(key, w, h)
  local user = getUsernameSafe(getPlayer())
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)

  local g = apsGetGlobalUI()
  if g then
    g[user] = g[user] or {}
    g[user][key] = { w = w, h = h }
  end

  local pui = apsGetPlayerUI()
  if pui then
    pui[user] = pui[user] or {}
    pui[user][key] = { w = w, h = h }
  end
end

-- =========================================================
-- Distance auto-close
-- =========================================================
local function apsTooFar(panel)
  if not panel or not panel._apsMachine then return false end
  local p = getPlayer()
  if not p then return false end
  local o = panel._apsMachine
  if not o or not o.getX or not o.getY then return false end

  local maxDist = tonumber(panel._apsMaxDist) or 2.5
  local dx = (p:getX() - o:getX())
  local dy = (p:getY() - o:getY())
  return (dx*dx + dy*dy) > (maxDist * maxDist)
end

-- =========================================================
-- Item display/texture
-- =========================================================
local function getItemDisplayNameByFullType(fullType)
  local sm = getScriptManager()
  local scriptItem = fullType and sm and sm:FindItem(fullType) or nil
  if scriptItem and scriptItem.getDisplayName then return scriptItem:getDisplayName() end
  return tostring(fullType or "Unknown")
end

local function getItemTextureByFullType(fullType)
  local sm = getScriptManager()
  local scriptItem = fullType and sm and sm:FindItem(fullType) or nil
  if scriptItem then
    if scriptItem.getNormalTexture and scriptItem:getNormalTexture() then return scriptItem:getNormalTexture() end
    if scriptItem.getTexture and scriptItem:getTexture() then return scriptItem:getTexture() end
    if scriptItem.getIcon and scriptItem:getIcon() then return getTexture(scriptItem:getIcon()) end
  end
  return nil
end

-- =========================================================
-- PRO LISTBOX with thumbnails
-- =========================================================
local APSItemList = ISScrollingListBox:derive("APSItemList")

function APSItemList:new(x, y, w, h)
  local o = ISScrollingListBox:new(x, y, w, h)
  setmetatable(o, self)
  self.__index = self
  o.itemheight = 54
  o.font = UIFont.Small
  o.doDrawItem = APSItemList.doDrawItem
  return o
end

function APSItemList:setRowHeight(h)
  self.itemheight = math.max(34, tonumber(h) or self.itemheight or 54)
end

function APSItemList:doDrawItem(y, item, alt)
  local a = 0.90
  if self.selected == item.index then a = 1.0 end

  local rowH = self.itemheight

  if alt then self:drawRect(0, y, self.width, rowH, 0.10, 1, 1, 1) end
  if self.selected == item.index then
    self:drawRect(0, y, self.width, rowH, 0.18, 1, 1, 1)
    self:drawRectBorder(0, y, self.width, rowH, 0.35, 1, 1, 1)
  else
    self:drawRectBorder(0, y, self.width, rowH, 0.12, 1, 1, 1)
  end

  local data = item.item or {}
  local icon = data.tex
  local iconSize = math.min(rowH - 14, 46)
  local pad = 8
  local iconX, iconY = pad, y + math.floor((rowH - iconSize) / 2)

  if icon then
    self:drawTextureScaledAspect(icon, iconX, iconY, iconSize, iconSize, 1, 1, 1, 1)
  else
    self:drawRect(iconX, iconY, iconSize, iconSize, 0.18, 1, 1, 1)
    self:drawRectBorder(iconX, iconY, iconSize, iconSize, 0.20, 1, 1, 1)
  end

  local nameX = iconX + iconSize + 12
  local nameY = y + 6

  local name  = tostring(data.displayName or data.fullType or "Unknown")
  local qty   = tonumber(data.count or data.max or data.qty or 0) or 0
  local price = tonumber(data.price or 0) or 0
  local sub   = tonumber(data.subtotal or (price * qty)) or 0

  -- Subtotal (derecha)
  local rightInfo = fmtMoney(sub)
  local rightW = getTextW(UIFont.Medium, rightInfo)
  local rightX = self.width - 12 - rightW
  local rightY = y + math.floor(rowH/2) - 8

  -- Nombre
  self:drawText(name, nameX, nameY, 1, 1, 1, a, UIFont.Medium)

  -- Qty a la derecha del nombre (misma línea)
  local qtyText = "x" .. tostring(qty)
  local nameW = getTextW(UIFont.Medium, name)
  local qtyW  = getTextW(UIFont.Medium, qtyText)

  local gap = 10
  local rightLimit = rightX - 14  -- margen antes del subtotal

  local qtyX = nameX + nameW + gap
  if qtyX + qtyW > rightLimit then
    qtyX = rightLimit - qtyW
  end
  if qtyX < nameX then qtyX = nameX end

  self:drawText(qtyText, qtyX, nameY, 0.85, 0.85, 0.85, a, UIFont.Medium)

  -- Dibuja subtotal al final
  self:drawText(rightInfo, rightX, rightY, 1, 1, 1, a, UIFont.Medium)

  return y + rowH
end


-- =========================================================
-- RESIZE GRIP (custom)
-- =========================================================
local APSResizeGrip = ISPanel:derive("APSResizeGrip")

function APSResizeGrip:new(parent, size)
  local s = tonumber(size) or 16
  local o = ISPanel:new((parent.width or 0) - s, (parent.height or 0) - s, s, s)
  setmetatable(o, self)
  self.__index = self
  o.parentPanel = parent
  o.s = s
  o.resizing = false
  o.backgroundColor = {r=0,g=0,b=0,a=0.0}
  o.borderColor = {r=1,g=1,b=1,a=0.0}
  return o
end

function APSResizeGrip:prerender()
  ISPanel.prerender(self)
  local p = self.parentPanel
  if not p then return end
  local s = self.s or 16
  self:setX((p.width or 0) - s)
  self:setY((p.height or 0) - s)
end

function APSResizeGrip:render()
  ISPanel.render(self)
  local w, h = self.width, self.height
  self:drawRect(0, 0, w, h, 0.05, 1, 1, 1)
  local a = 0.35
  local s = 3
  self:drawRect(w - 5,  h - 5,  s, s, a, 1, 1, 1)
  self:drawRect(w - 9,  h - 9,  s, s, a, 1, 1, 1)
  self:drawRect(w - 13, h - 13, s, s, a, 1, 1, 1)
  self:drawRectBorder(0, 0, w, h, 0.20, 1, 1, 1)
end

function APSResizeGrip:onMouseDown(x, y)
  local p = self.parentPanel
  if not p then return false end
  self.resizing = true
  self.startMouseX = getMouseX()
  self.startMouseY = getMouseY()
  self.startW = tonumber(p.width) or 0
  self.startH = tonumber(p.height) or 0
  return true
end

function APSResizeGrip:onMouseMove(dx, dy)
  if not self.resizing then return false end
  local p = self.parentPanel
  if not p then return false end

  local mx = getMouseX()
  local my = getMouseY()
  local ddx = (mx - (self.startMouseX or mx))
  local ddy = (my - (self.startMouseY or my))

  local newW = (self.startW or p.width) + ddx
  local newH = (self.startH or p.height) + ddy

  local minW = tonumber(p._apsMinW) or 600
  local minH = tonumber(p._apsMinH) or 420
  local maxW = tonumber(p._apsMaxW) or (getCore():getScreenWidth() - 20)
  local maxH = tonumber(p._apsMaxH) or (getCore():getScreenHeight() - 20)

  if newW < minW then newW = minW end
  if newH < minH then newH = minH end
  if newW > maxW then newW = maxW end
  if newH > maxH then newH = maxH end

  p:setWidth(newW)
  p:setHeight(newH)

  if p.relayout then p:relayout() end
  if p.keepWithinScreen then p:keepWithinScreen() end

  if p._apsSizeKey then
    apsSaveSize(p._apsSizeKey, p.width, p.height)
  end

  return true
end

function APSResizeGrip:onMouseUp(x, y)
  self.resizing = false
  local p = self.parentPanel
  if p and p._apsSizeKey then
    apsSaveSize(p._apsSizeKey, p.width, p.height)
  end
  return true
end

function APSResizeGrip:onMouseUpOutside(x, y)
  self.resizing = false
  local p = self.parentPanel
  if p and p._apsSizeKey then
    apsSaveSize(p._apsSizeKey, p.width, p.height)
  end
  return true
end

local function enableResizable(panel, minW, minH, sizeKey)
  panel._apsMinW = tonumber(minW) or 600
  panel._apsMinH = tonumber(minH) or 420
  panel._apsMaxW = getCore():getScreenWidth() - 20
  panel._apsMaxH = getCore():getScreenHeight() - 20
  panel._apsSizeKey = sizeKey

  if not panel._apsGrip then
    local g = APSResizeGrip:new(panel, 16)
    g:initialise()
    panel:addChild(g)
    g:setVisible(true)
    panel._apsGrip = g
  end
end

-- =========================================================
-- =========================
--   PAWN (SELL) UI
-- =========================
-- =========================================================
local PawnPanel = ISPanel:derive("PawnPanel")

function PawnPanel:new(x, y, w, h)
  local o = ISPanel:new(x, y, w, h)
  setmetatable(o, self)
  self.__index = self
  o.moveWithMouse = true
  o.toSell = {}
  o._invCache = {}
  o._apsMachine = nil
  o._apsMaxDist = 2.5
  return o
end

local function getJewelPriceForFullType(fullType)
  if not fullType then return nil end
  local p = (AutoPawnShop and AutoPawnShop.GetJewelPrice) and AutoPawnShop.GetJewelPrice(fullType) or nil
  p = tonumber(p) or 0
  if p > 0 then return p end
  return nil
end


local function buildJewelInventorySummary(player)
  local inv = player and player.getInventory and player:getInventory() or nil
  local summary = {}
  if not inv or not inv.getItems then return summary end

  local function scanInventory(container)
    if not container or not container.getItems then return end
    local items = container:getItems()
    if not items then return end

    for i = 0, items:size() - 1 do
      local it = items:get(i)
      if it and it.getFullType then
        local ft = it:getFullType()
        local price = getJewelPriceForFullType(ft)
        if price and price > 0 then
          summary[ft] = summary[ft] or { count = 0, price = price }
          summary[ft].count = summary[ft].count + 1
          summary[ft].price = price -- por si cambia según config
        end
      end

      if it and it.IsInventoryContainer and it:IsInventoryContainer() then
        local childInv = it.getInventory and it:getInventory() or nil
        scanInventory(childInv)
      end
    end
  end

  scanInventory(inv)
  return summary
end



local function calcTotal(toSell)
  local total = 0
  for fullType, cnt in pairs(toSell or {}) do
	local price = AutoPawnShop.GetJewelPrice(fullType) or 0
    total = total + (price * (tonumber(cnt) or 0))
  end
  return total
end

function PawnPanel:updateHeader()
  local st = getClientState()
  setHeader(self, "Card Balance: " .. fmtMoney(st.balance), cardStatusText(st))
end

function PawnPanel:onStateChanged()
  self:updateHeader()
  if self._apsTotalTopLabel then
    self._apsTotalTopLabel:setName("Total: " .. fmtMoney(calcTotal(self.toSell)))
  end
  setHeader(self,
    "Card Balance: " .. fmtMoney(getClientState().balance),
    cardStatusText(getClientState())
  )
end

function PawnPanel:updatePreviewFromSelected()
  if not self.previewName then return end
  local row = self.invList.items[self.invList.selected]
  if not row or not row.item then
    self.previewName:setName("Select a jewel to preview")
    self.previewInfo:setName("")
    self.previewSub:setName("")
    self.previewIconTex = nil
    return
  end
  local d = row.item
  self.previewIconTex = d.tex
  self.previewName:setName(tostring(d.displayName or d.fullType))
  self.previewInfo:setName("You have: x" .. tostring(d.max or d.count or 0) .. "  -  Price: " .. fmtMoney(d.price or 0))
  self.previewSub:setName("Tip: add with >> and confirm to sell.")
end

function PawnPanel:refreshLists()
  self.invList:clear()
  self.sellList:clear()

  local player = getPlayer()
  local invSummary = buildJewelInventorySummary(player)

  self._invCache = {}
  for fullType, info in pairs(invSummary) do
    local displayName = getItemDisplayNameByFullType(fullType)
    local tex = getItemTextureByFullType(fullType)
    self._invCache[fullType] = {
      fullType = fullType, count = info.count, max = info.count,
      price = info.price, displayName = displayName, tex = tex,
      subtotal = info.price * info.count,
    }
    self.invList:addItem(displayName, {
      fullType = fullType, max = info.count, count = info.count,
      price = info.price, displayName = displayName, tex = tex,
      subtotal = info.price * info.count,
    })
  end

  for fullType, cnt in pairs(self.toSell) do
	local price = getJewelPriceForFullType(fullType)
    local displayName = getItemDisplayNameByFullType(fullType)
    local tex = getItemTextureByFullType(fullType)
    self.sellList:addItem(displayName, {
      fullType = fullType, count = cnt, price = price,
      displayName = displayName, tex = tex, subtotal = price * cnt,
    })
  end

  local total = calcTotal(self.toSell)
  if self.totalLabel then self.totalLabel:setName("Total: " .. fmtMoney(total)) end
  if self._apsTotalTopLabel then self._apsTotalTopLabel:setName("Total: " .. fmtMoney(total)) end

  self:updateHeader()
  self:updatePreviewFromSelected()
end

function PawnPanel:relayout()
  local pad = 12
  local top = 12
  local headerY = 88
  local listTop = 160

  local footerH = 48
  local midW = 80

  local rowH = math.max(40, math.min(74, math.floor(self.height / 8.0)))
  if self.invList and self.invList.setRowHeight then self.invList:setRowHeight(rowH) end
  if self.sellList and self.sellList.setRowHeight then self.sellList:setRowHeight(rowH) end

  if self.title then
    local tw = getTextW(UIFont.Large, self.title.name or "")
    self.title:setX(math.floor((self.width - tw) / 2))
    self.title:setY(top)
  end

  if self.subTitle then
    local sw = getTextW(UIFont.Small, self.subTitle.name or "")
    self.subTitle:setX(math.floor((self.width - sw) / 2))
    self.subTitle:setY(top + 40)
  end

  if self._apsBalanceLabel then self._apsBalanceLabel:setX(pad); self._apsBalanceLabel:setY(headerY) end
  if self._apsCardLabel then self._apsCardLabel:setY(headerY) end
  if self._apsTotalTopLabel then self._apsTotalTopLabel:setY(headerY) end
  setHeader(self,
    self._apsBalanceLabel and self._apsBalanceLabel.name or "",
    self._apsCardLabel and self._apsCardLabel.name or ""
  )

  if self.invTitle then self.invTitle:setX(pad); self.invTitle:setY(listTop - 22) end

  local leftW = math.floor((self.width - pad*3 - midW) * 0.5)
  local rightW = (self.width - pad*3 - midW) - leftW
  local leftX = pad
  local midX = leftX + leftW + pad
  local rightX = midX + midW + pad

  if self.sellTitle then self.sellTitle:setX(rightX); self.sellTitle:setY(listTop - 22) end

  local listH = self.height - listTop - footerH - 150
  listH = math.max(170, listH)

  if self.invList then
    self.invList:setX(leftX); self.invList:setY(listTop)
    self.invList:setWidth(leftW); self.invList:setHeight(listH)
  end

  if self.sellList then
    self.sellList:setX(rightX); self.sellList:setY(listTop)
    self.sellList:setWidth(rightW); self.sellList:setHeight(math.max(130, math.floor(listH * 0.70)))
  end

  local btnW, btnH = 70, 32
  local btnX = midX + math.floor((midW - btnW) / 2)
  local centerY = listTop + math.floor(listH / 2)
  local firstY = centerY - 70
  local step = 40

  if self.addBtn then self.addBtn:setX(btnX); self.addBtn:setY(firstY) end
  if self.remBtn then self.remBtn:setX(btnX); self.remBtn:setY(firstY + step) end
  if self.clearBtn then self.clearBtn:setX(btnX); self.clearBtn:setY(firstY + step*2) end
  if self.allBtn then self.allBtn:setX(btnX); self.allBtn:setY(firstY + step*3) end

  local prevY = listTop + (self.sellList and self.sellList.height or 160) + 10
  local prevH = 120
  if self.previewBox then
    self.previewBox:setX(rightX); self.previewBox:setY(prevY)
    self.previewBox:setWidth(rightW); self.previewBox:setHeight(prevH)
  end

  local actionY = self.height - 46
  local actionW = math.max(150, math.floor(rightW * 0.45))
  local gap = 10
  if self.sellBtn then self.sellBtn:setX(rightX); self.sellBtn:setY(actionY); self.sellBtn:setWidth(actionW); self.sellBtn:setHeight(32) end
  if self.closeBtn then self.closeBtn:setX(rightX + actionW + gap); self.closeBtn:setY(actionY); self.closeBtn:setWidth(actionW); self.closeBtn:setHeight(32) end
end

function PawnPanel:prerender()
  ISPanel.prerender(self)
  if apsTooFar(self) then self:onClose() return end
  if self._apsLastW ~= self.width or self._apsLastH ~= self.height then
    self._apsLastW, self._apsLastH = self.width, self.height
    if self.relayout then self:relayout() end
    if self.keepWithinScreen then self:keepWithinScreen() end
  end
end

function PawnPanel:initialise()
  ISPanel.initialise(self)
  enableResizable(self, 760, 480, "pawn")

  self.backgroundColor = { r=0, g=0, b=0, a=0.88 }
  self.borderColor = { r=1, g=1, b=1, a=0.20 }

  self.title = ISLabel:new(14, 10, 20, "Pawn Kiosk", 1, 1, 1, 1, UIFont.Large, true)
  self:addChild(self.title)

  self.subTitle = ISLabel:new(14, 30, 20, "Sell Jewels and deposit to your Credit Card", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
  self:addChild(self.subTitle)

  self._apsBalanceLabel = ISLabel:new(14, 52, 20, "Card Balance: " .. fmtMoney(getClientState().balance), 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self._apsBalanceLabel)

  self._apsTotalTopLabel = ISLabel:new(14, 52, 20, "Total: " .. fmtMoney(0), 1, 0.2, 0.2, 1, UIFont.Medium, true)
  self:addChild(self._apsTotalTopLabel)

  self._apsCardLabel = ISLabel:new(14, 52, 20, cardStatusText(getClientState()), 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self._apsCardLabel)

  self.invTitle = ISLabel:new(14, 78, 20, "Your Jewels", 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self.invTitle)

  self.invList = APSItemList:new(14, 100, 360, 250)
  self.invList:initialise()
  self.invList.onMouseDown = function(list, x, y)
    ISScrollingListBox.onMouseDown(list, x, y)
    if self and self.updatePreviewFromSelected then self:updatePreviewFromSelected() end
  end
  self:addChild(self.invList)

  self.addBtn = ISButton:new(386, 155, 70, 32, ">>", self, PawnPanel.onAdd)
  self:addChild(self.addBtn)

  self.remBtn = ISButton:new(386, 195, 70, 32, "<<", self, PawnPanel.onRemove)
  self:addChild(self.remBtn)

  self.clearBtn = ISButton:new(386, 235, 70, 32, "CLR", self, PawnPanel.onClear)
  self:addChild(self.clearBtn)

  self.allBtn = ISButton:new(386, 275, 70, 32, "ALL", self, PawnPanel.onAddAll)
  self:addChild(self.allBtn)

  self.sellTitle = ISLabel:new(460, 78, 20, "To Sell", 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self.sellTitle)

  self.sellList = APSItemList:new(460, 100, 360, 190)
  self.sellList:initialise()
  self:addChild(self.sellList)

  self.previewBox = ISPanel:new(460, 298, 360, 120)
  self.previewBox:initialise()
  self.previewBox.backgroundColor = { r=0, g=0, b=0, a=0.40 }
  self.previewBox.borderColor = { r=1, g=1, b=1, a=0.20 }
  self:addChild(self.previewBox)

  self.previewName = ISLabel:new(92, 10, 20, "Select a jewel to preview", 1, 1, 1, 1, UIFont.Medium, true)
  self.previewBox:addChild(self.previewName)

  self.previewInfo = ISLabel:new(92, 36, 20, "", 0.9, 0.9, 0.9, 1, UIFont.Small, true)
  self.previewBox:addChild(self.previewInfo)

  self.previewSub = ISLabel:new(92, 58, 20, "", 0.8, 0.8, 0.8, 1, UIFont.Small, true)
  self.previewBox:addChild(self.previewSub)

  self.previewIconTex = nil
  self.previewBox.prerender = function(box)
    ISPanel.prerender(box)
    local tex = self.previewIconTex
    local x, y = 12, 12
    local s = 70
    if tex then
      box:drawTextureScaledAspect(tex, x, y, s, s, 1, 1, 1, 1)
      box:drawRectBorder(x-1, y-1, s+2, s+2, 0.25, 1, 1, 1)
    else
      box:drawRect(x, y, s, s, 0.18, 1, 1, 1)
      box:drawRectBorder(x, y, s, s, 0.20, 1, 1, 1)
    end
  end

  self.totalLabel = ISLabel:new(14, 420, 20, "Total: " .. fmtMoney(0), 1, 1, 1, 1, UIFont.Large, true)
  self.totalLabel:setVisible(false)
  self:addChild(self.totalLabel)

  self.sellBtn = ISButton:new(460, 460, 200, 32, "Confirm Sell", self, PawnPanel.onConfirmSell)
  self:addChild(self.sellBtn)

  self.closeBtn = ISButton:new(670, 460, 200, 32, "Close", self, PawnPanel.onClose)
  self:addChild(self.closeBtn)

  if isClient() then
    sendClientCommand("AutoPawnShop", "RequestSync", {})
  end

  self:refreshLists()
  self:relayout()
end

function PawnPanel:onAdd()
  local row = self.invList.items[self.invList.selected]
  if not row then AutoPawnShopUI_Toast("Select a jewel first.") return end
  local data = row.item
  if not data or not data.fullType then AutoPawnShopUI_Toast("Invalid item.") return end

  local ft = data.fullType
  local current = self.toSell[ft] or 0
  if current < (data.max or 0) then
    self.toSell[ft] = current + 1
  else
    AutoPawnShopUI_Toast("No more of that jewel.")
  end
  self:refreshLists()
end

function PawnPanel:onRemove()
  local row = self.sellList.items[self.sellList.selected]
  if not row then AutoPawnShopUI_Toast("Select a jewel to remove.") return end
  local data = row.item
  if not data or not data.fullType then AutoPawnShopUI_Toast("Invalid item.") return end

  local ft = data.fullType
  local current = self.toSell[ft] or 0
  if current <= 1 then self.toSell[ft] = nil else self.toSell[ft] = current - 1 end
  self:refreshLists()
end

function PawnPanel:onClear()
  self.toSell = {}
  self:refreshLists()
end

function PawnPanel:onAddAll()
  self.toSell = {}
  for i = 1, #self.invList.items do
    local row = self.invList.items[i]
    if row and row.item and row.item.fullType then
      local ft = row.item.fullType
      local max = tonumber(row.item.max or row.item.count or 0) or 0
      if max > 0 then self.toSell[ft] = max end
    end
  end
  self:refreshLists()
end
local function isMultiplayerClient()
  return isClient() and not isServer()  -- client puro
end

function PawnPanel:onConfirmSell()
  local st = getClientState()
  if not st.hasCard then AutoPawnShopUI_Toast("You need a Credit Card to deposit the money.") return end
  if not st.linked then AutoPawnShopUI_Toast("Your credit card is not linked.") return end

  local total = calcTotal(self.toSell)
  if total <= 0 then AutoPawnShopUI_Toast("Select jewels to sell first.") return end

  if isMultiplayerClient() then
    sendClientCommand("AutoPawnShop", "SellSelectedJewels", { toSell = self.toSell })
    sendClientCommand("AutoPawnShop", "RequestSync", {})
  else
    -- SP o host local
    if AutoPawnShop and AutoPawnShop.SellSelectedJewelsLocal then
      local ok, msg = AutoPawnShop.SellSelectedJewelsLocal(getPlayer(), self.toSell)
      AutoPawnShopUI_Toast(msg or (ok and "Sold." or "Sell failed."))
    else
      AutoPawnShopUI_Toast("Sell function missing (SP).")
      return
    end
  end

  self.toSell = {}
  self:refreshLists()
end



function PawnPanel:onClose()
  self:setVisible(false)
  self:removeFromUIManager()
end

function AutoPawnShopUI_OpenPawn(playerNum, worldobject)
  local w, h = apsLoadSize("pawn", 980, 560)
  local x = (getCore():getScreenWidth() / 2) - (w / 2)
  local y = (getCore():getScreenHeight() / 2) - (h / 2)

  local panel = PawnPanel:new(x, y, w, h)
  panel._apsMachine = worldobject
  panel._apsMaxDist = 2.5
  panel:initialise()
  panel:addToUIManager()
  AutoPawnShopUI.pawnPanel = panel
end

-- =========================================================
-- =========================
--    SHOP (BUY) UI
-- =========================
-- =========================================================
local ShopPanel = ISPanel:derive("ShopPanel")

function ShopPanel:new(x, y, w, h)
  local o = ISPanel:new(x, y, w, h)
  setmetatable(o, self)
  self.__index = self
  o.moveWithMouse = true
  o.cart = {}
  o._catCache = {}
  o.selQty = 1
  o._apsMachine = nil
  o._apsMaxDist = 2.5
  o.isLinking = false
  return o
end

local function getPriceFromCatalog(fullType)
  for _, e in ipairs(Cfg.ShopCatalog or {}) do
    if e and e.item == fullType then return tonumber(e.price) or 0 end
  end
  return 0
end

local function calcCartTotal(cart)
  local total = 0
  for ft, qty in pairs(cart or {}) do
    local price = getPriceFromCatalog(ft)
    total = total + (price * (tonumber(qty) or 0))
  end
  return total
end

local function parseQty(txt)
  local n = tonumber(txt)
  n = math.floor(n or 1)
  if n < 1 then n = 1 end
  if n > 999 then n = 999 end
  return n
end

function ShopPanel:setLinking(flag)
  self.isLinking = (flag == true)
  if self.linkBtn then
    self.linkBtn:setEnable(not self.isLinking)
  end
end

function ShopPanel:updateHeader()
  local st = getClientState()
  setHeader(self, "Card Balance: " .. fmtMoney(st.balance), cardStatusText(st))
end

function ShopPanel:onStateChanged()
  self:updateHeader()
  self:updateCardStateUI()
  self:refreshTotalsOnly()
end

function ShopPanel:updateCardStateUI()
  local st = getClientState()

  local hasCard = st.hasCard
  local linked  = st.linked

  setHeader(self,
    "Card Balance: " .. fmtMoney(st.balance),
    (hasCard and (linked and "Credit Card: OK" or "Credit Card: UNLINKED") or "Credit Card: MISSING")
  )

  if not hasCard then
    self.msgLabel:setName("Falta la tarjeta de credito para comprar.")
    self.buyBtn:setEnable(false)
    self.addBtn:setEnable(false)
    if self.linkBtn then self.linkBtn:setVisible(false) end
  elseif not linked then
    self.msgLabel:setName("Tarjeta sin vincular. Click derecho -> Link o usa Link Card.")
    self.buyBtn:setEnable(false)
    self.addBtn:setEnable(false)
    if self.linkBtn then self.linkBtn:setVisible(true) end
  else
    self.msgLabel:setName("")
    self.buyBtn:setEnable(true)
    self.addBtn:setEnable(true)
    if self.linkBtn then self.linkBtn:setVisible(false) end
  end
end

function ShopPanel:refreshTotalsOnly()
  local total = calcCartTotal(self.cart)

  if self._apsTotalTopLabel then
    self._apsTotalTopLabel:setName("Total: " .. fmtMoney(total))
  end

  local st = getClientState()
  if total > (tonumber(st.balance) or 0) then
    self.warnLabel:setName("Saldo insuficiente. Quita items del carrito.")
    self.warnLabel:setVisible(true)
    if self.buyBtn then self.buyBtn:setEnable(false) end
  else
    self.warnLabel:setVisible(false)
    self:updateCardStateUI()
  end

  setHeader(self,
    self._apsBalanceLabel and self._apsBalanceLabel.name or "",
    self._apsCardLabel and self._apsCardLabel.name or ""
  )
end

function ShopPanel:setSelQty(n)
  n = math.floor(tonumber(n) or 1)
  if n < 1 then n = 1 end
  if n > 999 then n = 999 end
  self.selQty = n
  if self.qtyEntry then self.qtyEntry:setText(tostring(n)) end
  if self.qtyLabel then self.qtyLabel:setName("Qty: " .. tostring(n)) end
end

function ShopPanel:canAddToCart(fullType, addQty)
  local st = getClientState()
  local bal = tonumber(st.balance) or 0
  local currentTotal = calcCartTotal(self.cart)
  local price = getPriceFromCatalog(fullType)
  local addCost = price * (tonumber(addQty) or 0)
  return (currentTotal + addCost) <= bal
end

function ShopPanel:refreshLists()
  self.catList:clear()
  self.cartList:clear()
  self._catCache = {}

  for _, entry in ipairs(Cfg.ShopCatalog or {}) do
    local ft = entry.item
    local price = tonumber(entry.price) or 0
    local displayName = getItemDisplayNameByFullType(ft)
    local tex = getItemTextureByFullType(ft)
    self._catCache[ft] = { price = price, displayName = displayName, tex = tex }

    self.catList:addItem(displayName, {
      fullType = ft, displayName = displayName, price = price,
      count = 1, tex = tex, subtotal = price,
    })
  end

  for ft, qty in pairs(self.cart or {}) do
    local info = self._catCache[ft]
    local price = (info and info.price) or getPriceFromCatalog(ft)
    local displayName = (info and info.displayName) or getItemDisplayNameByFullType(ft)
    local tex = (info and info.tex) or getItemTextureByFullType(ft)
    self.cartList:addItem(displayName, {
      fullType = ft, displayName = displayName, price = price,
      count = qty, tex = tex, subtotal = price * qty,
    })
  end

  self:refreshTotalsOnly()
end

function ShopPanel:onCatalogSelectionChanged()
  local row = self.catList.items[self.catList.selected]
  if not row or not row.item then
    self.selName:setName("Select an item")
    self.selPrice:setName("")
    return
  end
  local d = row.item
  self.selName:setName(tostring(d.displayName or d.fullType))
  self.selPrice:setName("Price: " .. fmtMoney(d.price or 0))
end

function ShopPanel:relayout()
  local pad = 12
  local top = 10
  local headerY = 60

  local rowH = math.max(40, math.min(74, math.floor(self.height / 8.0)))
  if self.catList and self.catList.setRowHeight then self.catList:setRowHeight(rowH) end
  if self.cartList and self.cartList.setRowHeight then self.cartList:setRowHeight(rowH) end

  if self.title then self.title:setX(pad); self.title:setY(top) end
  if self._apsBalanceLabel then self._apsBalanceLabel:setX(pad); self._apsBalanceLabel:setY(headerY) end
  if self._apsTotalTopLabel then self._apsTotalTopLabel:setY(headerY) end
  if self._apsCardLabel then self._apsCardLabel:setY(headerY) end
  setHeader(self,
    self._apsBalanceLabel and self._apsBalanceLabel.name or "",
    self._apsCardLabel and self._apsCardLabel.name or ""
  )

  if self.msgLabel then self.msgLabel:setX(pad); self.msgLabel:setY(74) end

  local listTop = 132
  local footerH = 64
  local midW = 80

  local leftW = math.floor((self.width - pad*3 - midW) * 0.5)
  local rightW = leftW
  local leftX = pad
  local midX = leftX + leftW + pad
  local rightX = midX + midW + pad

  local listH = self.height - listTop - footerH - 160
  listH = math.max(170, listH)

  if self.catTitle then self.catTitle:setX(leftX); self.catTitle:setY(listTop - 22) end
  if self.catList then
    self.catList:setX(leftX); self.catList:setY(listTop)
    self.catList:setWidth(leftW); self.catList:setHeight(listH)
  end

  if self.cartTitle then self.cartTitle:setX(rightX); self.cartTitle:setY(listTop - 22) end
  if self.cartList then
    self.cartList:setX(rightX); self.cartList:setY(listTop)
    self.cartList:setWidth(rightW); self.cartList:setHeight(listH)
  end

  local btnW, btnH = 70, 32
  local btnY = listTop + math.floor(listH/2) - 60
  if self.addBtn then self.addBtn:setX(midX + math.floor((midW-btnW)/2)); self.addBtn:setY(btnY) end
  if self.remBtn then self.remBtn:setX(midX + math.floor((midW-btnW)/2)); self.remBtn:setY(btnY + 40) end
  if self.clearBtn then self.clearBtn:setX(midX + math.floor((midW-btnW)/2)); self.clearBtn:setY(btnY + 80) end

  local selBoxY = listTop + listH + 10
  local selBoxH = 100
  if self.selBox then
    self.selBox:setX(leftX); self.selBox:setY(selBoxY)
    self.selBox:setWidth(leftW); self.selBox:setHeight(selBoxH)
  end

  local actionY = self.height - 46
  local actionW = math.max(160, math.floor(rightW * 0.45))
  local gap = 10
  if self.buyBtn then self.buyBtn:setX(rightX); self.buyBtn:setY(actionY); self.buyBtn:setWidth(actionW); self.buyBtn:setHeight(32) end
  if self.closeBtn then self.closeBtn:setX(rightX + actionW + gap); self.closeBtn:setY(actionY); self.closeBtn:setWidth(actionW); self.closeBtn:setHeight(32) end

  if self.linkBtn then
    self.linkBtn:setX(rightX)
    self.linkBtn:setY(actionY + 40)
    self.linkBtn:setWidth(actionW)
    self.linkBtn:setHeight(28)
  end
end

function ShopPanel:prerender()
  ISPanel.prerender(self)
  if apsTooFar(self) then self:onClose() return end
  if self._apsLastW ~= self.width or self._apsLastH ~= self.height then
    self._apsLastW, self._apsLastH = self.width, self.height
    if self.relayout then self:relayout() end
    if self.keepWithinScreen then self:keepWithinScreen() end
  end
end

function ShopPanel:initialise()
  ISPanel.initialise(self)
  enableResizable(self, 860, 520, "shop")

  self.backgroundColor = { r=0, g=0, b=0, a=0.85 }
  self.borderColor = { r=1, g=1, b=1, a=0.25 }

  self.title = ISLabel:new(12, 10, 20, "Vending (Buy with Credit Card)", 1, 1, 1, 1, UIFont.Large, true)
  self:addChild(self.title)

  self._apsBalanceLabel = ISLabel:new(12, 44, 20, "Card Balance: " .. fmtMoney(getClientState().balance), 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self._apsBalanceLabel)

  self._apsTotalTopLabel = ISLabel:new(12, 44, 20, "Total: " .. fmtMoney(0), 1, 0.2, 0.2, 1, UIFont.Medium, true)
  self:addChild(self._apsTotalTopLabel)

  self._apsCardLabel = ISLabel:new(12, 44, 20, cardStatusText(getClientState()), 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self._apsCardLabel)

  self.msgLabel = ISLabel:new(12, 74, 20, "", 1, 1, 1, 1, UIFont.Small, true)
  self:addChild(self.msgLabel)

  self.catTitle = ISLabel:new(12, 98, 20, "Catalog", 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self.catTitle)

  self.catList = APSItemList:new(12, 120, 520, 260)
  self.catList:initialise()
  self.catList.onMouseDown = function(list, x, y)
    ISScrollingListBox.onMouseDown(list, x, y)
    if self and self.onCatalogSelectionChanged then self:onCatalogSelectionChanged() end
  end
  self:addChild(self.catList)

  self.addBtn = ISButton:new(544, 200, 70, 32, ">>", self, ShopPanel.onAdd)
  self:addChild(self.addBtn)

  self.remBtn = ISButton:new(544, 240, 70, 32, "<<", self, ShopPanel.onRemove)
  self:addChild(self.remBtn)

  self.clearBtn = ISButton:new(544, 280, 70, 32, "CLR", self, ShopPanel.onClear)
  self:addChild(self.clearBtn)

  self.cartTitle = ISLabel:new(630, 98, 20, "Cart", 1, 1, 1, 1, UIFont.Medium, true)
  self:addChild(self.cartTitle)

  self.cartList = APSItemList:new(630, 120, 520, 220)
  self.cartList:initialise()
  self:addChild(self.cartList)

  self.selBox = ISPanel:new(12, 390, 520, 100)
  self.selBox:initialise()
  self.selBox.backgroundColor = { r=0, g=0, b=0, a=0.40 }
  self.selBox.borderColor = { r=1, g=1, b=1, a=0.20 }
  self:addChild(self.selBox)

  self.selName = ISLabel:new(12, 10, 20, "Select an item", 1, 1, 1, 1, UIFont.Medium, true)
  self.selBox:addChild(self.selName)

  self.selPrice = ISLabel:new(12, 34, 20, "", 0.85, 0.85, 0.85, 1, UIFont.Small, true)
  self.selBox:addChild(self.selPrice)

  self.qtyLabel = ISLabel:new(12, 62, 20, "Qty: 1", 1, 1, 1, 1, UIFont.Medium, true)
  self.selBox:addChild(self.qtyLabel)

  self.qtyMinus = ISButton:new(110, 58, 40, 28, "-", self, ShopPanel.onQtyMinus)
  self.selBox:addChild(self.qtyMinus)

  self.qtyPlus = ISButton:new(156, 58, 40, 28, "+", self, ShopPanel.onQtyPlus)
  self.selBox:addChild(self.qtyPlus)

  self.qtyEntry = ISTextEntryBox:new("1", 206, 58, 70, 28)
  self.qtyEntry:initialise()
  self.qtyEntry.onCommandEntered = function(entry)
    self:setSelQty(parseQty(entry:getText()))
  end
  self.selBox:addChild(self.qtyEntry)

  self.qtyApply = ISButton:new(282, 58, 90, 28, "Set", self, ShopPanel.onQtySet)
  self.selBox:addChild(self.qtyApply)

  self.warnLabel = ISLabel:new(630, 328, 20, "Saldo insuficiente. Quita items del carrito.", 1, 0.7, 0.7, 1, UIFont.Small, true)
  self.warnLabel:setVisible(false)
  self:addChild(self.warnLabel)

  self.buyBtn = ISButton:new(630, 390, 220, 32, "Buy (Confirm)", self, ShopPanel.onBuy)
  self:addChild(self.buyBtn)

  self.closeBtn = ISButton:new(860, 390, 220, 32, "Close", self, ShopPanel.onClose)
  self:addChild(self.closeBtn)

  -- ✅ FIX: Link usa el cliente (SP-safe / MP manda comando)
  self.linkBtn = ISButton:new(630, 430, 220, 28, "Link Card", self, function()
    if AutoPawnShop and AutoPawnShop.RequestLinkCard then
      self:setLinking(true)
      AutoPawnShop.RequestLinkCard()
      self:setLinking(false)
    else
      AutoPawnShopUI_Toast("Client link function missing.")
    end
  end)
  self:addChild(self.linkBtn)
  self.linkBtn:setVisible(false)

  if isClient() then
    sendClientCommand("AutoPawnShop", "RequestSync", {})
  end

  self:refreshLists()
  self:updateCardStateUI()
  self:onCatalogSelectionChanged()
  self:relayout()
end

function ShopPanel:onQtyMinus() self:setSelQty((self.selQty or 1) - 1) end
function ShopPanel:onQtyPlus()  self:setSelQty((self.selQty or 1) + 1) end
function ShopPanel:onQtySet()   self:setSelQty(parseQty(self.qtyEntry and self.qtyEntry:getText() or "1")) end

function ShopPanel:onAdd()
  local row = self.catList.items[self.catList.selected]
  if not row or not row.item or not row.item.fullType then
    AutoPawnShopUI_Toast("Select an item from the catalog.")
    return
  end

  local ft = row.item.fullType
  local qty = tonumber(self.selQty) or 1
  if qty < 1 then qty = 1 end

  if not self:canAddToCart(ft, qty) then
    AutoPawnShopUI_Toast("Insufficient balance. You cannot add more items.")
    self:refreshTotalsOnly()
    return
  end

  self.cart[ft] = (self.cart[ft] or 0) + qty
  self:refreshLists()
end

function ShopPanel:onRemove()
  local row = self.cartList.items[self.cartList.selected]
  if not row or not row.item or not row.item.fullType then
    AutoPawnShopUI_Toast("Select an item from the cart.")
    return
  end

  local ft = row.item.fullType
  local qty = tonumber(self.selQty) or 1
  if qty < 1 then qty = 1 end

  local cur = self.cart[ft] or 0
  cur = cur - qty
  if cur <= 0 then self.cart[ft] = nil else self.cart[ft] = cur end

  self:refreshLists()
end

function ShopPanel:onClear()
  self.cart = {}
  self:refreshLists()
end

function ShopPanel:onBuy()
  self:updateCardStateUI()

  local st = getClientState()
  if not st.hasCard then AutoPawnShopUI_Toast("Missing Credit Card.") return end
  if not st.linked  then AutoPawnShopUI_Toast("Your credit card is not linked.") return end

  local total = calcCartTotal(self.cart)
  if total <= 0 then AutoPawnShopUI_Toast("Add items to the cart first.") return end
  if total > (tonumber(st.balance) or 0) then
    AutoPawnShopUI_Toast("Insufficient balance.")
    self:refreshTotalsOnly()
    return
  end

for ft, qty in pairs(self.cart) do
  local price = getPriceFromCatalog(ft)

  -- ✅ SP+MP: en MP manda comando al server, en SP compra local (lo resuelve el Client)
  if AutoPawnShop and AutoPawnShop.RequestBuyItem then
    AutoPawnShop.RequestBuyItem(ft, price, qty)
  else
    -- fallback viejo (por si no cargó el client modificado)
    sendClientCommand("AutoPawnShop", "BuyItem", { item = ft, price = price, qty = qty })
  end
end


  if isClient() then
    sendClientCommand("AutoPawnShop", "RequestSync", {})
  end

  self.cart = {}
  self:refreshLists()
end

function ShopPanel:onClose()
  self:setVisible(false)
  self:removeFromUIManager()
end

function AutoPawnShopUI_OpenShop(playerNum, worldobject)
  local w, h = apsLoadSize("shop", 1080, 620)
  local x = (getCore():getScreenWidth() / 2) - (w / 2)
  local y = (getCore():getScreenHeight() / 2) - (h / 2)

  local panel = ShopPanel:new(x, y, w, h)
  panel._apsMachine = worldobject
  panel._apsMaxDist = 2.5
  panel:initialise()
  panel:addToUIManager()
  AutoPawnShopUI.shopPanel = panel
end

function AutoPawnShopUI.GetBalance()
  local st = getClientState()
  return tonumber(st.balance) or 0
end

function AutoPawnShopUI_ShowCardInfoModal(cardItem)
  if not cardItem then AutoPawnShopUI_Toast("No card item.") return end

  local md = cardItem:getModData() or {}
  local owner = md.APS_owner or "Unlinked"

  local username = getUsernameSafe(getPlayer())
  local balanceText = "Balance: (owner-only)"
  if tostring(owner) == tostring(username) then
    balanceText = "Balance: " .. fmtMoney(AutoPawnShopUI.GetBalance())
  end

  local txt = "CREDIT CARD\n\nOwner: " .. tostring(owner) .. "\n" .. balanceText

  local w, h = 360, 190
  local x = (getCore():getScreenWidth() / 2) - (w / 2)
  local y = (getCore():getScreenHeight() / 2) - (h / 2)

  local modal = ISModalDialog:new(x, y, w, h, txt, true, nil, nil)
  modal:initialise()
  modal:addToUIManager()
end
print("[APS][UI] AutoPawnShop table=", tostring(AutoPawnShop))
print("[APS][UI] SellSelectedJewelsLocal=", tostring(AutoPawnShop and AutoPawnShop.SellSelectedJewelsLocal))
