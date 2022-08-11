require("class")
local field = require("field")
local fh = require("field_helper")
local helper = require("helper")

--reference
--https://xhelmboyx.tripod.com/formats/mp4-layout.txt
--https://www.cimarronsystems.com/wp-content/uploads/2017/04/Elements-of-the-H.264-VideoAAC-Audio-MP4-Movie-v2_0.pdf
--https://github.com/wlanjie/mp4
local is_decode_h264 = true

local pos_moov = 0
local pos_mdat = 0
local f_mdat = nil
local f_h264_frames = {}

local function is_media_track(typ)
    if typ == "vide" then return true end
    if typ == "soun" then return true end
    return false
end

local mp4_stts_t = class("mp4_stts_t")
function mp4_stts_t:ctor()
    self.entries = {}
end

function mp4_stts_t:add_entry( sample_count, sample_delta )
    table.insert(self.entries, {
        sample_count = sample_count,
        sample_delta = sample_delta,
    })
end

local mp4_stsc_t = class("mp4_stsc_t")
function mp4_stsc_t:ctor()
    self.entries = {}
end

function mp4_stsc_t:add_entry( first_chunk, sample_per_chunk, sample_description_index)
    table.insert(self.entries, {
        first_chunk = first_chunk,
        sample_per_chunk = sample_per_chunk,
        sample_description_index = sample_description_index
    })
end

function mp4_stsc_t:chunk_count()
    return #self.entries
end

function mp4_stsc_t:sum_sample()
    local sum = 0
    for _, o in ipairs(self.entries) do
        sum = sum + o.sample_per_chunk
    end
    return sum
end

local mp4_stsz_t = class("mp4_stsz_t")
function mp4_stsz_t:ctor()
    self.sample_sizes = {}
end

function mp4_stsz_t:add_size( size )
    table.insert(self.sample_sizes, size)
end

local mp4_stco_t = class("mp4_stco_t")
function mp4_stco_t:ctor()
    self.offsets = {}
end

function mp4_stco_t:add_offset( offset )
    table.insert(self.offsets, offset )
end

local mp4_ctts_t = class("mp4_ctts_t")
function mp4_ctts_t:ctor()
    self.entries = {}
end

function mp4_ctts_t:add_entry( sample_count, sample_offset )
    table.insert(self.entries, {
        sample_count = sample_count,
        sample_offset = sample_offset
    })
end

local mp4_elst_t = class("mp4_elst_t")
function mp4_elst_t:ctor()
    self.entries = {}
end

function mp4_elst_t:add_entry( segment_duration, media_time, media_rate_integer, media_rate_fraction )
    table.insert(self.entries, {
        segment_duration = segment_duration,
        media_time = media_time,
        media_rate_integer = media_rate_integer,
        media_rate_fraction = media_rate_fraction
    })
end

local mp4_frame_t = class("mp4_frame_t")
function mp4_frame_t:ctor()
    self.index = 0
    self.pts = 0
    self.dts = 0
    self.cts_delta = 0
    self.duration = 0
    self.offset = 0
    self.size = 0

    self.ichunk = 0
end

local mp4_avcc_t = class("mp4_avcc_t")
function mp4_avcc_t:ctor()
    self.length_size_minus_one = 3
    self.arr_sps = {} --0x00 00 01 ...
    self.arr_pps = {} --0x00 00 01 ...
end

local mp4_summary_track_t = class("mp4_summary_track_t")
function mp4_summary_track_t:ctor()
    self.id = 0
    self.type = ""
    self.time_scale = 0
    self.frame_count = 0
    self.duration = 0
    self.fps = 0

    self.frame_total_size = 0
    self.bitrate = 0

    self.codec = nil --codec type, avcC 

    --video
    self.width = 0
    self.height = 0
    self.avcc = nil

    --audio
    self.channel_count = 0
    self.sample_size = 0

    self.stts = mp4_stts_t.new()
    self.stsc = mp4_stsc_t.new()
    self.stsz = mp4_stsz_t.new()
    self.stco = mp4_stco_t.new()
    self.ctts = mp4_ctts_t.new()
    self.elst = mp4_elst_t.new()

    self.frames = {} --mp4_frame_t
end

function mp4_summary_track_t:calc_dts(iframe)

    local sum_count = 0
    local sum_delta = 0
    local dts = 0
    for i, entry in ipairs(self.stts.entries) do
        local count = entry.sample_count
        local delta = entry.sample_delta

        sum_count = sum_count + count
        sum_delta = sum_delta + count * delta

        if iframe <= sum_count then
            dts = sum_delta - (sum_count - iframe + 1) * delta
            break
        end
    end
    return dts
end

function mp4_summary_track_t:calc_duration(iframe)
    local sum_count = 0
    local duration = 0
    for i, entry in ipairs(self.stts.entries) do
        local count = entry.sample_count
        local delta = entry.sample_delta

        sum_count = sum_count + count
        if iframe <= sum_count then
            duration = delta
            break
        end
    end
    return duration
end

function mp4_summary_track_t:calc_cts_delta(iframe)
    local cts_delta = 0

    local sum_count = 0
    local sum_offset = 0
    for i, entry in ipairs(self.ctts.entries) do
        local count = entry.sample_count
        local offset = entry.sample_offset

        sum_count = sum_count + count
        if iframe <= sum_count then
            cts_delta = offset
            break
        end
    end

    return cts_delta
end

function mp4_summary_track_t:frame_to_chunk_index(iframe)
    local ichunk = 1
    local sum_count = 0
    local last_first = 0
    local last_per_chunk = 0
    local first_iframe = 0

    for i, entry in ipairs(self.stsc.entries) do
        local first_chunk = entry.first_chunk
        local sample_per_chunk = entry.sample_per_chunk
        first_iframe = sum_count + 1
        
        sum_count = sum_count + (first_chunk - last_first) * last_per_chunk

        if iframe <= sum_count then
            local nchunk = math.floor((iframe - first_iframe) / last_per_chunk)
            ichunk = last_first + nchunk
            return ichunk
        end
       
        if iframe <= (sum_count + sample_per_chunk) then
            ichunk = first_chunk
            return ichunk
        end

        last_first = first_chunk
        last_per_chunk = sample_per_chunk
    end
    return nil
end

function mp4_summary_track_t:build_frames()
    local last_ichunk = 0
    local last_frame = nil
    local nchunk = self.stsc:chunk_count()

    local chunk_sum_sample = self.stsc:sum_sample()   
    local ioffset_start = chunk_sum_sample - nchunk
    local noffsets = #self.stco.offsets

    self.frame_total_size = 0

    for i=1, self.frame_count do
        local frame = mp4_frame_t.new()

        frame.index = i
        frame.type = self.type
        frame.cts_delta = self:calc_cts_delta(i)
        frame.duration = self:calc_duration(i)
        frame.dts = self:calc_dts(i)
        frame.pts = frame.dts + frame.cts_delta

        frame.size = self.stsz.sample_sizes[i]

        self.frame_total_size = self.frame_total_size + frame.size

        local ioffsets = 0
        local ichunk = self:frame_to_chunk_index(i)
        if nil ~= ichunk then
            --calc offset
            if last_ichunk ~= ichunk then
                frame.offset = self.stco.offsets[ichunk]
            else
                frame.offset = last_frame.offset + last_frame.size
            end
        else
            ioffsets = i - ioffset_start

            if ioffsets <= noffsets then
                frame.offset = self.stco.offsets[ioffsets]
            else
                frame.offset = last_frame.offset + last_frame.size
            end
        end
        frame.ichunk = ichunk
--        bi.log(string.format("%s[%d].offset = %s itrunk:%s offset:%s/%s"
--                    , self.type, i, tostring(frame.offset), tostring(ichunk)
--                    , ioffsets, noffsets
--                    ))

        last_ichunk = ichunk
        last_frame = frame

        table.insert( self.frames, frame )
    end
    return self.frames
end

local mp4_summary_t = class("mp4_summary_t")
function mp4_summary_t:ctor()
    self.time_scale = 0
    self.duration = 0

    self.tracks = {}
end

function mp4_summary_t:last_track()
    local n = #self.tracks
    if n <= 0 then return nil end
    return self.tracks[n]
end

local func_box = nil

local mp4_summary = nil

local cb_desc_time = function(self)
    if self.value <= 0 then
        return string.format("%s %s:%d", self.type, self.name, 0)
    end

    --year - 66 (in seconds since midnight, January 1, 1904)
    --local k1904_1970s = (66 * 365 + 17) * 24 * 60 * 60
    local k1904_1970s = 2082844800
    local sec = self.value - k1904_1970s
    local str = os.date("%Y-%m-%d %H:%M:%S", sec)
    return string.format("%s %s:%d %s", self.type, self.name, sec, str)
end

local cb_desc_duration = function(self, timescale)
    return string.format("%s %s:%d (%s)", self.type, self.name, self.value, helper.ms2time(self.value, timescale))
end

local cb_desc_resolution = function(self)
    return string.format("%s %s:%d (%d)", self.type, self.name, self.value, self.value >> 16)
end

local get_summary_codec = function(codec_type)
    if codec_type == "avcC" then return "avcC (h264)" end
    return codec_type
end

local swap_endian = true
local peek_box_header = function( ba )
    local data = ba:peek_bytes(8)
    local ba_hdr = byte_stream(8)
    
    ba_hdr:set_data(data, 8)
    local size = ba_hdr:read_uint32(swap_endian)
    local name = ba_hdr:read_bytes(4)
    return size, name
end

local field_box_size = function() 
    local f = field.uint32("size", swap_endian)
    return f
end
local field_box_type = function() 
    local f = field.string("type", 4, fh.str_desc) 
    return f
end

local field_unknown = function()
    local f_len = field_box_size()
    local f_type = field_box_type()

    local f = field.list("unknown", nil, function(self, ba)
        local pos = ba:position()
        self:append( f_len )
        self:append( f_type )

        bi.log(string.format("unknown type %s %d", f_type.value, f_len.value))

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end, function(self)
        return string.format("unknown(%s) len:%d", f_type.value, f_len.value)
    end)
    return f
end

local append_box = function(flist, ba, pos_start, flen)
    local remain = flen - (ba:position() - pos_start)
    while remain > 0 do
        local size, name = peek_box_header(ba)

        local func = func_box[name] or field_unknown
        local f_box = func()
        flist:append( f_box )

        remain = flen - (ba:position() - pos_start)
    end
end

local field_ftyp = function()
    local f = field.list("ftyp FileTypeBox", nil, function(self, ba)
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )
        self:append( field.string("major_brand", 4, fh.str_desc, fh.mkbrief("MAJOR") ) )
        self:append( field.int32("minor_version", swap_endian, nil, fh.mkbrief("V") ) )

        local nremain = f_len.value - 16
        local n = nremain / 4
        for i=1, n do
            self:append( field.string("compatible_brand", 4, fh.str_desc, fh.mkbrief("BRAND") ) )
        end
    end)
    return f
end

local field_mdat = function()

    local f_len = field_box_size()
    local f = field.list("mdat MediaDataBox", nil, function(self, ba)
        local pos = ba:position()
        pos_mdat = pos
        self:append( f_len )
        local f_type = self:append( field_box_type() )

        if f_len.value == 1 then
            local f_large_size = self:append( field.uint64("large_size", swap_endian) )
            f_len.value = f_large_size.value
            --bi.log(string.format("large_size %d 0x%x", f_len.value, f_len.value))
        end

        local tk_video = nil
        local tk_audio = nil
        --build_frames
        local tmp_frames = {}
        if mp4_summary then
            for i, tk in ipairs(mp4_summary.tracks) do
                if is_media_track(tk.type) then
                    if nil == tk_video and tk.type == "vide" then
                        tk_video = tk
                    end
                    if nil == tk_audio and tk.type == "soun" then
                        tk_audio = tk
                    end

                    local frames = tk:build_frames()
                    for _, frame in ipairs(frames) do
                        table.insert( tmp_frames, {
                            index = frame.index,
                            type = frame.type,
                            offset = frame.offset,
                            size = frame.size,
                        })
                    end
                end
            end
        end

        local total = #tmp_frames
        bi.set_progress_max(total)
        if total > 0 then
            table.sort( tmp_frames, function(a, b) return a.offset < b.offset end )
        end

        local cb_desc_frame = function(frame)
            local cb = function(self)
                return string.format("%s[%d] [%d,%d) len:%d"
                        , frame.type, frame.index, frame.offset, frame.offset+frame.size, frame.size)
            end
            return cb
        end

        local cb_desc_h264 = function(frame)
            local cb = function(self)
                local bmp_flag = "✓"
                if nil == self.ffh then
                    bmp_flag = " " --"✗"
                end
                local brief = ""
                if self.get_child_brief then
                    brief = self:get_child_brief()
                end
                return string.format("%s[%d]%s[%d,%d) len:%d %s"
                        , frame.type, frame.index, bmp_flag, frame.offset, frame.offset+frame.size, frame.size, brief)
            end
            return cb
        end

        for tmp_index, frame in ipairs(tmp_frames) do
--            bi.log(string.format( "[%d]frame[%s][%d] size %d", tmp_index, frame.type, frame.index, frame.size))
            local pos = ba:position()
            if frame.offset > pos then
                bi.log(string.format("error: unknwon frame offset index:%d %s [%d,%d] %d", frame.index, frame.type, frame.offset, pos, frame.size))
                self:append( field.string("unknown", frame.offset - pos ) )
            elseif frame.offset < pos then
                bi.log(string.format("error: %s[%d].offset < pos, offset:[%d,%d]", frame.type, frame.index, frame.offset, pos))
                break
            end

            if mp4_summary then
                local is_h264 = frame.type == "vide" and tk_video.codec == "avcC"
                if is_h264 then

                    local codec_h264 = helper.get_codec("h264")
                    --length_size_minus_one
                    local nalu_len = tk_video.avcc.length_size_minus_one + 1
                    
                    local f_frame_h264 = field.list("frame", frame.size, function(self, ba)
                        local pos = ba:position()
                         
                        local nalus = {}
                        local f_nalu_len = self:append(field.uint32("nalu_len", swap_endian))
                        local nalu_data = ba:peek_bytes(f_nalu_len.value)
                        self:append( codec_h264.field_nalu_header(), ba )
                        self:append( field.string("ebsp", f_nalu_len.value-1) )

                        table.insert(nalus, nalu_data)

                        --if frame contains multiple nalus, SPS, PPS, SEI & IDR, need decode IDR frame
                        local remain = frame.size - (ba:position() - pos)
                        while remain > 0 do
                            f_nalu_len = self:append(field.uint32("nalu_len", swap_endian))
                            nalu_data = ba:peek_bytes(f_nalu_len.value)
                            self:append( codec_h264.field_nalu_header(), ba )
                            self:append( field.string("ebsp", f_nalu_len.value-1) )
                            remain = frame.size - (ba:position() - pos)

                            table.insert(nalus, nalu_data)
                        end

                        --decode nalu
                        if is_decode_h264 then
                            for _, nalu_data in ipairs(nalus) do
                                local nalu = string.pack("I3", 0x10000) .. nalu_data
                                self.ffh = bi.decode_avframe(AV_CODEC_ID.H264, nalu, #nalu)
                            end
                            if nil ~= self.ffh then
                                self.ih264 = #f_h264_frames
                            end
                        end
                    end, cb_desc_h264(frame))

                    f_frame_h264.cb_click = function(self)
                        bi.clear_bmp()

                        if nil ~= self.ffh then
                            self.ffh:drawBmp()
                        end
                    end

                    self:append( f_frame_h264 )

                    if f_frame_h264.ffh then
                        table.insert( f_h264_frames, f_frame_h264 )
                    end
                else
                    self:append( field.string("frame", frame.size, cb_desc_frame(frame)) )
                end
            else
                self:append( field.string("frame", frame.size, cb_desc_frame(frame)) )
            end

            bi.set_progress_value(tmp_index)
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)

    f_mdat = f
    return f
end

local field_mvhd = function()

    local f = field.list("mvhd MovieHeaderBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )
        local f_ver = self:append( field.uint8("version") )
        self:append( field.uint24("flags", swap_endian) )

        if f_ver.value == 0 then
            self:append( field.uint32("creation_time", swap_endian, cb_desc_time) )
            self:append( field.uint32("modification_time", swap_endian, cb_desc_time) )
        else
            self:append( field.uint64("creation_time", swap_endian, cb_desc_time) )
            self:append( field.uint64("modification_time", swap_endian, cb_desc_time) )
        end
        local f_time_scale = self:append( field.uint32("time_scale", swap_endian) )

        local time_scale = f_time_scale.value
        local cb_duration = function(self)
            return cb_desc_duration(self, time_scale)
        end

        local f_duration = nil
        if f_ver.value == 0 then
            f_duration = self:append( field.uint32("duration", swap_endian, cb_duration) )
        else
            f_duration = self:append( field.uint64("duration", swap_endian, cb_duration) )
        end

        self:append( field.uint32("rate", swap_endian) )
        self:append( field.uint16("volume", swap_endian) )
        self:append( field.string("reserved", 10) )
        self:append( field.string("matrix", 36) )
        self:append( field.string("pre_defined", 24) )
        self:append( field.uint32("next_track_id", swap_endian) )

        if mp4_summary then
            mp4_summary.time_scale = time_scale
            mp4_summary.duration = f_duration.value
        end
    end)
    return f
end

local field_tkhd = function()
    local f = field.list("tkhd TrackHeaderBox", nil, function(self, ba)
        local pos = ba:position()

        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )
        local f_ver = self:append( field.uint8("version") )

        self:append( field.bit_array("flags", {
                field.ubits("reversed", 20),
                field.ubits("size_is_aspect_ratio", 1),
                field.ubits("in_preivew", 1),
                field.ubits("in_movie", 1),
                field.ubits("enabled", 1),
            }))

        if f_ver.value == 0 then
            self:append( field.uint32("creation_time", swap_endian, cb_desc_time) )
            self:append( field.uint32("modification_time", swap_endian, cb_desc_time) )
        else
            self:append( field.uint64("creation_time", swap_endian, cb_desc_time) )
            self:append( field.uint64("modification_time", swap_endian, cb_desc_time) )
        end

        self:append( field.uint32("track_id", swap_endian) )
        self:append( field.uint32("reserved", swap_endian) )

        if f_ver.value == 0 then
            self:append( field.uint32("duration", swap_endian, cb_desc_duration) )
        else
            self:append( field.uint64("duration", swap_endian, cb_desc_duration) )
        end

        self:append( field.string("reversed", 8) )
        self:append( field.uint16("layer", swap_endian) )
        self:append( field.uint16("alternate_group", swap_endian))
        self:append( field.uint16("volume", swap_endian) )
        self:append( field.uint16("reversed", swap_endian) )
        self:append( field.string("matrix", 36) )

        local f_width = self:append( field.uint32("width", swap_endian, cb_desc_resolution) )
        local f_height = self:append( field.uint32("height", swap_endian, cb_desc_resolution))

        if mp4_summary then
            local track = mp4_summary:last_track()
            track.width = f_width.value >> 16
            track.height = f_height.value >> 16
        end
    end)
    return f
end

local field_mdhd = function()

    local f = field.list("mdhd MediaHeaderBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local f_flags = self:append( field.uint8("flags") )
        local f_ver = self:append( field.uint24("version", swap_endian) )
 
        if f_ver.value == 0 then
            self:append( field.uint32("creation_time", swap_endian, cb_desc_time) )
            self:append( field.uint32("modification_time", swap_endian, cb_desc_time) )
        else
            self:append( field.uint64("creation_time", swap_endian, cb_desc_time) )
            self:append( field.uint64("modification_time", swap_endian, cb_desc_time) )
        end
        local f_time_scale = self:append( field.uint32("time_scale", swap_endian) )

        local time_scale = f_time_scale.value
        local cb_duration = function(self)
            return cb_desc_duration(self, time_scale)
        end

        local f_duration = nil
        if f_ver.value == 0 then
            f_duration = self:append( field.uint32("duration", swap_endian, cb_duration) )
        else
            f_duration = self:append( field.uint64("duration", swap_endian, cb_duration) )
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("language", remain) )
        end

        if mp4_summary then
            local track = mp4_summary:last_track()
            track.time_scale = time_scale
            track.duration = f_duration.value
        end

    end)
    return f
end

local field_hdlr = function( save_handler )
    local f = field.list("hdlr HandlerReferenceBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        self:append( field.string("unknown", 4) )
        local f_handler_type = self:append( field.string("handler_type", 4, fh.str_desc) )
        self:append( field.string("unknwon", 12) )

        local remain = f_len.value  - (ba:position()-pos)
        self:append( field.string("handler_name", remain, fh.str_desc) )

        if save_handler and mp4_summary then
            local track = mp4_summary:last_track()
            track.type = f_handler_type.value
        end
    end)
    return f
end

local field_url = function()

    local f = field.list("url UrlBox", nil, function(self, ba)
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.bit_array("flags", {
            field.ubits("unknown", 23),
            field.ubits("media_data_location_is_defined_in_the_movie_box", 1),
        }))
    end)
    return f

end

local field_dref = function()
    local f = field.list("dref DataReferenceBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        self:append( field.uint32("entries_count", swap_endian) )
        self:append( field_url() )

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_dinf = function()
    local f = field.list("dinf DataInformationBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field_dref() )

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_avc1 = function()

    local f = field.list("avc1", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.string("reversed", 6) )
        self:append( field.uint16("pps_count", swap_endian) )
        self:append( field.uint16("predefined1", swap_endian) )
        self:append( field.uint16("reserved", swap_endian) )
        self:append( field.string("predefined2", 12) )
        self:append( field.uint16("width", swap_endian) )
        self:append( field.uint16("height", swap_endian) )
        self:append( field.uint32("horiz_resolution", swap_endian) )
        self:append( field.uint32("vert_resolution", swap_endian) )
        self:append( field.uint32("reserved", swap_endian) )
        self:append( field.uint16("frame_count", swap_endian) )
        self:append( field.string("compressor_name", 32) )
        self:append( field.uint16("depth", swap_endian) )
        self:append( field.uint16("reserved", swap_endian) )

        append_box(self, ba, pos, f_len.value)
    end)
    return f
end

local field_avcC = function()
    local f = field.list("avcC", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local track = nil
        if mp4_summary then
            track = mp4_summary:last_track()
            track.codec = "avcC"
            track.avcc = mp4_avcc_t.new()
        end

        self:append( field.uint8("version") )
        self:append( field.uint8("profile") )
        self:append( field.uint8("profile_compatibility") )
        self:append( field.uint8("level") )
        local f_length_size = field.ubits("length_size_minus_one", 2, nil, fh.mkbrief())
        local f_sps_count = field.ubits("sps_count", 5, nil, fh.mkbrief())
        self:append( field.bit_list("flags", 2, function(self, ba)
                self:append( field.ubits("reversed", 6) )
                self:append( f_length_size )
                self:append( field.ubits("reversed", 3) )
                self:append( f_sps_count )
            end))

        if track then
            track.avcc.length_size_minus_one = f_length_size.value
        end

        local codec_h264 = helper.get_codec("h264")
        for i=1, f_sps_count.value do
            local f_sps_len = self:append(field.uint16("sps_len", swap_endian))
            local sps_data = ba:peek_bytes(f_sps_len.value)
            self:append( codec_h264.field_sps( f_sps_len.value ) )

            local sps_with_sig = string.pack("I3", 0x10000) .. sps_data

            table.insert(track.avcc.arr_sps, sps_with_sig)

            --bi.decode_frame_to_bmp(AV_CODEC_ID.H264, sps_with_sig, #sps_with_sig)
            bi.decode_avframe(AV_CODEC_ID.H264, sps_with_sig, #sps_with_sig)
        end

        local f_pps_count = self:append( field.uint8("pps_count") )
        for i=1, f_pps_count.value do
            local f_pps_len = self:append(field.uint16("pps_len", swap_endian))
            local pps_data = ba:peek_bytes(f_pps_len.value)
            self:append( codec_h264.field_pps( f_pps_len.value ) )

            local pps_with_sig = string.pack("I3", 0x10000) .. pps_data
            table.insert(track.avcc.arr_pps, pps_with_sig)

            --bi.decode_frame_to_bmp(AV_CODEC_ID.H264, pps_with_sig, #pps_with_sig)
            bi.decode_avframe(AV_CODEC_ID.H264, pps_with_sig, #pps_with_sig)
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_mp4a = function()

    local f = field.list("mp4a", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.string("reversed", 6) )
        self:append( field.uint16("data_reference_index", swap_endian) )
        local f_ver = self:append( field.uint16("version", swap_endian) )
        self:append( field.uint16("revision", swap_endian) )
        self:append( field.uint32("vendor", swap_endian) )
        local f_channel_count = self:append( field.uint16("channel_count", swap_endian) )
        local f_sample_size = self:append( field.uint16("sample_size", swap_endian) )
        self:append( field.uint16("compression_id", swap_endian) )
        self:append( field.uint16("packet_size", swap_endian) )
        local f_sample_rate = self:append( field.uint32("sample_rate", swap_endian, cb_desc_resolution) )

        if f_ver.value == 1 then
            self:append( field.uint32("v1_samples_per_packet", swap_endian) )
            self:append( field.uint32("v1_bytes_per_packet", swap_endian) )
            self:append( field.uint32("v1_bytes_per_frame", swap_endian) )
            self:append( field.uint32("v1_bytes_per_sample", swap_endian) )
        elseif f_ver.value == 2 then
            self:append( field.uint32("v2_samples_per_packet", swap_endian) )
            self:append( field.uint64("v2_sample_rate64", swap_endian) )
            self:append( field.uint32("v2_channel_count", swap_endian) )
            self:append( field.uint32("v2_reseved", swap_endian) )
            self:append( field.uint32("v2_bits_per_channel", swap_endian) )
            self:append( field.uint32("v2_format_specific_flags", swap_endian) )
            self:append( field.uint32("v2_bytes_per_audio_packet", swap_endian) )
            self:append( field.uint32("v2_lpcm_frames_per_audio_packet", swap_endian) )
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end

        if mp4_summary then
            local track = mp4_summary:last_track()
            track.channel_count = f_channel_count.value
            track.sample_size = f_sample_size.value
        end

    end)
    return f
end

local field_stsd = function()
    local f = field.list("stsd SampleDescriptionBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        self:append( field.uint32("entries_count", swap_endian) )

        append_box(self, ba, pos, f_len.value)

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_stts = function()
    local f = field.list("stts DecodingTimeToSampleBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        local f_entries = self:append( field.uint32("entries_count", swap_endian) )

        for i=1, f_entries.value do
            self:append( field.list(string.format("entry[%d]", i), nil, function(self, ba)
                local f_sample_count = self:append( field.uint32("sample_count", swap_endian, nil, fh.mkbrief("sample_count") ) )
                local f_sample_delta = self:append( field.uint32("sample_delta", swap_endian, nil, fh.mkbrief("sample_delta") ) )

                if mp4_summary then
                    local track = mp4_summary:last_track()
                    track.stts:add_entry( f_sample_count.value, f_sample_delta.value)
                end

            end))
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end


    end)
    return f
end

local field_stsc = function()
    local f = field.list("stsc SampleToChunkBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        local f_entries = self:append( field.uint32("entries_count", swap_endian) )

        for i=1, f_entries.value do
            self:append( field.list(string.format("entry[%d]", i), nil, function(self, ba)
                local f_first_chunk = self:append( field.uint32("first_chunk", swap_endian, nil, fh.mkbrief() ) )
                local f_sample_per_chunk = self:append( field.uint32("sample_per_chunk", swap_endian, nil, fh.mkbrief() ) )
                local f_sample_di = self:append( field.uint32("sample_description_index", swap_endian, nil, fh.mkbrief() ) )

                if mp4_summary then
                    local track = mp4_summary:last_track()
                    track.stsc:add_entry( f_first_chunk.value, f_sample_per_chunk.value, f_sample_di.value )
                end
            end))
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_stco = function()
    local f = field.list("stco ChunkOffsetBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        local f_offset_count = self:append( field.uint32("offset_count", swap_endian) )

        for i=1, f_offset_count.value do
            local f_offset = self:append( field.uint32(string.format("offset[%d/%d]", i, f_offset_count.value), swap_endian ) )

            if mp4_summary then
                local track = mp4_summary:last_track()
                track.stco:add_offset( f_offset.value )
            end
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_stsz = function()
    local f = field.list("stsz SampleSizeBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        self:append( field.uint32("sample_size") )
        local f_entries = self:append( field.uint32("sample_count", swap_endian) )

        if f_entries.value > 1 then
            for i=1, f_entries.value do
                local f_sample_size = self:append( field.uint32(string.format("sample_size[%d/%d]", i, f_entries.value), swap_endian ) )

                if mp4_summary then
                    local track = mp4_summary:last_track()
                    track.stsz:add_size( f_sample_size.value )
                end
            end
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end

        if mp4_summary then
            local track = mp4_summary:last_track()
            track.frame_count = f_entries.value
        end
    end)
    return f
end

local field_stss = function()
    local f = field.list("stss SyncSampleTable", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local f_entries = self:append( field.uint32("entrie_count", swap_endian) )
        local f_iframe_count = self:append( field.uint32("iframe_count", swap_endian) )
        for i=1, f_iframe_count.value do
            self:append( field.uint32(string.format("iframe[%d/%d]", i, f_iframe_count.value), swap_endian) )
        end
    end)
    return f
end

local field_ctts = function()
    local f = field.list("ctts CompositionTimeToSampleBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        local f_entries = self:append( field.uint32("entries_count", swap_endian) )

        for i=1, f_entries.value do
            self:append( field.list(string.format("entry[%d/%d]", i, f_entries.value), nil, function(self, ba)
                local f_sample_count = self:append( field.uint32("sample_count", swap_endian, nil, fh.mkbrief() ) )
                local f_sample_offset = self:append( field.uint32("sample_offset", swap_endian, nil, fh.mkbrief() ) )

                if mp4_summary then
                    local track = mp4_summary:last_track()
                    track.ctts:add_entry( f_sample_count.value, f_sample_offset.value )
                end
            end))
        end

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local func_stbl = {
    ["stsd"] = field_stsd,
    ["stts"] = field_stts,
    ["stsc"] = field_stsc,
    ["stco"] = field_stco,
    ["stsz"] = field_stsz,
    ["stss"] = field_stss,
    ["ctts"] = field_ctts,
}

local field_stbl = function()
    local f = field.list("stbl SampleToGroupBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        while ba:length() > 0 do

            local remain = f_len.value  - (ba:position()-pos)
            if remain <= 0 then
                break
            end

            local size, name = peek_box_header(ba)

            local fst = func_stbl[name]
            if nil ~= fst then
                self:append( fst() )
            else
                self:append( field_unknown() )
            end
        end
--[[
        self:append( field_stsd() )
        self:append( field_stts() )
        self:append( field_stsc() )
        self:append( field_stco() )
        self:append( field_stsz() )
        self:append( field_stss() ) --sound track has no stss
--]]

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_vmhd = function()
    local f = field.list("vmhd VideoMediaHeaderBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_smhd = function()
    local f = field.list("smhd SoundMediaHeaderBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local remain = f_len.value  - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end


local field_minf = function()
    local f = field.list("minf MediaInformationBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        append_box(self, ba, pos, f_len.value)
    end)
    return f
end

local field_mdia = function()
    local f = field.list("mdia Mediabox", nil, function(self, ba)
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field_mdhd() )
        self:append( field_hdlr(true) )
        self:append( field_minf() )
    end)
    return f
end

local field_udta = function()
    local f = field.list("udta UserdataBox", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local remain = f_len.value - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end
    end)
    return f
end

local field_elst = function()
    local f = field.list("elst EditListAtoms", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field.uint8("version") )
        self:append( field.uint24("flags") )
        local f_entries = self:append( field.uint32("entries_count", swap_endian) )

        for i=1, f_entries.value do
            self:append( field.list(string.format("entry[%d]", i), nil, function(self, ba)
                local f_seg_dur = self:append( field.uint32("segment_duration", swap_endian, nil, fh.mkbrief("duration")) )
                local f_media_time = self:append( field.uint32("media_time", swap_endian, nil, fh.mkbrief("time")) )
                local f_rate_i = self:append( field.uint16("media_rate_integer", swap_endian, nil, fh.mkbrief("integer")))
                local f_rate_f = self:append( field.uint16("media_rate_fraction", swap_endian, nil, fh.mkbrief("fraction")) )

                if mp4_summary then
                    local track = mp4_summary:last_track()
                    track.elst:add_entry( f_seg_dur.value, f_media_time.value, f_rate_i.value, f_rate_f.value )
                end
            end))
        end

    end)
    return f
end

local field_edts = function()
    local f = field.list("edts Editatoms", nil, function(self, ba)
        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        self:append( field_elst() )
    end)
    return f
end


local field_trak = function()

    local f = field.list("trak TrackBox", nil, function(self, ba)

        if mp4_summary then
            local track = mp4_summary_track_t.new()
            table.insert(mp4_summary.tracks, track)
            track.id = #mp4_summary.tracks
        end

        local pos = ba:position()
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        append_box(self, ba, pos, f_len.value)
    end)
    return f
end

local field_moov = function()

    local f = field.list("moov MovieBox", nil, function(self, ba)
        local pos = ba:position()
        pos_moov = pos
        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        append_box(self, ba, pos, f_len.value)

    end)
    return f
end

local field_free = function()

    local f = field.list("free", nil, function(self, ba)
        local pos = ba:position()

        local f_len = self:append( field_box_size() )
        local f_type = self:append( field_box_type() )

        local remain = f_len.value - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("unknown", remain) )
        end

    end)
    return f
end

if nil == func_box then
    func_box = {
        ["ftyp"] = field_ftyp,
        ["mdat"] = field_mdat,
        ["moov"] = field_moov,
        ["free"] = field_free,

        ["mvhd"] = field_mvhd,
        ["tkhd"] = field_tkhd,
        ["mdhd"] = field_mdhd,
        ["hdlr"] = field_hdlr,
        ["url"] = field_url,
        ["dref"] = field_dref,
        ["dinf"] = field_dinf,
        ["stbl"] = field_stbl,
        ["vmhd"] = field_vmhd,
        ["smhd"] = field_smhd,
        ["minf"] = field_minf,
        ["mdia"] = field_mdia,
        ["udta"] = field_udta,
        ["elst"] = field_elst,
        ["edts"] = field_edts,
        ["trak"] = field_trak,

        ["avc1"] = field_avc1,
        ["avcC"] = field_avcC,
        ["mp4a"] = field_mp4a,
    }
end

local function decode_mp4( ba, len )
    f_h264_frames = {}
    mp4_summary = mp4_summary_t.new()

    pos_mdat = 0
    pos_moov = 0
    f_mdat = nil

    local pos_start = ba:position()
    local fmp4 = field.list("MP4", len, function(self, ba)
        while ba:length() > 0 do
            local pos = ba:position()
            if pos - pos_start > len then
                break
            end

            local size, name = peek_box_header(ba)
            append_box(self, ba, pos, size)
        end

        if f_mdat and (pos_moov > pos_mdat) then
            --parse mdat again
            local pos = ba:position()
            local back = pos - pos_mdat
            ba:back_pos(back)
            f_mdat:read(ba)
        end
    end)

    return fmp4
end

local function build_summary()
    if nil == mp4_summary then return end

    local str_duration = helper.ms2time(mp4_summary.duration, mp4_summary.time_scale)

    bi.append_summary("duration", string.format("%d (%s)", mp4_summary.duration, str_duration))

    local tk_video = nil
    local tk_audio = nil

    local mtk = {}
    for i, tk in ipairs(mp4_summary.tracks) do
        if is_media_track(tk.type) then
            table.insert(mtk, tk)
        end
    end

    for i, tk in ipairs(mtk) do
        local pre = string.format("trk[%d]", i)

        if tk.type == "vide" then
            tk_video = tk
        elseif tk.type == "soun" then
            tk_audio = tk
        end

        bi.append_summary(string.format("%s.type", pre), tk.type)

        if tk.codec then
            bi.append_summary(string.format("%s.codec", pre), get_summary_codec(tk.codec))
        end

        if tk.width ~= 0 then
            bi.append_summary(string.format("%s.resolution", pre), string.format("%dx%d", tk.width, tk.height))
        end

        bi.append_summary(string.format("%s.time_scale", pre), tostring(tk.time_scale))
        str_duration = helper.ms2time(tk.duration, tk.time_scale)
        bi.append_summary(string.format("%s.duration", pre), string.format("%d (%s)", tk.duration, str_duration))

        tk.fps = tk.frame_count / (tk.duration/tk.time_scale)
        bi.append_summary(string.format("%s.fps", pre), string.format("%.2f", tk.fps))
        bi.append_summary(string.format("%s.frame_count", pre), tostring(tk.frame_count))

        local secs = tk.duration / tk.time_scale
        tk.bitrate = tk.frame_total_size * 8 / secs
        bi.append_summary(string.format("%s.bitrate", pre), string.format("%.2f Kbps", tk.bitrate/1000))

        if tk.channel_count ~= 0 then
            bi.append_summary(string.format("%s.channel_count", pre), tostring(tk.channel_count))
            bi.append_summary(string.format("%s.sample_size", pre), tostring(tk.sample_size))
        end
    end

    --video/audio frames
    local tw_video = bi.create_summary_table("VideoFrame")
    local tw_audio = bi.create_summary_table("AudioFrame")

    local tw_header = { "index", "type", "dts", "ms_dts", "pts", "ms_pts", "duration", "range", "len", "chunk" }
    local tw_ncol = #tw_header
    tw_video:set_column_count(tw_ncol)
    tw_audio:set_column_count(tw_ncol)

    for i=1, tw_ncol do
        tw_video:set_header(i-1, tw_header[i] )
        tw_audio:set_header(i-1, tw_header[i] )
    end

    for i, tk in ipairs(mtk) do
        local nframe = #tk.frames
        local tw = tw_video
        if tk.type == "soun" then
            tw = tw_audio
        end

        for j, frame in ipairs(tk.frames) do
            local ms_pts = frame.pts / tk.time_scale * 1000
            local ms_dts = frame.dts / tk.time_scale * 1000
            local ms_duration = frame.duration / tk.time_scale * 1000

            tw:append_empty_row()

            tw:set_last_row_column( 0, string.format("%d/%d", j, nframe) )
            tw:set_last_row_column( 1, frame.type )
            tw:set_last_row_column( 2, tostring(frame.dts) )
            tw:set_last_row_column( 3, helper.ms2time(ms_dts) )
            tw:set_last_row_column( 4, tostring(frame.pts) )
            tw:set_last_row_column( 5, helper.ms2time(ms_pts) )
            tw:set_last_row_column( 6, string.format("%d %.2f", frame.duration, ms_duration) )
            tw:set_last_row_column( 7, string.format("[%d,%d)", frame.offset, frame.offset + frame.size) )
            tw:set_last_row_column( 8, tostring(frame.size) )
            tw:set_last_row_column( 9, tostring(frame.ichunk) )
        end
    end

    local tmp_frames = {}
    for i, tk in ipairs(mp4_summary.tracks) do
        for j, frame in ipairs(tk.frames) do
            table.insert( tmp_frames, {
                ms_pts = frame.pts / tk.time_scale * 1000,
                index = frame.index,
                type = frame.type,
                pts = frame.pts,
                dts = frame.dts,
                size = frame.size,
            })
        end
    end

    table.sort(tmp_frames, function(a, b) return a.ms_pts < b.ms_pts end)

    --timeline
    local tw_timeline = bi.create_summary_table("Timeline")
    local tw_timeline_header = { "ms_pts", "type", "index", "pts", "dts", "size", "type", "index", "pts", "dts", "size" }
    local tw_timeline_ncol = #tw_timeline_header
    tw_timeline:set_column_count(tw_timeline_ncol)
    for i=1, tw_timeline_ncol do
        tw_timeline:set_header(i-1, tw_timeline_header[i] )
    end

    local last_ms_pts = -1
    for i, frame in ipairs(tmp_frames) do
        local tk = tk_video
        local ioffset = 0
        if frame.type == "soun" then
            tk = tk_audio
            ioffset = 5
        end

        if frame.ms_pts ~= last_ms_pts then
            last_ms_pts = frame.ms_pts
            tw_timeline:append_empty_row()
            tw_timeline:set_last_row_column( 0, helper.ms2time(frame.ms_pts) )
        end

        tw_timeline:set_last_row_column( ioffset+1, frame.type )
        tw_timeline:set_last_row_column( ioffset+2, string.format("%d/%d", frame.index, tk.frame_count) )
        tw_timeline:set_last_row_column( ioffset+3, tostring(frame.pts) )
        tw_timeline:set_last_row_column( ioffset+4, tostring(frame.dts) )
        tw_timeline:set_last_row_column( ioffset+5, tostring(frame.size) )
    end
end

local function clear()
    for _, f in ipairs(f_h264_frames) do
        if f.ffh then
            bi.ffmpeg_helper_free(f.ffh)
            f.ffh = nil
        end
    end
    f_h264_frames = {}
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_ext = "mp4 m4a",
    decode = decode_mp4,
    build_summary = build_summary, 
    clear = clear,
}

return codec
