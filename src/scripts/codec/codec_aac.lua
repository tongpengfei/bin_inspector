local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

local ADTS_ID = {
    MPEG4 = 0,
    MPEG2 = 1,
}

local ADTS_ID_STR = {
    [ADTS_ID.MPEG4] = "MPEG4",
    [ADTS_ID.MPEG2] = "MPEG2",
}

local ADTS_PROFILE = {
    MAIN = 0, --main profile
    LC = 1,   --low complexity profile
    SSR = 2,  --scalable sampling rate profile
    RESERVED = 3,
}

local ADTS_PROTECT = {
    CRC = 0,
    NOCRC = 1,
}

local ADTS_PROTECT_STR = {
    [ADTS_PROTECT.CRC] = "CRC",
    [ADTS_PROTECT.NOCRC] = "NOCRC",
}

local ADTS_PROFILE_STR = {
    [ADTS_PROFILE.MAIN] = "main",
    [ADTS_PROFILE.LC] = "low complexity profile",
    [ADTS_PROFILE.SSR] = "scalable sampling rate profile",
    [ADTS_PROFILE.RESERVED] = "reserved"
}

local ADTS_PROFILE_BRIEF = {
    [ADTS_PROFILE.MAIN] = "MAIN",
    [ADTS_PROFILE.LC] = "LC",
    [ADTS_PROFILE.SSR] = "SSR",
    [ADTS_PROFILE.RESERVED] = "RESERVED"
}

local ADTS_SAMPLING = {
    [0] = 96000,
    [1] = 88200,
    [2] = 64000,
    [3] = 48000,

    [4] = 44100,
    [5] = 32000,
    [6] = 24000,
    [7] = 22050,

    [8] = 16000,
    [9] = 12000,
    [10] = 11025,
    [11] = 8000,

    [12] = 7350,
    [13] = 0,     --reserved,
    [14] = 0,     --reserved,
    [15] = -1,    --escape value
}

local AAC_CHANNEL = {
    [0] = "Defined in AOT Specifc Config",
    [1] = "1 channel: front-center",
    [2] = "2 channels: front-left, front-right",
    [3] = "3 channels: front-center, front-left, front-right",
    [4] = "4 channels: front-center, front-left, front-right, back-center",
    [5] = "5 channels: front-center, front-left, front-right, back-left, back-right",
    [6] = "6 channels: front-center, front-left, front-right, back-left, back-right, LFE-channel",
    [7] = "8 channels: front-center, front-left, front-right, side-left, side-right, back-left, back-right, LFE-channel",
    [8] = "reserved",  --0x8
    [9] = "reserved",  --0x9
    [10] = "reserved", --0xA
    [11] = "reserved", --0xB
    [12] = "reserved", --0xC
    [13] = "reserved", --0xD
    [14] = "reserved", --0xE
    [15] = "reserved", --0xF
}

local AAC_CHANNEL_COUNT = {
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 4,
    [5] = 5,
    [6] = 6,
    [7] = 8,
}

local ID_SYN_ELE_TYPE = {
    SCE = 0, --single_channel_element
    CPE = 1, --channel_pair_element
    CCE = 2, --coupling_channel_element
    LFE = 3, --lfe_channel_element
    DSE = 4, --data_stream_element
    PCE = 5, --program_config_element
    FIL = 6, --fill_element
    END = 7,
}

local ID_SYN_ELE_STR = {
    [ID_SYN_ELE_TYPE.SCE] = "SCE",
    [ID_SYN_ELE_TYPE.CPE] = "CPE",
    [ID_SYN_ELE_TYPE.CCE] = "CCE",
    [ID_SYN_ELE_TYPE.LFE] = "LFE",
    [ID_SYN_ELE_TYPE.DSE] = "DSE",
    [ID_SYN_ELE_TYPE.PCE] = "PCE",
    [ID_SYN_ELE_TYPE.FIL] = "FIL",
    [ID_SYN_ELE_TYPE.END] = "END",
}

local aac_summary_t = class("aac_summary_t")
function aac_summary_t:ctor()
    self.channels = 0
    self.duration = 0
    self.sample_rate = 0
    self.bitrate = 0
    self.frames = 0

    self.total_frame_len = 0
end
local aac_summary = nil

local cb_desc_frame = function(self)
    local brief = self:get_child_brief()
    return string.format("%s L:%d %s", self.name, self.len, brief)
end

local field_id_syn_ele = function()
    local f = field.ubits("id_syn_ele", 3, fh.mkdesc(ID_SYN_ELE_STR), fh.mkbrief("ELE", ID_SYN_ELE_STR))
    return f
end

local cb_element_brief = function(self)
    local brief = self:get_child_brief()
    return string.format("%sRAWL:%d", brief, self.len)
end

local function field_syn_single_channel_element()

    local f = field.bit_list("single_channel_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )
        --TODO

    end, nil, cb_element_brief)
    return f
end

local function field_syn_channel_pair_element()
    local f = field.bit_list("channel_pair_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )
        --TODO

    end, nil, cb_element_brief)
    return f
end

local function field_syn_coupling_channel_element()
    local f = field.bit_list("coupling_channel_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )
        --TODO

    end, nil, cb_element_brief)
    return f
end

local function field_syn_lfe_channel_element()
    local f = field.bit_list("lfe_channel_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )
        --TODO

    end, nil, cb_element_brief)
    return f
end

local function field_syn_data_stream_element()
    local f = field.bit_list("data_stream_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )
        --TODO

    end, nil, cb_element_brief)
    return f
end

local function field_syn_program_config_element()
    local f = field.bit_list("program_config_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )
        --TODO
    end, nil, cb_element_brief)
    return f
end

local EXT_TYPE = {
    FIL = 0,
    FILL_DATA = 1,
    DATA_ELEMENT = 2,
    DYNAMIC_RANGE = 11,
}

local function field_syn_fill_element()
    local f = field.bit_list("fill_element", nil, function(self, ba)
        self:append( field_id_syn_ele() )

        local count = 0
        local f_count = self:append( field.ubits("count", 4) )
        if f_count.value == 15 then
            local f_count2 = self:append( field.ubits("count2", 8) )
            count = f_count.value + f_count2.value - 1
        end

        if count <= 0 then return end

        --TODO
        while count > 0 do
            local f_extension_type = self:append( field.ubits("extension_type", 4) )
            local etype = f_extension_type.value

            if etype == EXT_TYPE.DYNAMIC_RANGE then

            elseif etype == EXT_TYPE.FILL_DATA then

            elseif etype == EXT_TYPE.DATA_ELEMENT then

            else--if etype == EXT_TYPE.FIL then

            end

            break
           
        end
    end, nil, cb_element_brief)
    return f
end

local function field_syn_end_element()
    local f = field.bit_list("end_element", nil, function(self, ba)
    end)
    return f
end

local syn_ele_fields = {
    [ID_SYN_ELE_TYPE.SCE] = field_syn_single_channel_element,
    [ID_SYN_ELE_TYPE.CPE] = field_syn_channel_pair_element,
    [ID_SYN_ELE_TYPE.CCE] = field_syn_coupling_channel_element,
    [ID_SYN_ELE_TYPE.LFE] = field_syn_lfe_channel_element,
    [ID_SYN_ELE_TYPE.DSE] = field_syn_data_stream_element,
    [ID_SYN_ELE_TYPE.PCE] = field_syn_program_config_element,
    [ID_SYN_ELE_TYPE.FIL] = field_syn_fill_element,
    [ID_SYN_ELE_TYPE.END] = field_syn_end_element,
}

local function field_frame(index)
    local f = field.list(string.format("frame[%d]", index), nil, function(self, ba)
        --test protection
        local protection = ba:peek_uint16() & 0x1
        local hlen = 7
        if protection == 0 then
            hlen = 9
        end

        local f_frame_length = field.ubits("frame_length", 13, nil, cb_brief_frame_length)
        local f_protection = field.ubits("protection_absent", 1, fh.mkdesc(ADTS_PROTECT_STR), fh.mkbrief("PRT", ADTS_PROTECT_STR))
        local f_header = field.bit_list("adts_header", hlen, function(self, ba)
            self:append( field.ubits("syncword", 12) )
            self:append( field.ubits("id", 1, fh.mkdesc(ADTS_ID_STR), fh.mkbrief("ID", ADTS_ID_STR) ) )
            self:append( field.ubits("layer", 2) )
            self:append( f_protection )
            self:append( field.ubits("profile", 2, fh.mkdesc(ADTS_PROFILE_STR), fh.mkbrief("PRF", ADTS_PROFILE_BRIEF) ) )
            local f_sampling = field.ubits("sampling_frequency_index", 4, fh.mkdesc(ADTS_SAMPLING), fh.mkbrief("SMP", ADTS_SAMPLING))
            self:append( f_sampling )
            self:append( field.ubits("private_bit", 1) )
            local f_ch = self:append( field.ubits("channel_configuration", 3, fh.mkdesc(AAC_CHANNEL), fh.mkbrief("CH", AAC_CHANNEL_COUNT )) )
            self:append( field.ubits("origin", 1) )
            self:append( field.ubits("home", 1) )

            self:append( field.ubits("copyright_identification_bit", 1) )
            self:append( field.ubits("copyright_identification_start", 1) )
            self:append( f_frame_length )
            self:append( field.ubits("adts_buffer_fullness", 11) )
            self:append( field.ubits("number_of_raw_data_blocks_in_frame", 2) )

            if f_protection.value == 0 then
                self:append( field.ubits("crc_check", 16) )
            end

            if aac_summary then
                if f_frame_length.len > 7 then
                    aac_summary.total_frame_len = aac_summary.total_frame_len + f_frame_length.value
                end
                if aac_summary.channels == 0 then
                    aac_summary.sample_rate = ADTS_SAMPLING[f_sampling.value] or "??"
                    aac_summary.channels = f_ch.value
                end
            end
        end, nil, fh.child_brief)

        self:append( f_header )


        self:append( field.select("raw_data", f_frame_length.value - hlen, function(self, ba)
                local id_syn_ele = ba:peek_ubits(3)

                local cb_field = syn_ele_fields[id_syn_ele]
                if nil == cb_field then return nil end
                local f = cb_field()
                return f
            end) )
    end, cb_desc_frame)
    return f
end


local function decode_aac( ba, len )
    aac_summary = aac_summary_t.new()

    local f_aac = field.list("AAC", len, function(self, ba)

        --ADIF 0x41 0x44 0x49 0x46
        local peek = ba:peek_uint32()
        if peek == 0x46494441 then
            --TODO parse ADIF
            return
        end

        --ADTS
        local index = 0
        while ba:length() > 0 do
            index = index + 1

            self:append(field_frame(index))

            local pos = ba:position()
            bi.set_progress_value(pos)
        end

        aac_summary.frames = index

    end)

    return f_aac
end

local function build_summary()
    if nil == aac_summary then return end

    local duration = 1
    local bytes_per_frame = 0

    local frames_per_sec = aac_summary.sample_rate/1024
    if aac_summary.frames > 0 then
        bytes_per_frame = aac_summary.total_frame_len / aac_summary.frames / 1000
    end

    local bitrate = math.floor(8 * bytes_per_frame * frames_per_sec + 0.5)
    if frames_per_sec ~= 0 then
        duration = aac_summary.frames / frames_per_sec
    end

    aac_summary.duration = duration
    aac_summary.bitrate = bitrate

    bi.append_summary("channels", tostring(aac_summary.channels))
    bi.append_summary("sample_rate", string.format("%s Hz", aac_summary.sample_rate))
    bi.append_summary("bitrate", string.format("%d Kbps", aac_summary.bitrate))
    bi.append_summary("frames", tostring(aac_summary.frames))
    bi.append_summary("duration", string.format("%s (%.3f secs) ", helper.ms2time(duration*1000), duration))
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_ext = "aac",
    decode = decode_aac,
    build_summary = build_summary,

}

return codec
