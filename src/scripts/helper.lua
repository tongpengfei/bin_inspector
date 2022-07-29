require("class")
local mri = require("MemoryReferenceInfo")
mri.m_cConfig.m_bAllMemoryRefFileAddTime = false

local function dump_memory(path, name, obj)
    assert( nil ~= path )

    collectgarbage("collect")
    if nil == name then
        mri.m_cMethods.DumpMemorySnapshot(path, nil, -1)
        return
    end
    assert( nil ~= obj )

    mri.m_cMethods.DumpMemorySnapshot(path, nil, -1, name, obj)
end

-- /a/b/c.txt => c.txt
local function get_file_name(file)
    return file:match("^.+/(.+)$")
end

-- /a/b/c/abc.txt => /a/b/c/abc
local function get_base_name(str)
    return str:match("(.+)%..+")
end

local function get_file_ext(str)
    local ext = str:match("^.+(%..+)$")
    return ext
end

local function ms2time(v, timescale)
    timescale = timescale or 1000
    local msv = math.floor(v / timescale * 1000)
    local ms = msv % 1000
    local sec = math.floor(msv / 1000)
    local s = math.floor(sec % 60)
    local m = math.floor(sec / 60 % 60)
    local h = math.floor(sec / 60 / 60 % 24)
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function ms2date(v)
    local ms = v % 1000
    local sday = os.date("%Y-%m-%d %H:%M:%S", math.floor(v/1000))
    return string.format("%s.%03d", sday, ms)
end


local K = 1024
local M = K * K
local G = K * M
local function size_format(v)
    if v < K then
        return string.format("%d", v)
    end
    if v < M then
        return string.format("%.3fKB", v/K)
    end
    if v < G then
        return string.format("%.3fMB", v/M)
    end
    return string.format("%.3fGB", v/G)
end

local function n2ip( n )
    local a = (n >> 24) & 0xFF
    local b = (n >> 16) & 0xFF
    local c = (n >> 8) & 0xFF
    local d = n & 0xFF

    return string.format("%d.%d.%d.%d", a, b, c, d)
end

local function split(str, sep)
    local sep, fields = sep or "\t", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end

local function read_file(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

local function ask_save(name)
    local file = bi.save_as(name)
    if nil == file or "" == file then return nil end

    local fp = io.open(file, "wb")
    if nil == fp then 
        bi.message_box(string.format("cant save file to:%s", file))
        return nil
    end
    return fp
end

local dict_codec = {}

local function register_codec(script, codec)
    assert( nil ~= codec )
    assert( nil ~= codec.file_ext ) --"ext0 ext1"
    assert( nil ~= codec.decode )

    --"ext0 ext1" => (*.ext0 *.ext1)"
    local desc = codec.file_desc
    local arr_ext = split(codec.file_ext, " ")
    local ext = nil
    for _, e in ipairs(arr_ext) do
        if ext == nil then
            ext = string.format(" *.%s", e)
            desc = desc or string.format("%s file", string.upper(e))
        else
            ext = ext .. string.format(" *.%s", e)
        end
        
        if nil ~= dict_codec[e] then
            --error(string.format("register_codec repeated: %s %s", codec.file_ext, e))
            bi.log(string.format("!!warning!! register_codec repeated, skip this one: %s.lua [%s] %s", script, codec.file_ext, e))
            return -1
        end

        dict_codec[e] = codec
    end

    if ext ~= " *.*" then
        bi.reg_supported_file_ext(string.format("%s (%s)", desc, ext))
    end

    bi.log(string.format("register codec %s.lua [%s]", script, codec.file_ext))
    return 0
end

local function get_codec(ext)
	local def = dict_codec['*']
    if nil == ext then
		return def
	end

    local codec = dict_codec[ext]
    if nil == codec then
        return def
        --error(string.format("cant find codec with ext: [%s]", ext))
    end

    return codec
end

local function main_list_context_menu(field, menu)

    local mlist = bi.main_list()
    local ncount = mlist:selected_count()
    if ncount <= 1 then return end

    menu:add_action("save selected bin", function()

        local file = bi.save_as("%s/selected.bin", bi.get_tmp_dir())
        if nil == file or "" == file then return nil end

        mlist:save_selected(file)
    end)   

end

local function build_main_list(field)
    local mlist = bi.main_list()

    local fields = nil
    if nil ~= field.children and #field.children > 0 then
        fields = field.children
    else
        fields = { field }
    end

    for i, f in ipairs(fields) do
        local node = mlist:append( f:get_desc() )

        f.dump_node = f

        local s = f:get_byte_offset()
        local n = f:get_byte_len()
        node:set_byte_stream( f.ba, s, n )

		if nil ~= f.fg_color then
			node:set_fg_color( f.fg_color )
		end
		if nil ~= f.bg_color then
			node:set_bg_color( f.bg_color )
		end

        node:reg_handler_click(function()

            if f.cb_click then
                f:cb_click()
            end

            f:dump_range()

            local mt = bi.main_tree()
            mt:clear()

            if nil ~= f.children and #f.children > 0 then
                for j, ft in ipairs(f.children) do
                    local node_tree = ft:build_tree()
                    mt:addChild(node_tree)
                end
                --node:setExpanded(true)
            end
        end)

        f:setup_context_menu(node, main_list_context_menu)
    end
end

local function build_authors(codec)
    local tw = bi.create_summary_table("Authors")
    local tw_hdr = { "name", "mail" }
    local tw_ncol = #tw_hdr
    tw:set_column_count(tw_ncol)

    for i=1, tw_ncol do
        tw:set_header(i-1, tw_hdr[i] )
    end

	if not codec.authors then return end

	for _, author in ipairs(codec.authors) do
		local name = author.name or ""
		local mail = author.mail or ""

		if name ~= "" or mail ~= "" then
			tw:append_empty_row()

			tw:set_last_row_column( 0, name )
			tw:set_last_row_column( 1, mail )
		end
	end
end

local function do_decode_file(file)
    local ext = get_file_ext(file)
    if nil ~= ext then
	    local len = #ext
	    ext = string.sub( ext, -(len-1) )
	end

    bi.clear()
	bi.clear_bmp()

    for k, codec in pairs(dict_codec) do
        if codec.clear then
            codec.clear()
        end
    end

    local codec = get_codec(ext)
    if nil == codec then return -1 end
	local data = read_file(file)

    if nil == data then
        error(string.format("cant read file [%s]", file))
        return -1
    end

    local tm_start = bi.now_ms()

    local fsize = #data
    bi.append_summary("size", string.format("%d (%s)", fsize, size_format(fsize) ))

    if fsize <= 0 then
        return
    end

    local ba = byte_stream(fsize)
    ba:set_data(data, fsize)

    bi.set_progress_max(fsize)

	local args = {
		fname=file,
	}
    local field = codec.decode( ba, fsize, args )
    if nil == field then
        error(string.format("decode_data field == nil, file:[%s]", file))
        return -1
    end

    field:read(ba)

    build_main_list(field)

    if fsize > 0 and codec.build_summary then
        codec.build_summary()
    end

	--build author
	build_authors(codec)

    local tm_end = bi.now_ms()
    local elapse = tm_end - tm_start
    bi.log(string.format("decode cost %dms, %s", elapse, file))
    bi.show_status(string.format("decode cost %dms (%s) %s", elapse, ms2time(elapse), file))

--[[
    local node = field:build_tree()
    local mt = bi.main_tree()
    mt:addChild(node)
    node:setExpanded(true)
--]]

    bi.adjust_table_header_width()

    return 0
end

local function decode_file(file)
    do_decode_file(file)
    collectgarbage("collect")

--    dump_memory(string.format("%s", bi.get_tmp_dir()))
    return 0
end

local function decode_data(ext, ba, len)
    local codec = get_codec(ext)
    if nil == codec then return -1 end

    local field = codec.decode( ba, len )
    if nil == field then
        error(string.format("decode_data field == nil, ext:[%s]", ext))
    end
    return field
end

local function dump_find_all(str, len)
	if len >= 4 then
		bi.log(string.format("dump_find_all %d 0x%02X 0x%02X 0x%02X 0x%02X", len, str:byte(1), str:byte(2), str:byte(3), str:byte(4)))
	else
		bi.log(string.format("dump_find_all %d ", len))
	end

    local wlist = bi.find_result_widget()
	wlist:clear()
	bi.show_find_result()

	local pos = 0
	local index = 0
	while pos ~= -1 do

		pos = bi.find_next(pos, str, len)
		if pos == -1 then break end

--		bi.log(string.format("find in pos %d", pos))
		local node = wlist:append( string.format("[%d] %d", index, pos) )

		local s = pos
		local e = pos + len

        node:reg_handler_click(function()
		    bi.dump_set_range(s, e)
		    bi.show_status( string.format("range:[%d,%d) len:%d", s, e, e-s) )
		end)

		index = index + 1
		pos = pos + len
	end
end

local function load_codec_dir(path)
	bi.log(string.format("load_codec from %s", path))

    local files = list_dir(path)
    if nil == files then
        error(string.format("load_codec list_dir returns nil, path:%s", path))
        return -1
    end
    
    for _, file in ipairs(files) do
        local ext = get_file_ext(file)
        if ext == ".lua" then
            local fname = get_base_name(file)
            local codec = require(fname)
            register_codec( fname, codec )
        end
    end
end

local function load_private_scripts_dir(path)
    local files = list_dir(path)
    if nil == files then
        error(string.format("load_private_scripts_dir list_dir returns nil, path:%s", path))
        return -1
    end
    
    for _, file in ipairs(files) do
        local ext = get_file_ext(file)
        if ext == ".lua" then
            local fname = get_base_name(file)
            require(fname)
        end
    end
end

local function init()

	bi.log(string.format("version: %s", bi.version()))

    bi.reg_handler_decode_data( decode_data )
    bi.reg_handler_decode_file( decode_file )

	bi.reg_handler_dump_find_all( dump_find_all )

    local res_path = bi.get_res_path()

    load_private_scripts_dir(string.format("%s", bi.get_private_scripts_path()))

    load_codec_dir(string.format("%s", bi.get_private_codec_path()))
    load_codec_dir(string.format("%s/scripts/codec", res_path))
end

local t = {
    init = init,

    ms2time = ms2time,
    ms2date = ms2date,

	get_base_name = get_base_name,
	get_file_ext = get_file_ext,
	split = split,

    size_format = size_format,
    n2ip = n2ip,

    read_file = read_file,
    ask_save = ask_save,

    get_codec = get_codec,

    decode_file = decode_file,
    decode_data = decode_data,
}

return t
