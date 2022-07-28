
local function test_byte_stream()
    local bb = byte_stream(0)
    local str = "hello"
    local len = #str
    bb:set_data("hello", len)

    local a = bb:read_uint8()
    bi.log("read_uint8:" .. string.char(a))

    local c = bb:read_bytes(2)
    local c0 = c:sub(1, 2)
    bi.log("read_bytes c:" .. c .. " " .. c0)
    bi.log( string.char(c:byte(1)) .. "=" .. c:byte(1) )
    bi.log( string.char(c:byte(2)) .. "=" .. c:byte(2) )


    bi.log( string.char(str:byte(1)) .. "=" .. str:byte(1) )
    bi.log( string.char(str:byte(2)) .. "=" .. str:byte(2) )


    local ba = byte_stream(0)
    local data = string.pack("<I4I1", 0x12345678, 0xAB)
    ba:set_data( data, #data )
    local n = ba:read_uint32(false)
    bi.log(string.format("read_uint32 0x%X", n))

    local bit = ba:read_ubits(1)
    bi.log(string.format("read_ubits(1) 0x%X", bit))

    local bit2 = ba:read_ubits(2)
    bi.log(string.format("read_ubits(2) 0x%X", bit2))

    local bit3 = ba:read_ubits(3)
    bi.log(string.format("read_ubits(3) 0x%X", bit3))

    local bit4 = ba:read_ubits(1)
    bi.log(string.format("read_ubits(1) 0x%X", bit4))
end

test_byte_stream()
