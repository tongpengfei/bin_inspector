local field = require("field")

--[[
<: sets little endian
>: sets big endian
=: sets native endian
![n]: sets maximum alignment to n (default is native alignment)
b: a signed byte (char)
B: an unsigned byte (char)
h: a signed short (native size)
H: an unsigned short (native size)
l: a signed long (native size)
L: an unsigned long (native size)
j: a lua_Integer
J: a lua_Unsigned
T: a size_t (native size)
i[n]: a signed int with n bytes (default is native size)
I[n]: an unsigned int with n bytes (default is native size)
f: a float (native size)
d: a double (native size)
n: a lua_Number
cn: a fixed-sized string with n bytes
z: a zero-terminated string
s[n]: a string preceded by its length coded as an unsigned integer with n bytes (default is a size_t)
x: one byte of padding
Xop: an empty item that aligns according to option op (which is otherwise ignored)
' ': (empty space) ignored
--]]
local function test_field()
    local mt = bi.main_tree()

    local buf = byte_stream(512)

	local values = {
        0x12, 0x1234, 0x2BCDEF, 0x01234567, 0x0123456789ABCDEF,
        0x21, 0x3412, 0xFEDCBA, 0x76543210, 0xABCDEF0123456789,
		"hello"
	}

    local data = string.pack("<bhi3ii8BHI3II8s2",
		table.unpack(values)
    )

    buf:set_data(data, #data)
	buf:append(data, #data)

    bi.log( "buf len:" .. buf:length() )

    local function test_parse_data( buf, swap_endian )
		local f_i8 = field.int8("int8")
        local f_i16 = field.int16("int16", swap_endian )
        local f_i24 = field.int24("int24", swap_endian )
        local f_i32 = field.int32("int32", swap_endian )
        local f_i64 = field.int64("int64", swap_endian )
		local f_u8 = field.uint8("uint8")
        local f_u16 = field.uint16("uint16", swap_endian )
        local f_u24 = field.uint24("uint24", swap_endian )
        local f_u32 = field.uint32("uint32", swap_endian )
        local f_u64 = field.uint64("uint64", swap_endian )
		local f_str_len = field.int16("name len")
	    local f_str = field.string("name", f_str_len)

	    bi.log(string.format("i8:  0x%X => 0x%X", values[1], f_i8:read(buf) ))
	    bi.log(string.format("i16: 0x%X => 0x%X", values[2], f_i16:read(buf) ))
	    bi.log(string.format("i24: 0x%X => 0x%X", values[3], f_i24:read(buf) ))
	    bi.log(string.format("i32: 0x%X => 0x%X", values[4], f_i32:read(buf) ))
	    bi.log(string.format("i64: 0x%X => 0x%X", values[5], f_i64:read(buf) ))

	    bi.log(string.format("u8:  0x%X => 0x%X", values[6], f_u8:read(buf) ))
	    bi.log(string.format("u16: 0x%X => 0x%X", values[7], f_u16:read(buf) ))
	    bi.log(string.format("u24: 0x%X => 0x%X", values[8], f_u24:read(buf) ))
	    bi.log(string.format("u32: 0x%X => 0x%X", values[9], f_u32:read(buf) ))
	    bi.log(string.format("u64: 0x%X => 0x%X", values[10], f_u64:read(buf) ))
	
		local str_len = f_str_len:read(buf)
	    bi.log("str len:" .. str_len)
	    bi.log("str:" .. f_str:read(buf, str_len) )
	end

	test_parse_data( buf, false )
    test_parse_data( buf, true )
end

local function test_field_bit_array()
	local data = string.pack("B", 0x67)

	local bb = byte_stream(10)
	bb:set_data(data, #data)

	local f_bit_array = field.bit_array("0x67", {
    				field.ubits("nal_unit_type", 5),
    				field.ubits("nal_reference_idc", 2),
    				field.ubits("forbidden_bit", 1),
                })

	f_bit_array:read(bb)

	bi.log(f_bit_array:get_desc())
end

test_field_bit_array()
test_field()
