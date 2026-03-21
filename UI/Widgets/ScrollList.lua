------------------------------------------------------------------------
-- Vault of Truths - UI/Widgets/ScrollList.lua
-- Reusable scrollable list with row recycling
------------------------------------------------------------------------
local ADDON_NAME, GF = ...

if not GF.UI then GF.UI = {} end
if not GF.UI.Widgets then GF.UI.Widgets = {} end

--- Create a scrollable list widget
---@param parent Frame Parent frame
---@param rowHeight number Height of each row
---@param createRow function(index, parent) -> Frame Row factory
---@param updateRow function(row, data, index) Row update callback
---@return table ScrollList widget
function GF.UI.Widgets:CreateScrollList(parent, rowHeight, createRow, updateRow)
    local widget = {}
    widget.data = {}
    widget.rowHeight = rowHeight or 24

    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    widget.frame = container

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0) -- Room for scrollbar

    -- Content frame (child of scroll frame)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(content)
    widget.content = content

    -- Row pool
    local rows = {}
    widget.rows = rows

    --- Set data and refresh the list
    ---@param data table Array of data items
    function widget:SetData(data)
        self.data = data or {}
        self:Refresh()
    end

    --- Refresh the display
    function widget:Refresh()
        local data = self.data
        local numRows = #data

        -- Resize content frame
        content:SetHeight(math.max(numRows * self.rowHeight, 1))

        -- Create/reuse rows as needed
        for i = 1, numRows do
            if not rows[i] then
                rows[i] = createRow(i, content)
                rows[i]:SetHeight(self.rowHeight)
                rows[i]:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
                rows[i]:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            end
            rows[i]:Show()
            updateRow(rows[i], data[i], i)
        end

        -- Hide excess rows
        for i = numRows + 1, #rows do
            rows[i]:Hide()
        end
    end

    --- Get the container frame
    function widget:GetFrame()
        return container
    end

    -- Update content width when container resizes
    container:SetScript("OnSizeChanged", function(self, w, h)
        content:SetWidth(w - 26)
        widget:Refresh()
    end)

    return widget
end
