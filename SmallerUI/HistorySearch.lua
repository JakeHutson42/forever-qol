local _, Addon = ...

function Addon:HistoryTerms(query)
    local terms = {}
    for term in query:lower():gmatch("%S+") do terms[#terms + 1] = term end
    return terms
end

function Addon:HistoryMatches(text, terms)
    for _, term in ipairs(terms) do
        if not text:find(term, 1, true) then return false end
    end
    return true
end

function Addon:CancelHistorySearch(driver)
    driver:SetScript("OnUpdate", nil)
    driver:Hide()
end

function Addon:RunHistorySearch(driver, nextRecord, complete)
    local function Step()
        local deadline = debugprofilestop and debugprofilestop() + 3
        for index = 1, 400 do
            if not nextRecord() then
                self:CancelHistorySearch(driver)
                complete()
                return
            end
            if deadline and index % 16 == 0 and debugprofilestop() >= deadline then return end
        end
    end
    driver:SetScript("OnUpdate", Step)
    driver:Show()
    Step()
end
