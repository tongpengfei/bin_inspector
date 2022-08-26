local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

local OGG_HDR_TYPE = {
	CONTNUATION = 1,
	FIRST = 2,
	LAST = 4,
}

local OGG_HDR_TYPE_STR = {
	[1] = "CONTNUATION",
	[2] = "FIRST",
	[4] = "LAST",
}

local ogg_t = class("ogg_t")
function ogg_t:ctor()
	self.fsize = 0
	self.version = 0
	self.channel = 0
	self.pre_skip = 0
	self.sample_rate = 0
	self.sample_count = 0
	self.bitrate = 0
	self.vendor = nil
	self.comments = {}
	self.duration = 0
	self.page_count = 0
end

local g_ogg = nil

local function field_vorbis_header1(len)
	local f = field.list("vorbis_header1", len, function(self, ba)
		local pos = ba:position()

		self:append( field.uint8("packet_type") )
		self:append( field.string("tag", 6, fh.str_desc, fh.str_brief_v) )
		local f_ver = self:append( field.uint32("version", false, nil, fh.mkbrief("V")) )
		local f_ch = self:append( field.uint8("channel", nil, fh.mkbrief("CH")) )
		local f_sample_rate = self:append( field.uint32("sample_rate", false, nil, fh.mkbrief_v("")) )
		local f_bitrate = self:append( field.uint32("bitrate", false, nil, fh.mkbrief("BITRATE")) )
		self:append( field.uint8("blocksize", nil, fh.mkbrief("BLOCKSIZE")) )
		self:append( field.uint8("framing_flag", nil, fh.mkbrief("FRAMING_FLAG")) )

		local remain = len - (ba:position() - pos)
		if remain > 0 then
			self:append(field.string("unknown", remain))
		end

		g_ogg.version = f_ver.value
		g_ogg.channel = f_ch.value
		g_ogg.sample_rate = f_sample_rate.value
		--g_ogg.bitrate


	end, nil, fh.child_brief)
	return f
end

local function field_vorbis_header3(len)
	local f = field.list("vorbis_header3", len, function(self, ba)
		local pos = ba:position()

		self:append( field.uint8("packet_type") )
		self:append( field.string("tag", 6, fh.str_desc, fh.str_brief_v) )

		local f_vendor_len = self:append( field.uint32("vendor_len") )
		local f_vendor = self:append( field.string("vendor", f_vendor_len.value, fh.str_desc) )

		g_ogg.vendor = f_vendor:get_data()

		local f_ncomments = self:append( field.uint32("ncomments") )
		for i=0, f_ncomments.value-1 do
			self:append( field.list(string.format("comment[%d]", i), nil, function(self, ba)
				local f_comment_len = self:append( field.uint32("size") )
				if f_comment_len.value > 0 then
					local f_comment = self:append(field.string("comment", f_comment_len.value, fh.str_desc, fh.str_brief_v))

					table.insert(g_ogg.comments, f_comment:get_data())
				end
			end))
		end

		local remain = len - (ba:position() - pos)
		if remain > 0 then
			self:append(field.string("unknown", remain))
		end
	end, nil, fh.child_brief)
	return f
end


local function field_page(index)

	local is_header = true
	local f_page = field.list(string.format("page[%d]", index), nil, function(self, ba)
		local f_sync = self:append( field.string("sync", 4, fh.str_desc, fh.str_brief_v) )
		if f_sync:get_data() ~= "OggS" then
			--error format 
			return
		end

		self:append( field.uint8("version", nil, fh.mkbrief("V")) )
		local f_header_type = self:append( field.uint8("header_type", nil, fh.mkbrief("T")) )
		local f_gp = self:append( field.uint64("granule_position", false, nil, fh.mkbrief("GP")) )
		self:append( field.uint32("serial", false, nil, fh.mkbrief("SERIAL")) )
		self:append( field.uint32("seq", false, nil, fh.mkbrief("SEQ")) )
		self:append( field.uint32("crc") )

		--g_ogg.sample_count = f_gp.value - g_ogg.pre_skip
		g_ogg.sample_count = f_gp.value

		local f_nsegs = self:append( field.uint8("nsegs", nil, fh.mkbrief("SEGS")) )
		local total_size = 0
		local arr_size = {}
		for i=1, f_nsegs.value do
			local f_size = self:append( field.uint8(string.format("size[%d]", i)))
			total_size = total_size + f_size.value
			table.insert(arr_size, f_size.value)
		end

		if true == is_header then
			local pkt_type = ba:peek_uint8()
			if 1 == pkt_type then
				self:append( field_vorbis_header1(total_size) )
			elseif 3 == pkt_type then

				self:append( field.list("packet", total_size, function(self, ba)

					local vorbis_header3_len = arr_size[1]
					g_ogg.pre_skip = vorbis_header3_len

					self:append( field_vorbis_header3(vorbis_header3_len) )

					self:append( field.string("remain", total_size-vorbis_header3_len) )
				end))
			else
				is_header = false
			end
		end

		if false == is_header then
			self:append( field.string("packet", total_size) )
		end
	end)
	return f_page
end


local function decode_ogg( ba, len )
	g_ogg = ogg_t.new()

	g_ogg.fsize = len

    local f_opus = field.list("opus", len, function(self, ba)
		local index = 0
		while true do
			local pos = ba:position()
            bi.set_progress_value(pos)

			local tag = ba:peek_bytes(4)
			if tag ~= "OggS" then 
				break 
			end
			self:append( field_page(index) )
			index = index + 1
		end

		g_ogg.page_count = index
    end)

    return f_opus
end

local function clear()
end

local function build_summary()
	if nil == g_ogg then return end

	g_ogg.bitrate = (g_ogg.fsize*48000*8 + (g_ogg.sample_count >> 1)) / g_ogg.sample_count

	if g_ogg.sample_rate > 0 then
		g_ogg.duration = g_ogg.sample_count / (g_ogg.sample_rate / 1000)
	end

    bi.append_summary("version", g_ogg.version )
    bi.append_summary("channel", g_ogg.channel )
    bi.append_summary("sample_rate", g_ogg.sample_rate )
--    bi.append_summary("pre_skip", g_ogg.pre_skip )

    bi.append_summary("sample_count", g_ogg.sample_count)
    bi.append_summary("bitrate", string.format("%.3f kbps", g_ogg.bitrate/1000))
    bi.append_summary("page_count", g_ogg.page_count)

	local ms = g_ogg.duration 
    bi.append_summary("duration", string.format("%s (%.3f secs)", helper.ms2time(ms), ms/1000))

	if nil ~= g_ogg.vendor then
		bi.append_summary("vendor", g_ogg.vendor)
	end

	for i, v in ipairs(g_ogg.comments) do
		local arr = helper.split( v, '=' )
		bi.append_summary(arr[1], arr[2])
	end

end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "ogg audio files",
    file_ext = "ogg",
    decode = decode_ogg,
    clear = clear,
    build_summary = build_summary,
}

return codec
