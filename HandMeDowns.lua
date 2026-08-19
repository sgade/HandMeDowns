--[[----------------------------------------------------------------------------

  HandMeDowns/HandMeDowns.lua
  Recommends twinks for warbound gear

  Copyright (c) 2025 Sören Gade

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.

----------------------------------------------------------------------------]]--

-- *** Bootstrap
--
-- This file only creates the addon object and the small set of generic
-- helpers shared across every other file. WoW addon files are separate Lua
-- chunks - `local`s never cross files - so anything that needs to be shared
-- lives as a namespaced field on this table instead (HandMeDowns.Data,
-- HandMeDowns.Characters, HandMeDowns.Pawn, HandMeDowns.Assignment). See
-- HandMeDowns.toc for load order: this file must load first.

HandMeDowns = LibStub("AceAddon-3.0"):NewAddon("HandMeDowns", "AceConsole-3.0")

HandMeDowns.Util = {}

function HandMeDowns.Util.arrayContains(array, element)
    for _, value in ipairs(array) do
        if value == element then
            return true
        end
    end
    return false
end

function HandMeDowns.Util.clearTable(table)
    for key in pairs(table) do
        table[key] = nil
    end
end
