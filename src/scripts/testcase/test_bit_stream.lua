local function test_bit_stream(bytes, nbits)

	local data = nil

    for _, v in ipairs(bytes) do
		data = (data or "") .. string.pack("<B", v)
	end

	local ba = byte_stream(#data)

	ba:set_data(data, #data)
	bi.log("bit stream length " .. ba:length())

	local len = ba:length()
	while len > nbits do

		local v = ba:read_ubits(nbits)

		bi.log(string.format("0x%X", v))
		len = ba:length()
	end
end

local function test_uebits()

--    local data = string.pack("<B", 0x1); --100 1
    local data = string.pack("<B", 0x5);   --101 2

    local ba = byte_stream(#data)
    ba:set_data(data, #data)
--    local v0 = ba:read_ubits(5)
--    bi.log(string.format("test_uebits v0:%d", v0))
    local v, nbits = ba:read_uebits()
    bi.log(string.format("test_uebits 0x4 => %u, nbits:%d", v, nbits))
end


local tmp_data = {
      0x12, 0x34, 0x56, 0x78, 0xAB, 0xCD, 0xEF
}

local nbits = 4
test_bit_stream(tmp_data, nbits)

local nbits = 2
--test_bit_stream(tmp_data, nbits)

test_uebits()
