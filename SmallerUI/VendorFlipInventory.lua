local _, Addon = ...
local frame = CreateFrame("Frame")
local Flips = { pending = {} }
Addon.VendorFlipInventory = Flips

local MAIL_LIFETIME = 30 * 86400
local DELIVERY_WINDOW = 60

local function Now()
    return GetServerTime and GetServerTime() or time()
end

local function ItemKey(link)
    if type(link) ~= "string" then return end
    local key = link:match("(item:[^|]+)")
    if not key then return end
    while key:sub(-1) == ":" or key:sub(-2) == ":0" do
        key = key:gsub(":0?$", "")
    end
    return key
end

local function Ledger()
    if type(Addon.character.vendorFlipInventory) ~= "table" then Addon.character.vendorFlipInventory = {} end
    local ledger = Addon.character.vendorFlipInventory
    if type(ledger.receipts) ~= "table" then ledger.receipts = {} end
    if type(ledger.stacks) ~= "table" then ledger.stacks = {} end
    if type(ledger.otherPurchases) ~= "table" then ledger.otherPurchases = {} end
    return ledger
end

function Addon:RecordVendorFlipPurchase(purchase, cost)
    local link = ItemKey(purchase.link)
    if not purchase.unitPrice and not link then return end
    local receipts = Ledger().receipts
    receipts[#receipts + 1] = {
        itemID = purchase.deal.key.itemID, link = link, quantity = purchase.quantity, cost = cost,
        seller = purchase.seller, commodity = purchase.unitPrice ~= nil, at = Now(),
    }
    return true
end

function Addon:RecordOtherAuctionPurchase(commodity, itemID)
    local purchases = Ledger().otherPurchases
    purchases[#purchases + 1] = { at = Now(), commodity = commodity, itemID = itemID }
end

local function Notify(message)
    if message then Addon:Print(message) end
    if Addon.RefreshVendorFlipUI then Addon:RefreshVendorFlipUI() end
end

local function BagItems(wantedID)
    local items = {}
    local container = C_Container
    if not container or not ItemLocation or not C_Item or not C_Item.GetItemGUID then return items end
    local lastBag = Enum.BagIndex and (Enum.BagIndex.ReagentBag or Enum.BagIndex.Bag_4) or 4
    for bag = 0, lastBag do
        for slot = 1, container.GetContainerNumSlots(bag) do
            local info = container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and (not wantedID or wantedID == info.itemID) then
                local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                local guid = C_Item.GetItemGUID(location)
                if guid and info.stackCount and info.stackCount > 0 then
                    items[guid] = { bag = bag, slot = slot, guid = guid, info = info, count = info.stackCount,
                        key = ItemKey(info.hyperlink) }
                end
            end
        end
    end
    return items
end

function Flips:PruneReceipts()
    local ledger, oldest = Ledger(), Now() - MAIL_LIFETIME - DELIVERY_WINDOW
    for _, records in ipairs({ ledger.receipts, ledger.otherPurchases }) do
        for index = #records, 1, -1 do
            if records[index].at < oldest then table.remove(records, index) end
        end
    end
    return ledger.receipts
end

local function FindDelivery(mailIndex, clock)
    local _, _, _, _, money, cod, days, attachments = GetInboxHeaderInfo(mailIndex)
    if not attachments or attachments < 1 or money ~= 0 or cod ~= 0 or not days or days <= 0 then return end
    local kind, _, seller, paid = GetInboxInvoiceInfo(mailIndex)
    if kind ~= "buyer" or type(paid) ~= "number" or paid <= 0 then return end
    local total, itemID, key = 0, nil, nil
    local quantities, seen = {}, 0
    for index = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, id, _, count = GetInboxItem(mailIndex, index)
        if name then
            local link = ItemKey(GetInboxItemLink(mailIndex, index))
            if not id or not count or not link or (itemID and (id ~= itemID or link ~= key)) then return end
            itemID, key = id, link
            quantities[index] = count
            seen = seen + 1
            total = total + count
        end
    end
    if seen ~= attachments or not itemID then return end
    return { index = mailIndex, itemID = itemID, key = key, quantity = total, cost = paid, seller = seller,
        at = clock + days * 86400 - MAIL_LIFETIME, quantities = quantities }
end

local function SellerMatches(seller, recorded)
    if type(seller) ~= "string" or seller == "" or type(recorded) ~= "string" or recorded == "" then return true end
    if seller:lower() == recorded:lower() then return true end
    if seller:find("-", 1, true) and recorded:find("-", 1, true) then return false end
    return seller:lower():match("^[^-]+") == recorded:lower():match("^[^-]+")
end

local function Matches(delivery, receipt, quantity)
    return delivery.itemID == receipt.itemID and delivery.quantity == (quantity or receipt.remaining or receipt.quantity)
        and delivery.cost == receipt.cost
        and (not receipt.link or receipt.link == delivery.key) and math.abs(delivery.at - receipt.at) <= DELIVERY_WINDOW
        and SellerMatches(delivery.seller, receipt.seller)
end

local function OverlapsOtherPurchase(delivery, receipt, otherPurchases)
    for _, other in ipairs(otherPurchases) do
        if other.commodity == receipt.commodity and (not other.itemID or other.itemID == delivery.itemID)
            and math.abs(delivery.at - other.at) <= DELIVERY_WINDOW then
            return true
        end
    end
    return false
end

local function FindMail(receipts, itemID, visible, clock)
    local deliveries, byIndex = {}, {}
    local matchedMail = {}
    for index = 1, visible do
        local delivery = FindDelivery(index, clock)
        if delivery and delivery.itemID == itemID then
            for _, receipt in ipairs(receipts) do
                if Matches(delivery, receipt) then
                    if not byIndex[index] then byIndex[index] = {} end
                    byIndex[index][#byIndex[index] + 1] = receipt
                    if not matchedMail[receipt] then matchedMail[receipt] = {} end
                    local hits = matchedMail[receipt]
                    hits[#hits + 1] = index
                end
            end
            if byIndex[index] then deliveries[#deliveries + 1] = delivery end
        end
    end
    local candidates = {}
    local otherPurchases = Ledger().otherPurchases
    for _, delivery in ipairs(deliveries) do
        local matches = byIndex[delivery.index]
        local group = matchedMail[matches[1]]
        local balanced = #group == #matches
        -- Match repeated identical invoices only when the full group maps
        -- one-for-one to recorded purchases.
        for _, receipt in ipairs(matches) do
            local hits = matchedMail[receipt]
            if #hits ~= #group then balanced = false; break end
            for i, index in ipairs(group) do
                if hits[i] ~= index or #byIndex[index] ~= #matches then balanced = false; break end
            end
            if OverlapsOtherPurchase(delivery, receipt, otherPurchases) then balanced = false end
            if not balanced then break end
        end
        if balanced then
            delivery.receipt = matches[1]
            candidates[delivery.index] = delivery
        end
    end
    return candidates
end

local function RemoveReceipt(receipt)
    local receipts = Ledger().receipts
    for index, recorded in ipairs(receipts) do
        if recorded == receipt then table.remove(receipts, index); return end
    end
end

local function InboxQuantity(itemID, visible)
    local quantity = 0
    for index = 1, visible do
        local attachments = select(8, GetInboxHeaderInfo(index)) or 0
        local seen = 0
        for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
            if seen == attachments then break end
            local name, id, _, count = GetInboxItem(index, attachment)
            if name then
                if not id or not count then return end
                seen = seen + 1
                if id == itemID then quantity = quantity + count end
            end
        end
        if seen ~= attachments then return end
    end
    return quantity
end

local function AbortTake(take)
    Flips.pending[take.itemID] = nil
    if take.mailVerified then RemoveReceipt(take.receipt) end
end

local function InvoiceCounts(take, visible)
    local full, partial, clock = 0, 0, Now()
    for index = 1, visible do
        local delivery = FindDelivery(index, clock)
        if delivery then
            if Matches(delivery, take.receipt) then full = full + 1 end
            if take.remainder > 0 and Matches(delivery, take.receipt, take.remainder) then partial = partial + 1 end
        end
    end
    return full, partial
end

local function CheckTake(take)
    if Flips.mailOpen and not take.mailVerified then
        local visible, total = GetInboxNumItems()
        local remaining = visible and visible == total and InboxQuantity(take.itemID, visible)
        if not remaining then return end
        local decrease = take.inboxBefore - remaining
        if decrease > take.quantity then
            take.mailVerified = true
            AbortTake(take)
            return
        end
        if decrease ~= take.quantity then return end
        local full, partial = InvoiceCounts(take, visible)
        take.mailVerified = full == take.fullBefore - 1
            and (take.remainder == 0 or partial == take.partialBefore + 1)
    end
    if not take.mailVerified then return end

    local current, previous = BagItems(take.itemID), take.before
    local totalGain, gains = 0, {}
    for guid, item in pairs(current) do
        local old = previous[guid]
        local gain = item.count - (old and old.count or 0)
        if gain < 0 or (old and item.key ~= old.key) or (gain > 0 and item.key ~= take.key) then
            AbortTake(take)
            return
        end
        if gain > 0 then
            totalGain = totalGain + gain
            gains[guid] = item
        end
    end
    for guid in pairs(previous) do
        if not current[guid] then AbortTake(take); return end
    end
    if totalGain < take.quantity then return end
    if totalGain > take.quantity then AbortTake(take); return end

    Flips.pending[take.itemID] = nil
    local receipt = take.receipt
    receipt.remaining = take.remainder
    if receipt.remaining == 0 then RemoveReceipt(receipt) end
    local stacks, tagged = Ledger().stacks, 0
    for guid, item in pairs(gains) do
        local old, tracked = previous[guid], stacks[guid]
        if not old or (tracked and tracked.itemID == take.itemID and tracked.key == old.key and tracked.count == old.count) then
            stacks[guid] = { itemID = take.itemID, key = item.key, count = item.count }
            tagged = tagged + item.count - (old and old.count or 0)
        end
    end
    if tagged > 0 then Notify() end
end

local function CheckTakes()
    for _, take in pairs(Flips.pending) do CheckTake(take) end
end

-- Posty's attachment and whole-mail actions call these same native functions.
-- Their secure post-hooks run before the server updates the inbox and bags.
local function ObserveTake(mailIndex, attachmentIndex)
    if not Flips.mailOpen or not Addon.character or not Addon:GetVendorDealSettings().enabled
        or not GetInboxInvoiceInfo or not GetInboxItemLink or type(mailIndex) ~= "number" then return end
    CheckTakes()
    local receipts = Flips:PruneReceipts()
    if #receipts == 0 then return end
    local visible, total = GetInboxNumItems()
    if not visible or visible ~= total or mailIndex > visible then return end
    local targetID, overlaps
    for attachment = attachmentIndex or 1, attachmentIndex or (ATTACHMENTS_MAX_RECEIVE or 16) do
        local _, itemID = GetInboxItem(mailIndex, attachment)
        if itemID then targetID = itemID end
        if Flips.pending[itemID] then
            AbortTake(Flips.pending[itemID])
            overlaps = true
        end
    end
    if not targetID or overlaps then return end
    local delivery = FindMail(receipts, targetID, visible, Now())[mailIndex]
    if not delivery then return end
    local quantity = delivery.quantity
    if attachmentIndex then quantity = delivery.quantities[attachmentIndex] end
    local inboxBefore = InboxQuantity(delivery.itemID, visible)
    if not quantity or quantity <= 0 or not inboxBefore then return end
    local take = { itemID = delivery.itemID, key = delivery.key, quantity = quantity, receipt = delivery.receipt,
        remainder = delivery.quantity - quantity, before = BagItems(delivery.itemID), inboxBefore = inboxBefore }
    take.fullBefore, take.partialBefore = InvoiceCounts(take, visible)
    Flips.pending[take.itemID] = take
    C_Timer.After(6, function()
        if Flips.pending[take.itemID] ~= take then return end
        CheckTake(take)
        if Flips.pending[take.itemID] == take then AbortTake(take) end
    end)
end

function Flips:SellableStacks()
    if not Addon.character or not Addon:GetVendorDealSettings().enabled then return {} end
    local tracked = Ledger().stacks
    if not next(tracked) then return {} end
    local items, verified = BagItems(), {}
    for guid, record in pairs(tracked) do
        local item = items[guid]
        if not item or item.count ~= record.count or item.key ~= record.key or item.info.itemID ~= record.itemID then
            if not self.pending[record.itemID] then tracked[guid] = nil end
        elseif not item.info.hasNoValue then
            local name, _, _, _, _, _, _, _, _, texture, unitPrice = C_Item.GetItemInfo(item.info.hyperlink)
            if unitPrice and unitPrice > 0 then
                item.name, item.icon, item.value = name or item.info.hyperlink, item.info.iconFileID or texture, unitPrice * item.count
                verified[guid] = item
            end
        end
    end
    return verified
end

function Flips:CanSell()
    return self.merchantOpen and MerchantFrame and MerchantFrame:IsVisible() and MerchantFrame.selectedTab == 1
        and Addon:GetVendorDealSettings().enabled and not InCombatLockdown()
        and not GetCursorInfo() and not (InRepairMode and InRepairMode())
end

function Flips:Sell(reviewed)
    if self.selling or not self:CanSell() then return false end
    local sale = { index = 1, sold = 0, skipped = 0, value = 0 }
    self.selling = sale
    local function Finish(reason)
        if self.selling ~= sale then return end
        self.selling = nil
        local sold = ("Sold %d selected stack(s) for %s."):format(sale.sold, GetMoneyString(sale.value, true))
        if sale.skipped > 0 then sold = sold .. (" Skipped %d changed or locked stack(s)."):format(sale.skipped) end
        Notify(reason and (sold .. " " .. reason) or sold)
    end
    local function Next()
        if self.selling ~= sale then return end
        local row = reviewed[sale.index]
        if not row then Finish(); return end
        if sale.interrupted or not self:CanSell() then
            Finish("Sale stopped. Open the merchant tab to review any remaining stacks.")
            return
        end
        local item = self:SellableStacks()[row.guid]
        sale.index = sale.index + 1
        if not item or item.info.isLocked or item.value ~= row.value or item.count ~= row.count or item.key ~= row.key then
            sale.skipped = sale.skipped + 1
            C_Timer.After(0, Next)
            return
        end
        -- Retire before submitting the sale. If the client doesn't confirm it,
        -- a later click must never attempt that stack again automatically.
        Ledger().stacks[item.guid] = nil
        local before, start = GetMoney(), GetTime()
        C_Container.UseContainerItem(item.bag, item.slot)
        local function WaitForSale()
            if self.selling ~= sale then return end
            local remaining = BagItems(item.info.itemID)[item.guid]
            if not remaining and GetMoney() - before == row.value then
                sale.sold, sale.value = sale.sold + 1, sale.value + row.value
                C_Timer.After(0.10, Next)
            elseif GetTime() - start >= 3 or sale.interrupted or not self:CanSell() then
                Finish("The last sale couldn’t be confirmed. Check your bags and buyback tab.")
            else
                C_Timer.After(0.10, WaitForSale)
            end
        end
        C_Timer.After(0.10, WaitForSale)
    end
    Next()
    return true
end

for _, event in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE", "MAIL_SUCCESS", "MAIL_FAILED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "BAG_UPDATE_DELAYED", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "GET_ITEM_INFO_RECEIVED", "CURSOR_UPDATE" }) do
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, itemID)
    if not Addon.character then return end
    local mailInteraction = itemID and Enum.PlayerInteractionType and itemID == Enum.PlayerInteractionType.MailInfo
    if event == "PLAYER_LOGIN" then
        Flips:PruneReceipts()
        if hooksecurefunc and TakeInboxItem then hooksecurefunc("TakeInboxItem", ObserveTake) end
        if hooksecurefunc and AutoLootMailItem then hooksecurefunc("AutoLootMailItem", ObserveTake) end
        if EventRegistry then
            EventRegistry:RegisterCallback("MerchantFrame.MerchantTabShow", function() Notify() end, Flips)
            EventRegistry:RegisterCallback("MerchantFrame.BuyBackTabShow", function() Notify() end, Flips)
        end
    elseif event == "MAIL_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and mailInteraction) then
        Flips.mailOpen = true
    elseif event == "MAIL_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and mailInteraction) then
        Flips.mailOpen = false
        for _, take in pairs(Flips.pending) do
            if not take.mailVerified then AbortTake(take) end
        end
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_SUCCESS" then
        CheckTakes()
    elseif event == "MAIL_FAILED" then
        if itemID and Flips.pending[itemID] then AbortTake(Flips.pending[itemID]) end
    elseif event == "MERCHANT_SHOW" then
        Flips.merchantOpen = true
        Notify()
        C_Timer.After(0, function() if Flips.merchantOpen then Notify() end end)
    elseif event == "MERCHANT_CLOSED" then
        Flips.merchantOpen = false
        if Flips.selling then Flips.selling.interrupted = true end
        Notify()
    elseif event == "BAG_UPDATE_DELAYED" then
        CheckTakes()
        if next(Ledger().stacks) then Flips:SellableStacks() end
        if Flips.merchantOpen then Notify() end
    elseif Flips.merchantOpen and (event == "MERCHANT_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" or event == "CURSOR_UPDATE") then
        Notify()
    end
end)
