AutoPawnShop = AutoPawnShop or {}

-- =========================================================
-- SAFETY: Config must always be a table
-- =========================================================
if type(AutoPawnShop.Config) ~= "table" then
  AutoPawnShop.Config = {}
end

local Cfg = AutoPawnShop.Config

-- =========================================================
-- GENERAL
-- =========================================================

-- Toggle logs (defaults, do not force override if already set)
if Cfg.DebugCard == nil then Cfg.DebugCard = true end
if Cfg.DebugLoot == nil then Cfg.DebugLoot = true end

-- Container types
Cfg.PawnKioskContainerType = Cfg.PawnKioskContainerType or "cashregister"
Cfg.CardShopContainerType  = Cfg.CardShopContainerType  or "vendingsnack"

-- UI scale
Cfg.UIScale     = Cfg.UIScale     or 1.25  -- escala general
Cfg.ShopUIScale = Cfg.ShopUIScale or 1.35  -- solo Comprar
Cfg.PawnUIScale = Cfg.PawnUIScale or 1.35  -- solo Vender

-- Credit card
Cfg.RequireCreditCardItem = Cfg.RequireCreditCardItem or "Base.CreditCard"
Cfg.BalanceKey            = Cfg.BalanceKey            or "APS_Balance"

-- Drop radius for finding vending
Cfg.DropRadius = Cfg.DropRadius or 3

-- =========================================================
-- JEWELS + WATCHES (SELL)
-- =========================================================

-- Ensure tables
if type(Cfg.JewelPrefixDefaultPrices) ~= "table" then Cfg.JewelPrefixDefaultPrices = {} end
if type(Cfg.JewelPrices) ~= "table" then Cfg.JewelPrices = {} end

-- ✅ Precios por prefijo (SOLO si NO está en JewelPrices)
-- Se evalúan en orden: el primero que matchee gana.
-- (si querés que esto sea “default” y no pisar si ya lo setearon, dejalo como está)
Cfg.JewelPrefixDefaultPrices = {
  { prefix = "Base.Ring",        price = 85 },
  { prefix = "Base.Earring",     price = 75 },
  { prefix = "Base.Earrings",    price = 75 },
  { prefix = "Base.Bracelet",    price = 80 },
  { prefix = "Base.Necklace",    price = 60 },
  { prefix = "Base.WristWatch",  price = 60 },
  { prefix = "Base.PocketWatch", price = 85 },
}

-- ✅ Lista explícita (tiene prioridad sobre el prefijo)
Cfg.JewelPrices = {
  -- Rings
  ["Base.Ring_Left_RingFinger_Gold"]      = 85,
  ["Base.Ring_Right_RingFinger_Gold"]     = 85,
  ["Base.Ring_Left_RingFinger_Silver"]    = 65,
  ["Base.Ring_Right_RingFinger_Silver"]   = 65,

  ["Base.Ring_Gold"]                      = 80,
  ["Base.Ring_Silver"]                    = 60,
  ["Base.GoldRing"]                       = 80,
  ["Base.SilverRing"]                     = 60,

  ["Base.Ring_Left_RingFinger_Diamond"]   = 190,
  ["Base.Ring_Right_RingFinger_Diamond"]  = 190,
  ["Base.DiamondRing"]                    = 190,

  ["Base.Ring_Left_RingFinger_Emerald"]   = 165,
  ["Base.Ring_Right_RingFinger_Emerald"]  = 165,
  ["Base.EmeraldRing"]                    = 165,

  ["Base.Ring_Left_RingFinger_Ruby"]      = 165,
  ["Base.Ring_Right_RingFinger_Ruby"]     = 165,
  ["Base.RubyRing"]                       = 165,

  ["Base.Ring_Left_RingFinger_Sapphire"]  = 165,
  ["Base.Ring_Right_RingFinger_Sapphire"] = 165,
  ["Base.SapphireRing"]                   = 165,

  -- Necklaces
  ["Base.Necklace_Gold"]                  = 135,
  ["Base.Necklace_Silver"]                = 105,
  ["Base.Necklace_Pearl"]                 = 125,
  ["Base.Necklace_Beads"]                 = 55,
  ["Base.Necklace"]                       = 45,

  -- Earrings
  ["Base.Earring_Gold"]                   = 60,
  ["Base.Earring_Silver"]                 = 45,
  ["Base.Earrings_Gold"]                  = 60,
  ["Base.Earrings_Silver"]                = 45,

  -- Bracelets
  ["Base.Bracelet_Gold"]                  = 95,
  ["Base.Bracelet_Silver"]                = 75,
  ["Base.Bracelet"]                       = 55,

  -- Watches
  ["Base.WristWatch"]                     = 45,
  ["Base.WristWatch_Classic"]             = 65,
  ["Base.WristWatch_Digital"]             = 70,
  ["Base.WristWatch_Gold"]                = 115,
  ["Base.WristWatch_Silver"]              = 90,
  ["Base.PocketWatch"]                    = 85,
}

-- =========================================================
-- SHOP (BUY)
-- =========================================================

-- Ensure table
if type(Cfg.ShopCatalog) ~= "table" then Cfg.ShopCatalog = {} end

-- ✅ Rebalance: subo precios del shop (más “real”)
Cfg.ShopCatalog = {
  { item = "Base.NailsBox",          price = 520 },
  { item = "Base.DuctTape",          price = 450 },
  { item = "Base.Woodglue",          price = 420 },
  { item = "Base.Screwdriver",       price = 320 },
  { item = "Base.Saw",               price = 620 },
  { item = "Base.Hammer",            price = 520 },
  { item = "Base.HandAxe",           price = 780 },
  { item = "Base.Axe",               price = 1600 },

  { item = "Base.PropaneTank",       price = 2200 },
  { item = "Base.WeldingMask",       price = 1200 },
  { item = "Base.WelderMask",        price = 1200 },
  { item = "Base.WeldingRods",       price = 950 },
  { item = "Base.BlowTorch",         price = 1400 },
  { item = "Base.PetrolCan",         price = 1600 },

  { item = "Base.Sledgehammer",      price = 14000 },
  { item = "Base.Generator",         price = 12000 },
  { item = "Base.GeneratorMagazine", price = 4500 },

  { item = "Base.ShotgunShellsBox",  price = 1500 },
  { item = "Base.9mmBulletsBox",     price = 1700 },
  { item = "Base.556Box",            price = 3200 },
  { item = "Base.308Box",            price = 3400 },

  { item = "Base.FirstAidKit",       price = 1500 },
  { item = "Base.Disinfectant",      price = 480 },
  { item = "Base.Battery",           price = 220 },
  { item = "Base.LightBulb",         price = 160 },
  { item = "Base.WalkieTalkie5",     price = 2800 },
}
