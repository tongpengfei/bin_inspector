require("class")
local helper = require("helper")

local FieldType = {
    kBits   = "bits",
    kUbits  = "ubits",
    kUEbits = "uebits",

    kUint8 = "uint8",
    kUint16 = "uint16",
    kUint24 = "uint24",
    kUint32 = "uint32",
    kUint64 = "uint64",
    kInt8 = "int8",
    kInt16 = "int16",
    kInt24 = "int24",
    kInt32 = "int32",
    kInt64 = "int64",
    kFloat = "float",
    kDouble = "double",
    kString = "string",

    kBitArray = "bit_array", --fixed bit fields
    kBitList = "bit_list",   --dynamic bit fields array

    kArray = "array",        --fiexed byte fields
    kList = "list",          --dynamic byte fields array

    kCallback = "callback",  --custom read function
    kSelect = "select",      --select a field if cond is true
}

----------------------------------------------------------------
local field_t = class("field_t")
function field_t:ctor(type, len, name, cb_desc, cb_brief)
    self.type = type
    self.name = name

    self.len = len or 0
    self.value = nil
    self.children = nil

    self.offset = -1
    self.ba = nil

    self.cb_child_brief = nil
    self.cb_click = nil

	self.cb_context_menu = nil --right click self or parent, will show children's context menu
	self.cb_private_context_menu = nil --right click self item to show this context menu

	self.bg_color = nil --back ground color #FFFFFF
	self.fg_color = nil --font color

    if cb_brief then self.get_brief = cb_brief end
    if cb_desc then self.get_desc = cb_desc end
end

--handler(self, data, data_len)
function field_t:set_click( handler )
    self.cb_click = handler
end

--handler(self, menu)
function field_t:set_context_menu( handler )
    self.cb_context_menu = handler
end

--handler(self, menu)
function field_t:set_private_context_menu( handler )
    self.cb_private_context_menu = handler
end

function field_t:set_bg_color( c )
	self.bg_color = c
end

function field_t:set_fg_color( c )
	self.fg_color = c
end

--ba: byte_array
function field_t:read(ba)
    self.offset = ba:position()

    if nil == self.ba then
        self.ba = ba
    end

    if self.is_bits then
        local nbits = ba:bit_offset() + ba:bit_remain()
        self.offset = self.offset - math.floor(nbits/8)
        self.bit_offset = ba:bit_offset()
    end
end

function field_t:get_byte_offset()
    local v = self.offset
    if self.is_bits then
        v = v + math.floor(self.bit_offset/8)
    end
    return v
end

function field_t:get_byte_len()
    if self.is_bits then
        return math.ceil(self.len/8)
    end
    return self.len
end

function field_t:set_raw_data(data)
    local n = #data
    local ba = byte_stream(n)
    ba:set_data(data, n)
    self.ba = ba
end

function field_t:get_data()
    local s = self:get_byte_offset()
    local nbyte = self:get_byte_len()
    local data = self.ba:peek_bytes_from(s, nbyte)
    return data
end

local function setup_menu( field, menu )
    if field.cb_private_context_menu then
        field:cb_private_context_menu(menu)
    end
    if field.cb_context_menu then
        field:cb_context_menu(menu)
    end

    if field.selected_field then
        setup_menu( field.selected_field, menu )
    end

    if nil == field.children then return end
    for _, child in ipairs(field.children) do
        setup_menu(child, menu)
    end
end

local function setup_menu_save_bin( field, menu )
    if field:get_byte_len() <= 0 then return end

    menu:add_action("save bin", function()

        local fp = helper.ask_save(string.format("%s/%s.bin", bi.get_tmp_dir(), field.name))
        if nil == fp then return end

        local data = field:get_data()

        fp:write( data )
        fp:close()
    end)   
end

local g_dump_node = nil
function field_t:dump_range()
    if self.len <= 0 then
        return
    end

    local s = self:get_byte_offset()
    local e = s+self:get_byte_len()

    if g_dump_node ~= self.dump_node then
        local nbyte = self:get_byte_len()
        bi.dump_ba(self.ba)
        g_dump_node = self.dump_node
    end

    bi.dump_set_range(s, e)
    bi.show_status( string.format("range:[%d,%d) len:%d", s, e, e-s) )
end

function field_t:setup_context_menu( node, cb_hander )

	node:reg_handler_context_menu(function(menu)
		--bi.log(string.format("on lua context_menu %s", self.name))
        if nil == self.parent then
            --root ignore children menu
            return
        end

        if cb_hander then
            cb_hander(self, menu)
        end

        setup_menu_save_bin( self, menu )

        --setup children menu
        setup_menu(self, menu)
	end)
end

function field_t:build_tree()
--    bi.log(string.format("type:%s name:%s ", self.type, self.name))
--[[
    if self.len > 0 then
        bi.log(string.format("type:%s name:%s len:%d range:[%d,%d)", self.type, self.name, self.len, self.offset, self.offset+self.len))
    else
        bi.log(string.format("type:%s name:%s range:[%d,??)", self.type, self.name, self.offset, self.offset))
    end
--]]

    if self.get_desc and type(self.get_desc) ~= "function" then
        bi.message_box(string.format("field:%s %s self.get_desc need be function, get: %s", self.type, self.name, type(self.get_desc)))
        return
    end

    local desc = self:get_desc()
    if nil == desc then
        desc = string.format("ERROR: [%s] desc is nil", self.name)
        bi.log(desc)
    end
    local node = bi.create_tree_item( desc )
    if self.children then
        for _, v in ipairs(self.children) do
            local c = v:build_tree()
            node:addChild(c)
        end
    end

	if self.bg_color then
		node:set_bg_color( self.bg_color )
	end
	if self.fg_color then
		node:set_fg_color( self.fg_color )
	end

    node:reg_handler_click(function()
        if self.cb_click then
            self:cb_click()
        end

        self:dump_range()
    end)

    self:setup_context_menu( node )

    return node
end


----------------------------------------------------------------
local field_bit_base_t = class("field_bit_base_t", field_t)
function field_bit_base_t:ctor(type, name, nbit, cb_desc, cb_brief)
    nbit = nbit or 1
    field_t.ctor(self, type, nbit, name, cb_desc, cb_brief)

    self.is_bits = true
    self.is_fixed_bits = true
end

function field_bit_base_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_bits(self.len)
    return self.value
end

function field_bit_base_t:get_desc()
    return string.format("[%2d bits] %s: %d", self.len, self.name, self.value)
end

----------------------------------------------------------------
local field_bits_t = class("field_bits_t", field_bit_base_t)
function field_bits_t:ctor(name, nbit, cb_desc, cb_brief)
    field_bit_base_t.ctor(self, FieldType.kBits, name,nbit, cb_desc, cb_brief)
end

----------------------------------------------------------------
local field_ubits_t = class("field_ubits_t", field_bit_base_t)

function field_ubits_t:ctor(name, nbit, cb_desc, cb_brief)
    field_bit_base_t.ctor(self, FieldType.kUbits, name, nbit, cb_desc, cb_brief)
end

function field_ubits_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_ubits(self.len)
    return self.value
end

----------------------------------------------------------------
local field_uebits_t = class("field_uebits_t", field_bit_base_t)

function field_uebits_t:ctor(name, cb_desc, cb_brief)
    field_bit_base_t.ctor(self, FieldType.kUEbits, name, 0, cb_desc, cb_brief)
    self.is_fixed_bits = false
end

function field_uebits_t:read(ba)
    field_t.read(self, ba)
    self.value, self.len = ba:read_uebits()
    return self.value
end

----------------------------------------------------------------
local field_sebits_t = class("field_sebits_t", field_bit_base_t)

function field_sebits_t:ctor(name, cb_desc, cb_brief)
    field_bit_base_t.ctor(self, FieldType.kSEbits, name, 0, cb_desc, cb_brief)
    self.is_fixed_bits = false
end

function field_sebits_t:read(ba)
    field_t.read(self, ba)
    self.value, self.len = ba:read_sebits()
    return self.value
end

----------------------------------------------------------------
local field_string_t = class("field_string_t", field_t)
function field_string_t:ctor(name, len, cb_desc, cb_brief)
    field_t.ctor(self, FieldType.kString, len, name, cb_desc, cb_brief)
end
   
function field_string_t:read(ba, read_len)
    field_t.read(self, ba)
    if read_len == nil or read_len <= 0 then
        read_len = self.len
    end
    if read_len == nil or read_len <= 0 then
        read_len = ba:length()
    end

    if read_len < 32 then
        self.value = ba:read_bytes(read_len)
    else
        ba:skip_bytes(read_len)
        self.value = self.get_data
    end
    self.len = read_len
    return self.value
end

function field_string_t:get_str()
    local data = field_t.get_data(self)

    local pos = string.find(data, '\0')
    if nil ~= pos then
        local nbyte = self:get_byte_len()
        local nremove = pos - nbyte - 2
        data = data:sub(1, nremove)
    end

    return string.format("%s", data)
end
 
function field_string_t:get_desc()
    return string.format("%s: %d bytes", self.name, self.len) 
end

----------------------------------------------------------------
local field_number_t = class("field_number_t", field_t)
function field_number_t:ctor(type, len, name, swap_endian, cb_desc, cb_brief)
    field_t.ctor(self, type, len, name, cb_desc, cb_brief)

    self.swap_endian = (swap_endian == true)
end
   
function field_number_t:get_desc()
    return string.format("%s %s: %d", self.type, self.name, self.value) 
end

----------------------------------------------------------------
local field_uint8_t = class("field_uint8_t", field_number_t)
function field_uint8_t:ctor(name, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kUint8, 1, name, nil, cb_desc, cb_brief)
end

function field_uint8_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_uint8()
    return self.value
end

function field_uint8_t:get_desc()
    return string.format("%s %s: %u", self.type, self.name, self.value) 
end
    
----------------------------------------------------------------
local field_uint16_t = class("field_uint16_t", field_uint8_t)
function field_uint16_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kUint16, 2, name, swap_endian, cb_desc, cb_brief)
end

function field_uint16_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_uint16(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_uint24_t = class("field_uint24_t", field_uint8_t)
function field_uint24_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kUint24, 3, name, swap_endian, cb_desc, cb_brief)
end

function field_uint24_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_uint24(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_uint32_t = class("field_uint32_t", field_uint8_t)
function field_uint32_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kUint32, 4, name, swap_endian, cb_desc, cb_brief)
end

function field_uint32_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_uint32(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_uint64_t = class("field_uint64_t", field_uint8_t)
function field_uint64_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kUint64, 8, name, swap_endian, cb_desc, cb_brief)
end

function field_uint64_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_uint64(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_double_t = class("field_double_t", field_number_t)
function field_double_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kDouble, 8, name, swap_endian, cb_desc, cb_brief)
end

function field_double_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_double(self.swap_endian)
    return self.value
end

function field_double_t:get_desc()
    return string.format("%s %s: %.2f", self.type, self.name, self.value) 
end


----------------------------------------------------------------
local field_int8_t = class("field_int8_t", field_number_t)
function field_int8_t:ctor(name, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kInt8, 1, name, nil, cb_desc, cb_brief)
end

function field_int8_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_int8()
    return self.value
end

----------------------------------------------------------------
local field_int16_t = class("field_int16_t", field_number_t)
function field_int16_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kInt16, 2, name, swap_endian, cb_desc, cb_brief)
end

function field_int16_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_int16(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_int24_t = class("field_int24_t", field_number_t)
function field_int24_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kInt24, 3, name, swap_endian, cb_desc, cb_brief)
end

function field_int24_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_int24(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_int32_t = class("field_int32_t", field_number_t)
function field_int32_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kInt32, 4, name, swap_endian, cb_desc, cb_brief)
end

function field_int32_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_int32(self.swap_endian)
    return self.value
end

----------------------------------------------------------------
local field_int64_t = class("field_int64_t", field_number_t)
function field_int64_t:ctor(name, swap_endian, cb_desc, cb_brief)
    field_number_t.ctor(self, FieldType.kInt64, 8, name, swap_endian, cb_desc, cb_brief)
end

function field_int64_t:read(ba)
    field_t.read(self, ba)
    self.value = ba:read_int64(self.swap_endian)
    return self.value
end

function field_int64_t:get_desc()
    return string.format("%s %s: %d", self.type, self.name, self.value) 
end

----------------------------------------------------------------
local field_collection_t = class("field_collection_t", field_t)
function field_collection_t:ctor(type, name, len, children, cb_desc, cb_brief)
    field_t.ctor(self, type, len, name, cb_desc, cb_brief)
    self.children = children or {}
end

function field_collection_t:get_len()
    return self.len
end

function field_collection_t:get_desc()
    local child_brief = self:get_child_brief()
    if child_brief then
        return string.format("%s %slen:%d ", self.name, child_brief, self.len)
    end

    return string.format("%s len:%d", self.name, self.len)
end

function field_collection_t:get_child_brief()
    if nil == self.children then return nil end
    local brief = nil
    for _, v in ipairs(self.children) do
        if v.get_brief then
            brief = (brief or "") .. (v:get_brief() or "")
        end
    end

    return brief
end

----------------------------------------------------------------
local field_list_t = class("field_list_t", field_collection_t)
function field_list_t:ctor(name, len, cb_read, cb_desc, cb_brief)
    field_collection_t.ctor(self, FieldType.kList, name, len, children, cb_desc, cb_brief)
    self.cb_read = cb_read
end

function field_list_t:read(ba)
    field_t.read(self, ba)
    self.children = {}

--    self.ba = ba

    if self.cb_read then
        self:cb_read(ba)       
    end

    if self.len <= 0 then        
        for _, v in ipairs(self.children) do
            self.len = self.len + v.len
        end
    end

--    self.ba = nil
end

function field_list_t:append(field_child, ba)
    if not field_child then return nil end
    field_child.parent = self
    field_child:read(ba or self.ba)
    table.insert(self.children, field_child)
    return field_child
end

function field_list_t:append_list(children, ba)
    if not children then return nil end

    for _, v in ipairs(children) do
        self:append(v, ba)
    end
end


local field_array_t = class("field_array_t", field_collection_t)
function field_array_t:ctor(name, len, children, cb_desc, cb_brief)
    field_collection_t.ctor(self, FieldType.kArray, name, len, children, cb_desc, cb_brief)
end

function field_array_t:read(ba)
    field_t.read(self, ba)
    if nil == self.children then return end

    if self.len <= 0 then
        self.len = ba:length()
    end

    for _, v in ipairs(self.children) do
        v.parent = self
        v:read(ba)
    end
        
    return self.children
end

----------------------------------------------------------------
local field_bit_list_t = class("field_bit_list_t", field_collection_t)
function field_bit_list_t:ctor(name, len, cb_read, cb_desc, cb_brief)
    field_collection_t.ctor(self, FieldType.kBitList, name, len, children, cb_desc, cb_brief)
    self.cb_read = cb_read
end

function field_bit_list_t:read(ba)
    field_t.read(self, ba)
    if nil == self.children then return nil end
    if self.len > 0 then
        ba:to_bit_space(self.len)
    end

    local pos_byte = ba:position()
    local pos = ba:bit_offset()

    if self.cb_read then
        self:cb_read(ba)
    end

    local nbits = ba:bit_offset() - pos
    local nbyte = bi.bits2byte(nbits)
    if self.len == 0 then
        self.len = nbyte
    end
    self.total_bit = nbits

    local remain_bits = self.len*8 - nbits
    if remain_bits > 0 then
        ba:skip_bits(remain_bits)
    elseif remain_bits < 0 then
        local nread = math.ceil(nbits/8)
        local over = nread - self.len
        ba:back_pos(math.abs(over))
        bi.log_error(string.format("%s %s read over %d, byte_len:%d", self.type, self.name, over, self.len))
        ba:clear_bit_status()
    end

    return self.children
end

function field_bit_list_t:append(bit_field)
    if not bit_field then return end

    bit_field.parent = self
	bit_field:read(self.ba)
    table.insert(self.children, bit_field)
    return bit_field
end

function field_bit_list_t:append_list(bit_fields)
    if nil == bit_fields then return end

    for _, v in ipairs(bit_fields) do
        self:append(v)
    end
end

function field_bit_list_t:get_desc()
    local child_brief = self:get_child_brief()
    if child_brief then
        return string.format("%s [%d bytes %d bits] %s", self.name, self.len, self.total_bit, child_brief)
    end

    return string.format("%s [%d bytes %d bits]", self.name, self.len, self.total_bit)
end

function field_bit_list_t:get_child_brief()
    if nil == self.children then return nil end
    if self.cb_child_brief then return self:cb_child_brief() end

    local brief = nil
    for _, v in ipairs(self.children) do
        if v.get_brief then
            brief = (brief or "") .. v:get_brief()
        end
    end

    return brief
end

----------------------------------------------------------------
local field_bit_array_t = class("field_bit_array_t", field_bit_list_t)
function field_bit_array_t:ctor(name, children, cb_desc, cb_brief)
    field_collection_t.ctor(self, FieldType.kBitArray, name, nil, children, cb_desc, cb_brief)

    for _, v in ipairs(self.children) do
        v.parent = self
    end
end

function field_bit_array_t:read(ba)
    field_t.read(self, ba)

    local pos = ba:bit_offset()

    for _, v in ipairs(self.children) do
        v:read(ba)
    end

    self.total_bit = ba:bit_offset() - pos
    self.len = bi.bits2byte(self.total_bit)

    return self.children
end

----------------------------------------------------------------
local field_callback_t = class("field_callback_t", field_t)
function field_callback_t:ctor(name, cb_read, cb_desc, cb_brief)
    field_t.ctor(self, FieldType.kCallback, 0, name, cb_desc, cb_brief)
    self.cb_read = cb_read
end
   
function field_callback_t:get_desc()
    return string.format("%s: %s", self.name, tostring(self.value)) 
end

function field_callback_t:read(ba)
    field_t.read(self, ba)
    if self.cb_read then
        self.value, self.len = self:cb_read(ba)
        if self.len <= 0 then
            error(string.format("field_callback_t [%s %s] cb_read should return [value, len]", self.type, self.name))
        end
    end
    return self.value
end

----------------------------------------------------------------
--[[
    cb_selector = function() if xxx == 1 then return f end end
--]]
local field_select_t = class("field_select_t", field_t)
function field_select_t:ctor(name, len, cb_selector, cb_desc, cb_brief)
    field_t.ctor(self, FieldType.kSelect, len, name, cb_desc, cb_brief)
    self.cb_selector = cb_selector

    self.selected_field = nil
end
   
function field_select_t:get_desc()
    if nil == self.selected_field then return string.format("%s:??", self.name) end
    return self.selected_field:get_desc()
end

function field_select_t:get_brief()
    if nil == self.selected_field then return string.format("%s:??", self.name) end
    if self.selected_field.get_brief then return self.selected_field:get_brief() end
    return ""
end

function field_select_t:read(ba)
    local f = nil
    if self.cb_selector then
        f = self:cb_selector(ba)
        if f then
            self.selected_field = f
            f.len = self.len
        end
    end

    --default
    if nil == f then
        f = field_string_t.new(self.name, self.len, self.cb_desc, self.cb_brief)
    end

    f.parent = self.parent
    self.value = f:read(ba)
    self.offset = f.offset
    if self.len == 0 then
        self.len = f.len
    end

    self.selected_field = f
    return self.value
end

function field_select_t:build_tree()
    if self.selected_field then
        return self.selected_field:build_tree()
    end
end

local field = {
    bits = field_bits_t.new,
    ubits = field_ubits_t.new,
    uebits = field_uebits_t.new,
    sebits = field_sebits_t.new,

    uint8 = field_uint8_t.new,
    uint16 = field_uint16_t.new,
    uint24 = field_uint24_t.new,
    uint32 = field_uint32_t.new,
    uint64 = field_uint64_t.new,

    int8 = field_int8_t.new,
    int16 = field_int16_t.new,
    int24 = field_int24_t.new,
    int32 = field_int32_t.new,
    int64 = field_int64_t.new,

    double = field_double_t.new,
    string = field_string_t.new,
    
    list = field_list_t.new,
    array = field_array_t.new,

    bit_list = field_bit_list_t.new,
    bit_array = field_bit_array_t.new,

    callback = field_callback_t.new,
    select = field_select_t.new,
}

return field
