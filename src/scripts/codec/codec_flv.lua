require("class")
local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

local FLV_TYPE = {
    AUDIO = 8,
    VIDEO = 9,
    SCRIPT = 18,
}

local FLV_TYPE_STR = {
    [FLV_TYPE.AUDIO] = "AUDIO",
    [FLV_TYPE.VIDEO] = "VIDEO",
    [FLV_TYPE.SCRIPT] = "SCRIPT",
}

local AMF_TYPE = {
    NUMBER = 0x00,
    BOOLEAN= 0x01,
    STRING = 0x02,
    OBJECT = 0x03,
    NULL   = 0x05,
    ARRAY  = 0x08,
    OBJ_END_MARK = 0x09,
}

local AMF_TYPE_STR = {
    [0] = "number",
    [1] = "boolean",
    [2] = "string",
    [3] = "object",
    [5] = "null",
    [8] = "array",
    [9] = "obj_end_mark",
}

local SOUND_FORMAT = {
    PCM = 0,
    ADPCM = 1,
    MP3 = 2,
    PCM_LE = 3,
--    [4] = "Nellymoser 16-kHz mono",
--    [5] = "Nellymoser 8-kHz mono",
--    [6] = "Nellymoser",
--    [7] = "G.711 A-law logarithmic PCM",
--    [8] = "G.711 mu-law logarithmic PCM 9 = reserved",
    AAC = 10,
    SPEEX = 11,
    MP3_8KHZ = 14,
    DEVICE_SPECIFIC_SOUND = 15,
}


local SOUND_FORMAT_STR = {
    [0] = "Linear PCM, platform endian",
    [1] = "ADPCM",
    [2] = "MP3",
    [3] = "Linear PCM, little endian",
    [4] = "Nellymoser 16-kHz mono",
    [5] = "Nellymoser 8-kHz mono",
    [6] = "Nellymoser",
    [7] = "G.711 A-law logarithmic PCM",
    [8] = "G.711 mu-law logarithmic PCM 9 = reserved",
    [10] = "AAC",
    [11] = "Speex",
    [14] = "MP3 8-Khz",
    [15] = "Device-specific sound",
}

local SAMPLE_RATE_STR = {
    [0] = "5.5kHz",
    [1] = "11kHz",
    [2] = "22kHz",
    [3] = "44kHz",
}

local SAMPLE_BITS_STR = {
    [0] = "8bit",
    [1] = "16bit"
}

local CHANNEL_STR = {
    [0] = "mono",
    [1] = "stereo",
}

local AAC_PACKET_TYPE = {
    SEQUENCE_HEADER = 0, --AudioSpecificConfig
    RAW = 1, --audio data
}

local AAC_PACKET_TYPE_STR = {
    [0] = "AudioSpecificConfig",
    [1] = "AudioRawData",
}

local VIDEO_FRAME_TYPE = {
    KEY_FRAME = 1,
    INTER_FRAME = 2,
    DISPOSABLE_INTER_FARME = 3,
    GENERATED_KEY_FRAME = 4,
    VIDEO_INFO = 5,
}

local VIDEO_FRAME_TYPE_STR = {
    [1] = "key frame", -- (for AVC, a seekable frame)
    [2] = "inter frame", -- (for AVC, a non-seekable frame)
    [3] = "disposable inter frame", -- (H.263 only)
    [4] = "generated key frame", -- (reserved for server use only)
    [5] = "video info/command frame",
}

local VIDEO_CODEC_ID = {
    JPEG = 1,
    H263 = 2,
    SCREEN_VIDEO = 3,
    VP6 = 4,
    VP6_ALPHA = 5,
    SCREEN_VIDEO_V2 = 6,
    AVC = 7
}


local VIDEO_CODEC_ID_STR = {
    [1] = "JPEG",
    [2] = "Sorenson H.263",
    [3] = "Screen video",
    [4] = "On2 VP6",
    [5] = "On2 VP6 with alpha channel",
    [6] = "Screen video version 2",
    [7] = "AVC",
}

local AVC_PACKET_TYPE = {
    SEQUENCE_HEADER = 0,
    NALU = 1,
    END_OF_SEQUENCE = 2,
}

local AVC_PACKET_TYPE_STR = {
    [0] = "AVC sequence header",
    [1] = "AVC NALU",
    [2] = "AVC end of sequence", -- (lower level NALU sequence ender is not required or supported)
}

local flv_summary_t = class("flv_summary")
function flv_summary_t:ctor()
    self.amf = {} --key:value

end



local swap_endian = true
local flv_summary = nil

local field_flv_header = function()
    local f = field.array("header", 9, {
        field.string("signature", 3, fh.str_desc, fh.mkbrief("SIG")),
        field.uint8("version", nil, fh.mkbrief("V")),
        field.bit_array("flags", {
            field.ubits("type_flags_reversed", 5),
            field.ubits("type_flags_audio", 1, nil, fh.mkbrief("audio")),
            field.ubits("type_flags_reversed", 1),
            field.ubits("type_flags_video", 1, nil, fh.mkbrief("video")),
        }, nil, fh.child_brief),
        field.uint32("data_offset", swap_endian, nil, fh.mkbrief("HLEN")),
    })

    return f
end

local function field_meta_data(len)
    local f = field.list("metadata", len, function(self, ba)
        local pos = ba:position()

        while ba:length() > 0 do
            local remain = len - (ba:position() - pos)
            if remain <= 3 then
                self:append( field.uint24("end_mark", swap_endian) )
                break
            end

            local stype = nil
            local key = nil
            local value = nil
            local vtype = nil
            self:append(field.list("amf", nil, function(self, ba)

                local f_len = self:append(field.uint16("len", swap_endian))
                local f_key = self:append(field.string("key", f_len.value, fh.str_desc, fh.mkbrief()))
                local f_value = nil

                local f_vtype = self:append(field.uint8("vtype", fh.mkdesc(AMF_TYPE_STR)))
    
                vtype = f_vtype.value
                if vtype == AMF_TYPE.NUMBER then
                    f_value = self:append(field.double("value", swap_endian, nil, fh.mkbrief()))
                    value = f_value.value
                elseif vtype == AMF_TYPE.BOOLEAN then
                    f_value = self:append(field.uint8("value"))
                    value = f_value.value
                elseif vtype == AMF_TYPE.STRING then
                    local f_vlen = self:append(field.uint16("len", swap_endian))
                    f_value = self:append(field.string("value", f_vlen.value, fh.str_desc))
                    value = f_value.value
                elseif vtype == AMF_TYPE.OBJECT then
                    bi.log("todo amf object")
                elseif vtype == AMF_TYPE.NULL then
                    value = ""
                elseif vtype == AMF_TYPE.ARRAY then
                    bi.log("todo amf array")
                elseif vtype == AMF_TYPE.OBJ_END_MARK then
                end

                stype = AMF_TYPE_STR[vtype] or "??"
                key = f_key.value

                if f_value then
                    flv_summary.amf[key] = f_value.value
                end
            end, function(self)
                return string.format("amf %s %s: %s", stype, key, value)
            end))

            if  vtype == AMF_TYPE.OBJECT or
                vtype == AMF_TYPE.ARRAY or
                vtype == AMF_TYPE.OBJ_END_MARK then
                bi.log(string.format("todo amf %s", stype))
                break
            end
        end

        local remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append( field.string("amf", remain) )
        end

        local nread = ba:position() - pos
        if nread > len then
            ba:back_pos( nread - len )
        end
    end)
    return f
end

local function field_script(len)

    local f = field.list("script", len, function(self, ba)

        self:append( field.list("amf1", nil, function(self, ba)
            self:append( field.uint8("type", nil, fh.mkbrief("T")) )
            self:append( field.uint16("len", swap_endian, nil, fh.mkbrief("L")) )
            self:append( field.string("value", 10, fh.str_desc, fh.mkbrief("V")) )
        end))

        self:append( field.list("amf2", nil, function(self, ba)
            self:append( field.uint8("type", nil, fh.mkbrief("T")) )
            self:append( field.uint32("len", swap_endian, nil, fh.mkbrief("L")) )
            local value_len = len - 13 - 5

            --self:append( field.string("value", value_len) )
            self:append( field_meta_data(value_len) )
        end))
    end)
    return f
end

local function field_audio(len)
    local f = field.list("audio", len, function(self, ba)

        local f_fmt = field.ubits("sound_format", 4, fh.mkdesc(SOUND_FORMAT_STR), fh.mkbrief("FMT", SOUND_FORMAT_STR))

        self:append( field.bit_list("header", 1, function(self, ba)
            self:append( f_fmt )
            self:append( field.ubits("sound_rate", 2, fh.mkdesc(SAMPLE_RATE_STR), fh.mkbrief("RATE", SAMPLE_RATE_STR)) )
            self:append( field.ubits("sound_size", 1, fh.mkdesc(SAMPLE_BITS_STR), fh.mkbrief("BITS", SAMPLE_BITS_STR)) )
            self:append( field.ubits("sound_type", 1, fh.mkdesc(CHANNEL_STR), fh.mkbrief("CH", CHANNEL_STR)) )
        end))

        local data_len = len -1
        if f_fmt.value == SOUND_FORMAT.AAC then
            self:append( field.list("aac", data_len, function(self, ba)
                local f_type = self:append( field.uint8("packet_type"
                            , fh.mkdesc(AAC_PACKET_TYPE_STR), fh.mkbrief("T", AAC_PACKET_TYPE_STR)) )

                if f_type.value == AAC_PACKET_TYPE.SEQUENCE_HEADER then
                    self:append( field.string("audio_specific_config", data_len-1) )
                else
                    self:append( field.string("raw", data_len-1) )
                end
            end))
        else
            self:append( field.string("data", data_len) )
        end

    end)
    return f
end

local function field_video_header(video)
    local f = field.list("video_tag_header", nil, function(self, ba)

        local f_frame_type = field.ubits("frame_type", 4, fh.mkdesc(VIDEO_FRAME_TYPE_STR), fh.mkbrief("", VIDEO_FRAME_TYPE_STR))
        local f_codec_id = field.ubits("codec_id", 4, fh.mkdesc(VIDEO_CODEC_ID_STR), fh.mkbrief("", VIDEO_CODEC_ID_STR))
        self:append( field.bit_list("bits", 1, function(self, ba)
            self:append( f_frame_type )
            self:append( f_codec_id )
        end, nil, fh.child_brief))


        if f_codec_id.value == VIDEO_CODEC_ID.AVC then
            local f_avc_packet_type = field.uint8("avc_packet_type"
                        , fh.mkdesc(AVC_PACKET_TYPE_STR), fh.mkbrief("T", AVC_PACKET_TYPE_STR))

            local cb_brief_pts = function(self)
                return string.format("PTS:%d ", video.dts + self.value)
            end
            local f_composition_time = field.int24("composition_time", swap_endian, nil, cb_brief_pts)
            self:append( f_avc_packet_type )
            self:append( f_composition_time )

            video.avc_packet_type = f_avc_packet_type.value
            video.composition_time = f_composition_time.value
        end

        video.frame_type = f_frame_type.value
        video.codec_id = f_codec_id.value
    end, nil, fh.child_brief)
    return f
end
local function field_video(len, video)
    local f = field.list("video", len, function(self, ba)
        local pos = ba:position()
        
        if video.frame_type == VIDEO_FRAME_TYPE.VIDEO_INFO then
            self:append( field.string("video_info", len) )
            return
        end

        if video.codec_id == VIDEO_CODEC_ID.AVC then
            if video.avc_packet_type == 0 then
                self:append( field.string("avc_decoder_configuration_record", len) )
            elseif video.avc_packet_type == 1 then
--[[                
                local codec_h264 = helper.get_codec("h264")
                local nalu_data = ba:peek_bytes(len)
                self:append( codec_h264.field_nalu_header(), ba )
--]]             
                local remain = len - (ba:position() - pos)
                self:append( field.string("nalus", remain) )
            else
                self:append( field.string("data", len) )
            end
            return
        end
        self:append( field.string("data", len) )
    end)
    return f
end

local function field_tag( index )
    local f_tag = field.list(string.format("tag[%d]", index), nil, function(self, ba)

        self:append( field.uint32("previous_tag_size", swap_endian) )

        if ba:length() <= 0 then
            return
        end

        local f_filter = field.ubits("filter", 1)
        local f_type = field.ubits("tag_type", 5, fh.mkdesc(FLV_TYPE_STR), fh.mkbrief("T", FLV_TYPE_STR))

        local f_data_size = field.uint24("data_size", swap_endian, nil, fh.mkbrief("DL"))
        local f_timestamp = field.uint24("timestamp", swap_endian)
        local f_timestamp_ex = field.uint8("timestamp_ex", nil, function(self)
                local dts = f_timestamp.value | (self.value << 24)
                return string.format("DTS:%d ", dts)
            end)
        local f_stream_id = field.uint24("stream_id", swap_endian)

        local f_header = self:append(field.list("header", nil, function(self, ba)

            self:append( field.bit_list("flags", 1, function(self, ba)
                    self:append( field.ubits("reserved", 2) )
                    self:append( f_filter )
                    self:append( f_type )
                end, nil, fh.child_brief))

            self:append( f_data_size )
            self:append( f_timestamp )
            self:append( f_timestamp_ex )
            self:append( f_stream_id )
        end, nil, fh.child_brief))

        local pos = ba:position()

        local ftype = f_type.value

        local dts = f_timestamp.value | (f_timestamp_ex.value << 24)
        local audio = {}
        local video = {}
        video.dts = dts

        if ftype == FLV_TYPE.AUDIO then
            --audio tag header
        end
        if ftype == FLV_TYPE.VIDEO then
            --video tag header
            self:append( field_video_header( video ) )
        end
        if f_filter.value ~= 0 then
            --TODO 
            --EncryptionTagHeader
            --FilterParams
        end

        local data_len = f_data_size.value - (ba:position() - pos)
        self:append( field.select("data", data_len, function()
            if ftype == FLV_TYPE.VIDEO then return field_video(data_len, video) end
            if ftype == FLV_TYPE.AUDIO then return field_audio(data_len, audio) end
            if ftype == FLV_TYPE.SCRIPT then return field_script(data_len) end

            return field.string("data", data_len)
        end))
    end)
    return f_tag
end

local function decode_flv( ba, len )
    flv_summary = flv_summary_t.new()

    local f_flv = field.list("FLV", len, function(self, ba)
        self:append( field_flv_header() )

        local index = 0
        while ba:length() > 0 do
            index = index + 1

            self:append( field_tag(index) )

            local pos = ba:position()
            bi.set_progress_value(pos)
        end

    end)

    return f_flv
end

local function build_summary()
    if not flv_summary then return end

    local function is_fixed_key(k)
        if k == "width" then return true end
        if k == "height" then return true end
        if k == "duration" then return true end
        if k == "filesize" then return true end
        if k == "framerate" then return true end
        return false
    end

    local amf = flv_summary.amf
    
    if amf["width"] and amf["height"] then
        bi.append_summary("resolution", string.format("%.fx%.f", amf["width"], amf["height"]))
    end
    if amf["duration"] then
        local v = amf["duration"]
        bi.append_summary("duration", string.format("%s (%s)", tostring(v), helper.ms2time(v*1000)))
    end
    if amf["framerate"] then
        local v = amf["framerate"]
        bi.append_summary("framerate", string.format("%s", tostring(v)))
    end

    local keys = {}
    for k, _ in pairs(amf) do
        if not is_fixed_key(k) then
            table.insert(keys, k)
        end
    end

    table.sort(keys)

    local tdict = {
        ["videocodecid"] = VIDEO_CODEC_ID_STR,
        ["audiocodecid"] = SOUND_FORMAT_STR,
        ["stereo"] = CHANNEL_STR,
    }

    for _, k in ipairs(keys) do
        local v = amf[k]
        local dict = tdict[k]
        if dict then
            v = dict[v] or "??"
        elseif k == "audiosize" or k == "videosize" then
            v = string.format("%.f (%s)", v, helper.size_format(math.floor(v)))
        else
            local vtype = type(v)
            if vtype == "number" then
                if (v*100) % 100 == 0 then
                    v = string.format("%.f", v)
                else
                    v = tostring(v)
                end
            elseif vtype == "function" then
                v = "??"
            end
        end

        bi.log(string.format("key %s", k))
        bi.append_summary(k, v)
    end

end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_ext = "flv",
    decode = decode_flv,
    build_summary = build_summary,

}

return codec
