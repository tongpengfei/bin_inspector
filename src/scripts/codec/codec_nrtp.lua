local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

--[[
    file format:
        size: 4 bytes
        rtp_hdr: 12 bytes
        data: size - 12
--]]

local max_len = 0

local function decode_nrtp( ba, len )

	bi.log("decode_nrtp")

    local mk_desc = function(index)
        local cb = function(self)
            return string.format("[%d] len %d", index, self.value)
        end
        return cb
    end

    local codec_rtp = helper.get_codec("rtp")

    local swap_endian = false
    local f_pcap = field.list("nrtp", len, function(self, ba)
        local pos_start = ba:position()

        local index = 0
        while true do
            local remain = len - (ba:position() - pos_start)
            if remain <= 0 then break end

            local f_frame = field.list(string.format("[%d] rtp", index), nil, function(self, ba)
                local f_len = self:append(field.uint32("len", swap_endian, nil, fh.mkbrief("data_len")))
                if f_len.value > max_len then
                    max_len = f_len.value
                end

                local f_rtp_hdr = self:append(codec_rtp.field_rtp_hdr())

                self:append(field.string("data", f_len.value-f_rtp_hdr.len))
            end)
            self:append( f_frame )

            index = index + 1
        end
    end)

    return f_pcap
end

local function clear()
end

local function build_summary()

    bi.append_summary("max_len", max_len)
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "nrtp",
    file_ext = "nrtp",
    decode = decode_nrtp,
    clear = clear,
    build_summary = build_summary,
}

return codec
