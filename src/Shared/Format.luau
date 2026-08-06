--!strict
-- Format.luau
-- Suffix-ladder number formatting, precision-safe to 1e300 (SRS NFR-4).
-- Handles NaN, inf, and negative inputs without producing garbage text.

local Shared = script.Parent
local ForgeMath = require(Shared:WaitForChild("ForgeMath"))

local Format = {}

local SUFFIXES = {
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
	"Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
	"Uvg", "Dvg", "Tvg", "Qavg", "Qivg", "Sxvg", "Spvg", "Ocvg", "Novg", "Tg",
	"Utg", "Dtg", "Ttg", "Qatg", "Qitg", "Sxtg", "Sptg", "Octg", "Notg", "Qd",
	"Uqd", "Dqd", "Tqd", "Qaqd", "Qiqd", "Sxqd", "Spqd", "Ocqd", "Noqd", "Qq",
}

function Format.formatNumber(n: number): string
	if not ForgeMath.isFinite(n) then
		if n ~= n then
			return "NaN"
		elseif n > 0 then
			return "Inf"
		else
			return "-Inf"
		end
	end

	if n == 0 then
		return "0"
	end

	local isNegative = n < 0
	local absN = math.abs(n)

	if absN < 1000 then
		local str = string.format("%.2f", absN)
		str = string.gsub(str, "%.00$", "")
		str = string.gsub(str, "(%..-)0+$", "%1")
		return if isNegative then "-" .. str else str
	end

	local exp = math.floor(math.log10(absN))
	local tier = math.floor(exp / 3)
	local index = tier + 1

	if index <= #SUFFIXES then
		local scaled = absN / (10 ^ (tier * 3))
		local suffix = SUFFIXES[index]
		local str = string.format("%.2f%s", scaled, suffix)
		return if isNegative then "-" .. str else str
	else
		-- Scientific notation fallback for numbers above the suffix table
		local mantissa = absN / (10 ^ exp)
		local str = string.format("%.2fe%d", mantissa, exp)
		return if isNegative then "-" .. str else str
	end
end

return Format
