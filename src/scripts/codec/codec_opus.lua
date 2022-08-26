local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

--https://opus-codec.org
--https://tools.ietf.org/html/rfc6716
--https://github.com/xiph/opusfile

--get opus decoder src:
--[[
	wget https://www.rfc-editor.org/rfc/rfc6716.txt
	cat rfc6716.txt | grep '^\ \ \ ###' | sed -e 's/...###//' | base64 --decode > opus-rfc6716.tar.gz
	cd opus-rfc6716
	make
--]]

--https://opus-codec.org/docs/opusfile_api-0.7/opusfile_8h_source.html
--[[
struct OpusHead{
	int           version;
	int           channel_count;
	unsigned      pre_skip;
	opus_uint32   input_sample_rate;
	int           output_gain;
	int           mapping_family;
	int           stream_count;
	int           coupled_count;
	unsigned char mapping[OPUS_CHANNEL_COUNT_MAX];
};
--]]

local opus_t = class("opus_t")
function opus_t:ctor()
	self.fsize = 0
	self.version = 0
	self.channel = 0
	self.pre_skip = 0
	self.sample_rate = 0
	self.stream_count = 0
	self.coupled_count = 0
	self.sample_count = 0
	self.bitrate = 0
	self.vendor = nil
	self.comments = {}
	self.duration = 0
	self.page_count = 0
end

local g_opus = nil

local function field_opus_head(len)
	local f = field.list("opus_head", len, function(self, ba)
		local pos = ba:position()
		local f_tag = self:append( field.string("tag", 8, fh.str_desc, fh.str_brief_v) )
		local f_version = self:append( field.uint8("version", nil, fh.mkbrief("V")) )
		local f_ch = self:append( field.uint8("channel_count", nil, fh.mkbrief("CH")) )
		local f_pre_skip = self:append( field.uint16("pre_skip", false, nil, fh.mkbrief("SKIP")) )
		local f_sample_rate = self:append( field.uint32("input_sample_rate", false, nil, fh.mkbrief("SAMPLE_RATE")) )
		local f_output_gain = self:append( field.uint16("output_gain") )
		local f_mapping_family = self:append( field.uint8("mapping_family") )
		local stream_count = 1
		local coupled_count = f_ch.value - 1

		if 0 == f_mapping_family.value then
		else
			stream_count = self:append( field.uint8("stream_count") )
			coupled_count = self:append( field.uint8("coupled_count") )

			for i=1, f_ch.value do
				self:append( field.uint8(string.format("mapping[%d]", i-1)) )
			end
		end

		local remain = len - (ba:position() - pos)
		if remain > 0 then
			self:append(field.string("unknown", remain))
		end

		g_opus.version = f_version.value
		g_opus.channel = f_ch.value
		g_opus.pre_skip = f_pre_skip.value
		g_opus.sample_rate = f_sample_rate.value
		g_opus.stream_count = stream_count
		g_opus.coupled_count = coupled_count

	end, nil, fh.child_brief)
	return f
end

local function field_opus_tags(len)
	local f = field.list("opus_tags", len, function(self, ba)
		local pos = ba:position()
		local f_tag = self:append( field.string("tag", 8, fh.str_desc, fh.str_brief_v) )
		local f_vendor_len = self:append( field.uint32("vendor_len") )
		if f_vendor_len.value > 0 then
			local f_vendor = self:append( field.string("vendor", f_vendor_len.value, fh.str_desc, fh.str_brief) )
			g_opus.vendor = f_vendor:get_data()
		end
		local f_ncomments = self:append( field.uint32("ncomments") )
		for i=0, f_ncomments.value-1 do
			self:append( field.list(string.format("comment[%d]", i), nil, function(self, ba)
				local f_comment_len = self:append( field.uint32("size") )
				if f_comment_len.value > 0 then
					local f_comment = self:append(field.string("comment", f_comment_len.value, fh.str_desc, fh.str_brief_v))

					table.insert(g_opus.comments, f_comment:get_data())
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

	local f_page = field.list(string.format("page[%d]", index), nil, function(self, ba)
		local f_sync = self:append( field.string("sync", 4, fh.str_desc, fh.str_brief_v) )
		if f_sync:get_data() ~= "OggS" then
			--error format 
			return
		end

		self:append( field.uint8("version", nil, fh.mkbrief("V")) )
		self:append( field.uint8("header_type", nil, fh.mkbrief("T")) )
		local f_gp = self:append( field.uint64("granule_position", false, nil, fh.mkbrief("GP")) )
		self:append( field.uint32("serial", false, nil, fh.mkbrief("SERIAL")) )
		self:append( field.uint32("seq", false, nil, fh.mkbrief("SEQ")) )
		self:append( field.uint32("crc") )

		g_opus.sample_count = f_gp.value - g_opus.pre_skip

		local f_nsegs = self:append( field.uint8("nsegs", nil, fh.mkbrief("SEGS")) )
		local total_size = 0
        local arr_size = {}

        self:append( field.list(string.format("seg_size count:%d", f_nsegs.value), nil, function(self, ba)
    		for i=1, f_nsegs.value do
    			local f_size = self:append( field.uint8(string.format("size[%d]", i)))
    			total_size = total_size + f_size.value
                table.insert(arr_size, f_size.value)
    		end
        end))

		if 1 == f_nsegs.value then
			local tag = ba:peek_bytes(8)
			if tag == "OpusHead" then
				self:append( field_opus_head( total_size ) )
			elseif tag == "OpusTags" then
				self:append( field_opus_tags( total_size ) )
			end
		else
            self:append( field.list(string.format("packets count:%d", f_nsegs.value), nil, function(self, ba)
                for i, pack_size in ipairs(arr_size) do
                    self:append( field.string(string.format("packet[%d]", i-1), pack_size) )
                end
            end))
		end

	end)
	return f_page
end


local function decode_opus( ba, len )
	g_opus = opus_t.new()

	g_opus.fsize = len

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

		g_opus.page_count = index
    end)

    return f_opus
end

local function clear()
end

local function build_summary()
	if nil == g_opus then return end

	g_opus.bitrate = (g_opus.fsize*48000*8 + (g_opus.sample_count >> 1)) / g_opus.sample_count

	if g_opus.sample_rate > 0 then
		g_opus.duration = g_opus.sample_count / (g_opus.sample_rate / 1000)
	end

    bi.append_summary("version", g_opus.version )
    bi.append_summary("channel", g_opus.channel )
    bi.append_summary("sample_rate", g_opus.sample_rate )
    bi.append_summary("stream_count", g_opus.stream_count)
    bi.append_summary("coupled_count", g_opus.coupled_count)

    bi.append_summary("pre_skip", g_opus.pre_skip)
    bi.append_summary("sample_count", g_opus.sample_count)
    bi.append_summary("bitrate", string.format("%.3f kbps", g_opus.bitrate/1000))
    bi.append_summary("page_count", g_opus.page_count)

	local ms = g_opus.duration 
    bi.append_summary("duration", string.format("%s (%.3f secs)", helper.ms2time(ms), ms/1000))

	if nil ~= g_opus.vendor then
		bi.append_summary("vendor", g_opus.vendor)
	end

	for i, v in ipairs(g_opus.comments) do
		local arr = helper.split( v, '=' )
		bi.append_summary(arr[1], arr[2])
	end
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "opus audio files",
    file_ext = "opus",
    decode = decode_opus,
    clear = clear,
    build_summary = build_summary,
}

return codec
