local field = require("field")
local helper = require("helper")
local fh = require("field_helper")


local function decode_default( ba, len )

	bi.log("decode_default")
    local f_pcap = field.list("BinInspector", len, function(self, ba)
    end)

    return f_pcap
end

local function clear()
end

local function build_summary()
end

local codec = {
--	authors = { {name="author1", mail="mail1"}, {name="author2", mail="mail2" } },
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "All files",
    file_ext = "*",
    decode = decode_default,
    clear = clear,
    build_summary = build_summary,
}

return codec
