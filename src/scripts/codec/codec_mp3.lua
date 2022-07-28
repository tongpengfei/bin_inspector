local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

local swap_endian = true

local MP3_LAYER = {
    III = 1,
    II =  2,
    I  =  3,
}

local MP3_MPEG_VER = {
    _2_5 = 0,
    _2   = 2,
    _1   = 3,
}

local MP3_MPEG_VER_STR = {
    [0] = "MPEG-2.5",
    [1] = "reserved",
    [2] = "MPEG-2",
    [3] = "MPEG-1",
}

local MP3_LAYER_STR = {
    [0] = "reserved",
    [1] = "Layer3",
    [2] = "Layer2",
    [3] = "Layer1",
}

local MP3_PROTECT_STR = {
    [0] = "CRC",
    [1] = "NOCRC",
}

local MP3_MODE_CHANNEL_STR = {
    [0] = "Stereo",
    [1] = "JointStereo",
    [2] = "DualChannel",
    [3] = "SingleChannel",
}

local MP3_PADDING_STR = {
    [0] = "not padded",
    [1] = "padded with one extra slot",
}

local SAMPLING_RATE_TABLE = {
           --V2.5  _     V2     V1
    { 11025, 0, 22050, 44100}, --0x00
    { 12000, 0, 24000, 48000}, --0x01
    {  8000, 0, 16000, 32000}, --0x02
    {     0, 0,     0,     0}, --0x03
}

local BITRATE_TABLE = {
     --L0   L3   L2   L1    L0   L3   L2   L1
    {  0,   0,   0,   0,    0,   0,   0,   0}, --0000
    {  0,  32,  32,  32,    0,   8,   8,  32}, --0001
    {  0,  40,  48,  64,    0,  16,  16,  48}, --0010
    {  0,  48,  56,  96,    0,  24,  24,  56}, --0011
    {  0,  56,  64, 128,    0,  32,  32,  64}, --0100
    {  0,  64,  80, 160,    0,  40,  40,  80}, --0101
    {  0,  80,  96, 192,    0,  48,  48,  96}, --0110
    {  0,  96, 112, 224,    0,  56,  56, 112}, --0111
    {  0, 112, 128, 256,    0,  64,  64, 128}, --1000
    {  0, 128, 160, 288,    0,  80,  80, 144}, --1001
    {  0, 160, 192, 320,    0,  96,  96, 160}, --1010
    {  0, 192, 224, 352,    0, 112, 112, 176}, --1011
    {  0, 224, 256, 384,    0, 128, 128, 192}, --1100
    {  0, 256, 320, 416,    0, 144, 144, 224}, --1101
    {  0, 320, 384, 448,    0, 160, 160, 256}, --1110
    { -1,  -1,  -1,  -1,    0,  -1,  -1,  -1}, --1111
}

local SAMPLER_PER_SECOND = {
    --V2.5    _    V2    V1
    {   0,    0,    0,    0}, --00 - reserved
    { 576,    0,  576, 1152}, --01 - Layer III
    {1152,    0, 1152, 1152}, --10 - Layer II
    { 384,    0,  384,  384}, --11 - Layer I
}

local STR_ENCODE = {
    [0] = "iso-8859-1",
    [1] = "utf-16",
    [2] = "utf-16be",
    [3] = "utf-8",
}

local PIC_TYPE_STR = {
    [0] = "Other",
    [1] = "32x32 pixels 'file icon' (PNG only)",
    [2] = "Other file icon",
    [3] = "Cover (front)",
    [4] = "Cover (back)",
    [5] = "Leaflet page",
    [6] = "Media (e.g. lable side of CD)",
    [7] = "Lead artist/lead performer/soloist",
    [8] = "Artist/performer",
    [9] = "Conductor",
    [10] = "Band/Orchestra",
    [11] = "Composer",
    [12] = "Lyricist/text writer",
    [13] = "Recording Location",
    [14] = "During recording",
    [15] = "During performance",
    [16] = "Movie/video screen capture",
    [17] = "A bright coloured fish",
    [18] = "Illustration",
    [19] = "Band/artist logotype",
    [20] = "Publisher/Studio logotype",
}

--https://github.com/biril/mp3-parser
local function get_frame_length(kbitrate, sampling_rate, padding, ver, layer)
    local sample_length = SAMPLER_PER_SECOND[layer+1][ver+1]
    local padding_size = 0
    if padding ~= 0 then
        if layer == MP3_LAYER.I then
            padding = 4
        else
            padding = 1
        end
    end
    local byte_rate = kbitrate * 1000 / 8
    return math.floor((sample_length * byte_rate / sampling_rate) + padding_size)
end

local id3v2_hdr_t = class("id3v2_hdr_t")
function id3v2_hdr_t:ctor()
    self.flag_unsynchronisation = 0
    self.flag_ext_hdr = 0
    self.flag_exp_ind = 0
    self.flag_footer = 0
    self.size = 0
end

local mp3_summary_t = class("mp3_summary_t")
function mp3_summary_t:ctor()
    self.ver = 0
    self.layer = 0
    self.channel = 0
    self.total_sample_length = 0
    self.sampling_rate = 0
    self.bitrate = 0
    self.duration = 0
    self.frames = 0
end

local mp3_summary = nil

local function field_id3v2_header( id3v2_hdr )
    local f = field.list("header", nil, function(self)
        self:append( field.string("id", 3, fh.str_desc, fh.mkbrief("ID") ) )
        self:append( field.uint16("ver", false, nil, fh.mkbrief("V") ) )
        self:append( field.bit_list("flags", 1, function(self, ba)
                local f_unsynchronisation = self:append( field.ubits("unsynchronisation", 1, nil, fh.mkbrief("UNSYCH")) )
                local f_ext_hdr = self:append( field.ubits("extended_header", 1, nil, fh.mkbrief("EXT") ) )
                local f_exp_ind = self:append( field.ubits("experimental_indicator", 1, nil, fh.mkbrief("EXP") ) )
                local f_footer = self:append( field.ubits("footer_present", 1, nil, fh.mkbrief("FOOT") ) )
                self:append( field.ubits("reserved", 4) )

                id3v2_hdr.flag_unsynchronisation = f_unsynchronisation.value
                id3v2_hdr.flag_ext_hdr = f_ext_hdr.value
                id3v2_hdr.flag_exp_ind = f_exp_ind.value
                id3v2_hdr.flag_footer = f_footer.value
            end, nil, fh.child_brief) )
        local f_size = self:append( field.uint32("size", swap_endian, nil, fh.mkbrief("L") ) )

        id3v2_hdr.size = f_size.value
    end, nil, fh.child_brief)
    return f
end

local function field_ext_header()
    local f = field.list("ext_header", nil, function(self)
        self:append( field.uint32("ext_hdr_size", swap_endian, nil, fh.mkbrief("L") ) )
        self:append( field.uint16("flags") )
        self:append( field.uint32("padding_size") )
    end)
    return f
end

local function field_tag_body_TXXX(len)

end

--https://id3.org/id3v2.3.0#Declared_ID3v2_frames
local function field_tag_body_APIC(len)
    local f = field.list("APIC", len, function(self, ba)
        local pos_start = ba:position()

        local f_encode = self:append( field.uint8("encode", fh.mkdesc(STR_ENCODE)) )
        local pos = ba:position()
        local pos_end = ba:search( string.pack("I1", 0x00), 1 )
        local str_len = pos_end - pos + 1
        local f_mime = self:append( field.string("mime", str_len, fh.str_desc) )

        self:append( field.uint8("pic_type", fh.mkdesc(PIC_TYPE_STR)) )

        pos = ba:position()
        local pos_str_end = ba:search( string.pack("I1", 0x00), 1 )
        str_len = pos_str_end - pos + 1

        local encode = f_encode.value
        if encode == 1 or encode == 2 then
            self:append( field.string("desc", str_len) )
        elseif encode == 3 then
            self:append( field.string("desc", str_len) )
        end

        pos = ba:position()
        local pos_not0 = ba:skip0()
        if pos_not0 > 0 then
            self:append( field.string("skip", pos_not0 - pos) )
        end

        local remain = len - (ba:position() - pos_start)
        local f_pic = self:append( field.string("pic", remain) )
        if string.find(f_mime.value, "image/jpeg") then
            bi.draw_jpeg( f_pic:get_data(), remain )
        end    
    end)
    return f
end

local function field_tag(index)
    local f = field.list(string.format("tag[%d]", index), nil, function(self)

        local f_id = field.string("id", 4, fh.str_desc, fh.mkbrief("ID") )
        local f_size = field.uint32("size", swap_endian, nil, fh.mkbrief("L") )
        local f_flag = field.uint16("flag")

        self:append( field.list("header", nil, function(self)
            self:append( f_id )
            self:append( f_size )
            self:append( f_flag )
        end, nil, fh.child_brief))

        self:append( field.select("body", f_size.value, function()
            local id = f_id.value
            local len = f_size.value
            --if string.char(id:byte(1)) == 'T' then return field_tag_body_TXXX(len) end
            if id == "APIC" then return field_tag_body_APIC(len) end

            return field.string("body", len)
        end))
    end)
    return f
end

local function field_frame(index)

    local f = field.list(string.format("frame[%d]", index), nil, function(self, ba)
        local old_pos = ba:position()

        local f_ver = field.ubits("ver", 2, fh.mkdesc(MP3_MPEG_VER_STR), fh.mkbrief("V", MP3_MPEG_VER_STR) )
        local f_layer = field.ubits("layer", 2, fh.mkdesc(MP3_LAYER_STR), fh.mkbrief("L", MP3_LAYER_STR) )
        local f_protect = field.ubits("protect", 1, fh.mkdesc(MP3_PROTECT_STR), fh.mkbrief("PROT", MP3_PROTECT_STR) )
        local f_bitrate_index = field.ubits("bitrate_index", 4) 
        local f_sampling_rate_index = field.ubits("sampling_rate_index", 2)
        local f_padding = field.ubits("padding", 1, fh.mkdesc(MP3_PADDING_STR))
        local f_mode_chan = field.ubits("mode_chan", 2, fh.mkdesc(MP3_MODE_CHANNEL_STR), fh.mkbrief("CH", MP3_MODE_CHANNEL_STR) )

        local f_audio_header = field.bit_list("header", 4, function(self)

            self:append( field.ubits("sync", 11) )
            self:append( f_ver )
            self:append( f_layer )
            self:append( f_protect )

            self:append( f_bitrate_index )
            self:append( f_sampling_rate_index )
            self:append( f_padding )
            self:append( field.ubits("private", 1) )

            self:append( f_mode_chan )

            self:append( field.ubits("mode_ext", 2) )
            self:append( field.ubits("copyright", 1) )
            self:append( field.ubits("original", 1) )
            self:append( field.ubits("emphasis", 2) )

            if f_protect.value == 0 then
                self:append( field.ubits("crc_check", 16) )
                self.len = 6
            end
        end, nil, fh.child_brief)
        self:append( f_audio_header )

        local layer = f_layer.value
        local ver = f_ver.value
        local br_index = layer
        if ver == MP3_MPEG_VER._2 or ver == MP3_MPEG_VER._2_5 then
            br_index = br_index + 4
        end
        local sampling_rate = SAMPLING_RATE_TABLE[f_sampling_rate_index.value+1][ver+1]
        if sampling_rate <= 0 then
            return
        end

        local kbitrate = BITRATE_TABLE[f_bitrate_index.value+1][br_index+1]
        --bi.log(string.format("BITRATE_TABLE[%d][%d] = %d", f_bitrate_index.value+1, br_index+1, kbitrate))
        local frame_len = get_frame_length(kbitrate, sampling_rate, padding, ver, layer)
        if frame_len <= 0 then
            return
        end

        local sample_length = SAMPLER_PER_SECOND[layer+1][ver+1]
        local duration = sample_length / sampling_rate * 1000

        if mp3_summary and sample_length > 0 then
            mp3_summary.ver = ver
            mp3_summary.layer = layer
            mp3_summary.sampling_rate = sampling_rate
            mp3_summary.bitrate = kbitrate
            mp3_summary.total_sample_length = mp3_summary.total_sample_length + sample_length
        end

        local cb_hdr_brief = function(self)
            local child_brief = self:get_child_brief()
            return string.format("%sSMP:%d %.2fms %d %dkbps", child_brief, sample_length, duration, sampling_rate, kbitrate)
        end
        f_audio_header.get_brief = cb_hdr_brief

        local data_len = frame_len - (ba:position() - old_pos)
        if f_padding.value ~= 0 then
            data_len = data_len + 1
        end

        --bi.log(string.format("data_len %s, frame_len:%s sampling_rate:%d", tostring(data_len), tostring(frame_len), sampling_rate))
        self:append( field.string("data", data_len) )
    end)

	f.cb_context_menu = function(self, menu)

		menu:add_action("Extract Frame", function()
			bi.log(string.format("Extract Frame %s", self.name))
		end)

		menu:add_action("Extract Frame All", function()
			bi.log(string.format("Extract Frame All %s", self.name))
		end)

	end
    return f
end

local function is_syn(ba)
    if ba:length() < 2 then return false end

    local syn = ba:peek_ubits(11)
    if syn == 0x7FF then
        return true
    end

    return false
end

local function decode_mp3( ba, len )
    mp3_summary = mp3_summary_t.new()

    local f_mp3 = field.list("MP3", len, function(self, ba)

        local id3v2_hdr = id3v2_hdr_t.new()

        local f_id3v2 = field.list("id3v2", nil, function(self, ba)

            self:append( field_id3v2_header(id3v2_hdr) )

            if id3v2_hdr.flag_ext_hdr == 1 then
                self:append( field_ext_header() )
            end

            local total_tag_size = id3v2_hdr.size + 10

            --parse tag frame
            local index = 0
            while ba:position() < total_tag_size do
                if is_syn(ba) then
                    break
                end

                index = index + 1
                self:append( field_tag(index) )

                local pos = ba:position()
                local pos_not0 = ba:skip0()
                if pos_not0 > pos then
                    self:append( field.string("padding", pos_not0 - pos) )
                end
            end
        end)

        local id3 = ba:peek_uint24()
        if id3 == 0x334449 then --ID3
            self:append( f_id3v2 )
        end

        local pos = ba:position()

        --search audio frame syn
        local tmp_len = ba:length()
        local tmp = ba:peek_bytes(tmp_len)
        local tmp_ba = byte_stream(tmp_len)
        tmp_ba:set_data(tmp, tmp_len)
        while tmp_ba:length() > 1 do
            local u16 = tmp_ba:peek_uint16()
            if u16 == 0xFAFF or u16 == 0xFBFF then
                if tmp_ba:position() > 0 then
                    self:append( field.string("skip", tmp_ba:position() ) )
                end
                break
            end
            tmp_ba:read_uint8()
        end

        --audio frames
        index = 0
        while ba:length() > 0 do
            index = index + 1

            if not is_syn(ba) then
                break
            end

            self:append(field_frame(index))

            pos = ba:position()
            bi.set_progress_value(pos)
        end

        pos = ba:position()
        local remain = len - pos
        if remain > 0 then
            self:append( field.string("remain", remain) )
        end

        mp3_summary.frames = index
    end)

    return f_mp3
end

local function build_summary()
    if nil == mp3_summary then return end

    bi.append_summary("ver", MP3_MPEG_VER_STR[mp3_summary.ver])
    bi.append_summary("layer", MP3_LAYER_STR[mp3_summary.layer])
    bi.append_summary("channel", MP3_MODE_CHANNEL_STR[mp3_summary.channel])
    bi.append_summary("sample_rate", string.format("%s Hz", mp3_summary.sampling_rate))
    bi.append_summary("bitrate", string.format("%d kbps", mp3_summary.bitrate))
    bi.append_summary("frames", mp3_summary.frames)

    if mp3_summary.sampling_rate > 0 then
        mp3_summary.duration = mp3_summary.total_sample_length/ mp3_summary.sampling_rate * 1000

        local ms = mp3_summary.duration
        bi.append_summary("duration", string.format("%s (%.3f secs)", helper.ms2time(ms), ms/1000))
    end
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_ext = "mp3",
    decode = decode_mp3,
    build_summary = build_summary,
}

return codec
