require("class")
require("nalu_buf")
local field = require("field")
local helper = require("helper")
local fh = require("field_helper")
local args = nil
local codec_h264 = nil

--rtcp fir nack
--http://www.networksorcery.com/enp/rfc/rfc2032.txt

--rtcp xr
--https://www.rfc-editor.org/rfc/rfc3611

--rtcp rtpfb psfb
--https://www.rfc-editor.org/rfc/rfc4585.html

--RTCP message for Receiver Estimated Maximum Bitrate
--https://datatracker.ietf.org/doc/html/draft-alvestrand-rmcat-remb-03

local dict_stream_nalus = dict_stream_nalus_t.new()

local UDP_NET_EVENT = {
    NULL                     = 0,
    CREATE                   = 1,
    CREATERESPONSE           = 2,
    CLOSE                    = 3,
    DATA                     = 4,
    DATAMSG_0                = 5,
    UNRELIABLEDATA           = 6,
    HEARTBEAT                = 7,
    HEARTBEATRESPONSE        = 8,
    MODIFYUDPSERVERVERSION   = 9,
    DATAMSG_1                = 10,
    DETECTNETLINK            = 11,
    DETECTNETLINKRESPONSE    = 12,
    DETECTNTP                = 13,
    DETECTNTPRESPONSE        = 14,
}

local UDP_NET_EVENT_STR = {
    [UDP_NET_EVENT.NULL]                   = "NULL",
    [UDP_NET_EVENT.CREATE]                 = "CREATE",
    [UDP_NET_EVENT.CREATERESPONSE]         = "CREATERESPONSE",
    [UDP_NET_EVENT.CLOSE]                  = "CLOSE",
    [UDP_NET_EVENT.DATA]                   = "DATA",
    [UDP_NET_EVENT.DATAMSG_0]              = "DATAMSG_0",
    [UDP_NET_EVENT.UNRELIABLEDATA]         = "UNRELIABLEDATA",
    [UDP_NET_EVENT.HEARTBEAT]              = "HEARTBEAT",
    [UDP_NET_EVENT.HEARTBEATRESPONSE]      = "HEARTBEATRESPONSE",
    [UDP_NET_EVENT.MODIFYUDPSERVERVERSION] = "MODIFYUDPSERVERVERSION",
    [UDP_NET_EVENT.DATAMSG_1]              = "DATAMSG_1",
    [UDP_NET_EVENT.DETECTNETLINK]          = "DETECTNETLINK",
    [UDP_NET_EVENT.DETECTNETLINKRESPONSE]  = "DETECTNETLINKRESPONSE",
    [UDP_NET_EVENT.DETECTNTP]              = "DETECTNTP",
    [UDP_NET_EVENT.DETECTNTPRESPONSE]      = "DETECTNTPRESPONSE",
}

local XR_BLOCK_TYPE = {
    LOSS_RLE                = 1,
    DUPLICATE_RLE           = 2,
    PACKET_RECEIPT_TIMES    = 3,
    RECEIVER_REFERENCE_TIME = 4,
    DLRR                    = 5,
    STATISTICS_SUMMARY      = 6,
    VOIP_METRICS            = 7,
}

local XR_BLOCK_TYPE_STR = {
    [XR_BLOCK_TYPE.LOSS_RLE]                = "LossRLE",
    [XR_BLOCK_TYPE.DUPLICATE_RLE]           = "DuplicateRLE",
    [XR_BLOCK_TYPE.PACKET_RECEIPT_TIMES]    = "PacketReceiptTimes",
    [XR_BLOCK_TYPE.RECEIVER_REFERENCE_TIME] = "ReceiverReferenceTime",
    [XR_BLOCK_TYPE.DLRR]                    = "DLRR",
    [XR_BLOCK_TYPE.STATISTICS_SUMMARY]      = "StatisticsSummary",
    [XR_BLOCK_TYPE.VOIP_METRICS]            = "VoIPMetrics",
}

local rtp_hdr_t = class("rtp_hdr_t")
function rtp_hdr_t:ctor()
    self.ver = 0
    self.padding = 0
    self.extension = 0
    self.cc = 0
    self.marker = 0
    self.pt = 0
    self.seq = 0
    self.timestamp = 0
    self.ssrc = 0
    self.csrc = nil
end

local rtp_ext_t = class("rtp_ext_t")
function rtp_ext_t:ctor()
    self.profile = 0
    self.length = 0
    self.ext = {}
end

local rtcp_hdr_t = class("rtcp_hdr_t")
function rtcp_hdr_t:ctor()
    self.ver = 0
    self.padding = 0
    self.rc = 0
    self.pt = 0
    self.length = 0
end

--[[
The sender report header:
 0               1               2               3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|    RC   |   PT=SR=200   |             length L          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         SSRC of sender                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

The sender information block:
 0               1               2               3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|            NTP timestamp, most significant word NTS           |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|             NTP timestamp, least significant word             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       RTP timestamp RTS                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                   sender's packet count SPC                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    sender's octet count SOC                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

The receiver report blocks:
 0               1               2               3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                 SSRC_1 (SSRC of first source)                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|fraction lost F|      cumulative number of packets lost C      |
-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|         extended highest sequence number received  EHSN       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    inter-arrival jitter J                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          last SR LSR                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    delay since last SR DLSR                   |
+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
|                 SSRC_2 (SSRC of second source)                |
:                               ...                             :
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

http://www.networksorcery.com/enp/rfc/rfc2032.txt
5.2.1.  Full INTRA-frame Request (FIR) packet
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|   MBZ   |  PT=RTCP_FIR  |           length              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                              SSRC                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

5.2.2.  Negative ACKnowledgements (NACK) packet
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|V=2|P|   MBZ   | PT=RTCP_NACK  |           length              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                              SSRC                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|              FSN              |              BLP              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

--]]

local rtcp_fir_t = class("rtcp_fir_t", rtcp_hdr_t)
function rtcp_fir_t:ctor()
    self.ssrc = 0
end

local rtcp_nack_t = class("rtcp_nack_t", rtcp_hdr_t)
function rtcp_nack_t:ctor()
    self.ssrc = 0
    self.fsn = 0
    self.blp = {}
end

local rtcp_sr_block_t = class("rtcp_sr_block_t")
function rtcp_sr_block_t:ctor()
    self.ntp_msw = 0
    self.ntp_lsw = 0
    self.rts = 0
    self.send_packet = 0
    self.send_bytes = 0
end

local rtcp_rr_block_t = class("rtcp_rr_block_t")
function rtcp_rr_block_t:ctor()
    self.ssrc = 0
    self.fraction_lost = 0
    self.cumulative_lost = 0

    self.seq_cycles = 0
    self.highest_seq = 0

    self.jitter = 0
    self.last_sr = 0
    self.delay_since_last_sr = 0
end

local rtcp_sr_t = class("rtcp_sr_t", rtcp_hdr_t)
function rtcp_sr_t:ctor()
    self.ssrc = 0
    self.sr_block = nil
end

local rtcp_rr_t = class("rtcp_rr_t", rtcp_hdr_t)
function rtcp_rr_t:ctor()
    self.ssrc = 0
    self.rr_blocks = {}
end

local rtcp_rtpfb_t = class("rtcp_rtpfb_t", rtcp_hdr_t)
function rtcp_rtpfb_t:ctor()
    self.ssrc = 0
    self.media_ssrc = 0
end

local rtcp_psfb_t = class("rtcp_psfb_t", rtcp_hdr_t)
function rtcp_psfb_t:ctor()
    self.ssrc = 0
    self.media_ssrc = 0
end

local rtcp_xr_t = class("rtcp_xr_t", rtcp_hdr_t)
function rtcp_xr_t:ctor()
    self.ssrc = 0
end


local function field_rtp_hdr(rtp_hdr)
    rtp_hdr = rtp_hdr or rtp_hdr_t.new()

    local f = field.bit_list("rtp_hdr", nil, function(self, ba)
        local f_ver = self:append( field.ubits("version", 2) )
        local f_padding = self:append( field.ubits("padding", 1, nil, fh.mkbrief_v("P")) )
        local f_extension = self:append( field.ubits("extension", 1, nil, fh.mkbrief_v("X")) )
        local f_cc = self:append( field.ubits("cc", 4, nil, fh.mkbrief_v("CC")) )

        local f_marker = self:append( field.ubits("marker", 1, nil, fh.mkbrief_v("M")) )
        local f_pt = self:append( field.ubits("pt", 7, nil, fh.mkbrief_v("PT")) )
        local f_seq = self:append( field.ubits("seq", 16, nil, fh.mkbrief_v("SEQ")) )

        local f_timestamp = self:append( field.ubits("timestamp", 32, nil, fh.mkbrief_v("TS")) )
        local f_ssrc = self:append( field.ubits("ssrc", 32, nil, fh.mkbrief_v("SSRC")) )

        rtp_hdr.ver = f_ver.value
        rtp_hdr.padding = f_padding.value
        rtp_hdr.extension = f_extension.value
        rtp_hdr.cc = f_cc.value
        rtp_hdr.marker = f_marker.value
        rtp_hdr.pt = f_pt.value
        rtp_hdr.seq = f_seq.value
        rtp_hdr.timestamp = f_timestamp.value
        rtp_hdr.ssrc = f_ssrc.value

        if f_cc.value > 0 then
            rtp_hdr.csrc = {}
        end

        for i=1, f_cc.value do
            local f_csrc = self:append( field.ubits("csrc", 32) )
            table.insert( rtp_hdr.csrc, f_csrc.value )
        end
    end, nil, fh.child_brief)
    return f
end

local function field_rtp_extension(rtp_ext)
    rtp_ext = rtp_ext or rtp_ext_t.new()
    local f = field.list("rtp_ext", nil, function(self, ba)
        local swap_endian = true
        local u16 = ba:peek_uint16(true)
        if u16 == 0xBEDE then
            --one byte header
            local f_profile = self:append( field.uint16("profile", swap_endian) )
            local f_length = self:append( field.uint16("length", swap_endian) )

            rtp_ext.profile = f_profile.value
            rtp_ext.length = f_length.value

            local index = 0
            local pos = ba:position()
            local ext_len = f_length.value * 4
            --self:append( field.string("ext", ext_len) )

            local remain = ext_len
            while remain > 0 do

                self:append( field.list(string.format("ext[%d]", index), nil, function(self, ba)
                    local f_id = field.ubits("ID", 4, nil, fh.mkbrief_v("ID"))
                    local f_len = field.ubits("L", 4, nil, fh.mkbrief_v("L"))

                    self:append( field.bit_list("hdr", 1, function(self, ba)
                        self:append(f_id)
                        self:append(f_len)
                    end, nil, fh.child_brief))

                    if f_id.value ~= 0 then
                        self:append( field.string("data", f_len.value + 1) )
                    end
                end))

                remain = ext_len - (ba:position() - pos)
                index = index + 1
            end
        else
            --TODO two byte header

        end

    end)
    return f
end

local function field_rtcp_hdr( rtcp_hdr )
    local f = field.bit_list("rtcp_hdr", nil, function(self, ba)
        local f_ver = self:append( field.ubits("version", 2) )
        local f_padding = self:append( field.ubits("padding", 1, nil, fh.mkbrief_v("P")) )
        local f_rc= self:append( field.ubits("rc", 5, nil, fh.mkbrief_v("RC")) )
        local f_pt = self:append( field.ubits("pt", 8, nil, fh.mkbrief_v("T")) )
        local f_length = self:append( field.ubits("length", 16, nil, fh.mkbrief_v("L")) )

        rtcp_hdr.ver = f_ver.value
        rtcp_hdr.padding = f_padding.value
        rtcp_hdr.rc = f_rc.value
        rtcp_hdr.pt = f_pt.value
        rtcp_hdr.length = f_length.value
    end, nil, fh.child_brief)
    return f
end

local function field_nalu(rtp_hdr, key, len)
    local NALU_TYPE = codec_h264.NALU_TYPE
    local NALU_TYPE_STR = codec_h264.NALU_TYPE_STR

    local f_nalu_hdr = codec_h264.field_nalu_header()

    local cb_brief = function(self)
        local stype = NALU_TYPE_STR[f_nalu_hdr.nalu_type] or "??"
        return string.format("%s VLEN:%d ", stype, len)
    end

    local f = field.list("NALU", len, function(self, ba)
        local pos = ba:position()

        local i_nalu_hdr = ba:peek_uint8()
        self:append( f_nalu_hdr )

        local f_ebsp = self:append( field.string( "ebsp", len-1) )

        --local stype = NALU_TYPE_STR[f_nalu_hdr.nalu_type]
        --if nil ~= stype then
            local nalu_buf = dict_stream_nalus:get(key)
            nalu_buf:append( rtp_hdr.seq, f_ebsp, i_nalu_hdr, true)
        --end
    end, nil, cb_brief)
    return f
end

local function field_nalu_stap(rtp_hdr, key, len, is_stap_b)
    local NALU_TYPE = codec_h264.NALU_TYPE
    local NALU_TYPE_STR = codec_h264.NALU_TYPE_STR

    local cb_brief = function(self)
        return string.format("%s VLEN:%d ", self.name, len)
    end

    local name = nil
    if true == is_stap_b then
        name = NALU_TYPE_STR[NALU_TYPE.STAP_B]
    else
        name = NALU_TYPE_STR[NALU_TYPE.STAP_A]
    end

    local f = field.list(name, len, function(self, ba)
        local pos = ba:position()

        self:append( codec_h264.field_nalu_header() )

        if true == is_stap_b then
            self:append( field.uint16("DON", true) )
        end

        local index = 0
        local remain = len
        while remain > 0 do

            local stap_len = ba:peek_uint16(true)
            self:append( field.list(string.format("nalu[%d]", index), stap_len, function(self, ba)

                local f_size = self:append( field.uint16("size", true) )

                local nalu_len = f_size.value
                local remain2 = len - (ba:position() - pos)
                if remain2 < f_size.value then
                    nalu_len = remain2
                    bi.log(string.format("%s reset nalu_len %d => %d", self.name, f_size.value, remain2))
                end

                local i_nalu_hdr = ba:peek_uint8()
                local f_nalu_hdr = self:append( codec_h264.field_nalu_header() )
                --local f_ebsp = self:append( field.string( "ebsp", f_size.value-1) )
                local f_ebsp = self:append( field.string( "ebsp", nalu_len-1) )

                local nalu_buf = dict_stream_nalus:get(key)
                nalu_buf:append( rtp_hdr.seq, f_ebsp, i_nalu_hdr, true)
            end, nil, fh.child_brief))
            index = index + 1
            remain = len - (ba:position() - pos)
        end

    end, nil, cb_brief)
    return f
end

local function field_nalu_stap_a(rtp_hdr, key, len)
    return field_nalu_stap(rtp_hdr, key, len, false)
end

local function field_nalu_stap_b(rtp_hdr, key, len)
    return field_nalu_stap(rtp_hdr, key, len, true)
end

local function field_nalu_fu_a(rtp_hdr, key, len)
    local NALU_TYPE = codec_h264.NALU_TYPE
    local NALU_TYPE_STR = codec_h264.NALU_TYPE_STR

    local f_nalu_hdr = codec_h264.field_nalu_header()
    local f_fu_hdr = codec_h264.field_fu_header()

    local cb_brief = function(self)
        local stype = ""
        local fu = f_fu_hdr.fu
        if fu.S == 1 then
            stype = string.format("FUA:S %s", NALU_TYPE_STR[fu.T] or "??")
        elseif fu.E == 1 then
            stype = string.format("FUA:E %s", NALU_TYPE_STR[fu.T] or "??")
        else
            stype = string.format("FUA %s", NALU_TYPE_STR[fu.T] or "??")
        end
        return string.format("%s VLEN:%d ", stype, len)
    end

    local f = field.list("FU-A", len, function(self, ba)
        local pos = ba:position()
        local i_nalu_hdr = ba:peek_uint8()

        self:append( f_nalu_hdr )
        self:append( f_fu_hdr )

        local remain = len - (ba:position() - pos)
        if remain <= 0 then return end
        local f_ebsp = self:append(field.string("ebsp", remain))

        local is_new_nalu = false
        if nil == f_fu_hdr then
            is_new_nalu = true
        elseif 1 == f_fu_hdr.fu.S then
            is_new_nalu = true

            i_nalu_hdr = i_nalu_hdr & 0xE0 | f_fu_hdr.fu.T
        end

        local nalu_buf = dict_stream_nalus:get(key)
        nalu_buf:append( rtp_hdr.seq, f_ebsp, i_nalu_hdr, is_new_nalu )

    end, nil, cb_brief)
    return f
end

local function field_rtp_h264(rtp_hdr, len)
    local f = field.select("h264", len, function(self, ba)
        local NALU_TYPE = codec_h264.NALU_TYPE
        local NALU_TYPE_STR = codec_h264.NALU_TYPE_STR

        local f_fu_hdr = nil

        local sip = 0
        local dip = 0
        local sport = 0
        local dport = 0
        local ssrc = rtp_hdr.ssrc
        if args then
            if args.ipv4_hdr then
                sip = args.ipv4_hdr.saddr
                dip = args.ipv4_hdr.daddr
            end

            if args.udp_hdr then
                sport = args.udp_hdr.source
                dport = args.udp_hdr.dest
            end
        end

        --bi.log(string.format("video %s:%d:%s => %s:%d", helper.n2ip(sip), sport, ssrc, helper.n2ip(dip), dport))

        local key_src = string.format("%s_%d_%d", helper.n2ip(sip), sport, ssrc)
        local key_dst = string.format("%s_%d", helper.n2ip(dip), dport)
        local key_stream = string.format("%s-%s", key_src, key_dst)

        local i_nalu_hdr = ba:peek_uint8()
        local nalu_type = i_nalu_hdr & 0x1F
        local f_video = nil
        if nalu_type == NALU_TYPE.FU_A then
            f_video = field_nalu_fu_a(rtp_hdr, key_stream, len)
        elseif nalu_type == NALU_TYPE.STAP_A then
            f_video = field_nalu_stap_a(rtp_hdr, key_stream, len)
        elseif nalu_type == NALU_TYPE.STAP_B then
            f_video = field_nalu_stap_b(rtp_hdr, key_stream, len)
        else
            f_video = field_nalu(rtp_hdr, key_stream, len)
        end

        --setup context menu
        f_video.cb_context_menu = function(self, menu)
            if dict_stream_nalus.nstream > 0 then
                menu:add_action("Extract all h264 streams", function()
                    for k, nalu_buf in pairs(dict_stream_nalus.stream_nalus) do
                        bi.log(string.format("save h264 stream %s", k))
                        nalu_buf:save(string.format("%s/%s.h264", bi.get_tmp_dir(), k))
                    end
                    --bi.message_box(string.format("save ok"))
                end)
            end

            if nil ~= key_stream then
        		menu:add_action(string.format("Extract h264 %s -> %s", key_src, key_dst), function()
                    local nalu_buf = dict_stream_nalus:get(key_stream)
                    if nil == nalu_buf then return end
                    local path = bi.save_as(string.format("%s/%s.h264", bi.get_tmp_dir(), key_stream))
                    if nil == path or "" == path then return end
                    bi.log(string.format("save_as %s", path))
                    nalu_buf:save(path)

                    bi.message_box(string.format("save ok:%s", path))
        		end)
            end
        end
        return f_video
    end)
    return f
end

local function field_rtp_video(len)
    local f = field.list("payload_video", len, function(self, ba)

        local pos = ba:position()
        local rtp_hdr = rtp_hdr_t.new()
        self:append( field_rtp_hdr(rtp_hdr) )

        if 1 == rtp_hdr.extension then
            self:append( field_rtp_extension() )
        end

        local remain = len - (ba:position() - pos)
        if remain <= 0 then return end

        self:append( field_rtp_h264(rtp_hdr, remain) )
    end, nil, fh.child_brief)
    return f
end

local function field_rtcp_sr(len)
    local f = field.list("rtcp_sr", len, function(self, ba)
        local swap_endian = true
        local sr = rtcp_sr_t.new()
        self:append( field_rtcp_hdr(sr) )

        local f_ssrc = self:append( field.uint32("ssrc", swap_endian) )
        sr.ssrc = f_ssrc.value

        local f_ntp_msw = self:append( field.uint32("ntp_msw", swap_endian) )
        local f_ntp_lsw = self:append( field.uint32("ntp_lsw", swap_endian, function(self)
                local ntp = (f_ntp_msw.value << 32) | self.value
                local ms = bi.ntp2ms(ntp)
                return string.format("%s %s: %u ms:%d %s ", self.type, self.name, self.value, ms, helper.ms2date(ms))
            end) )

        local f_rts = self:append(field.uint32("rts", swap_endian))
        local f_send_packet = self:append(field.uint32("send_packet", swap_endian))
        local f_send_bytes = self:append(field.uint32("send_bytes", swap_endian))

        local block = rtcp_sr_block_t.new()
        block.ntp_msw = f_ntp_msw.value
        block.ntp_lsw = f_ntp_lsw.value
        block.rts = f_rts.value
        block.send_packet = f_send_packet.value
        block.send_bytes = f_send_bytes.value

        sr.sr_block = block
    end)
    return f
end

local function field_rtcp_rr(len)
    local f = field.list("rtcp_rr", len, function(self, ba)
        local rr = rtcp_rr_t.new()
        self:append( field_rtcp_hdr(rr) )

        local swap_endian = true
        self:append( field.uint32("ssrc", swap_endian) )

        if rr.rc <= 0 then return end

        for i=1, rr.rc do
            self:append( field.list(string.format("rr_block[%d]", i), nil, function(self, ba)

                local f_ssrc = self:append(field.uint32("ssrc", swap_endian))
                local f_fraction_lost = self:append(field.uint8("fraction_lost"))
                local f_cumulative_lost = self:append(field.uint24("cumulative_lost", swap_endian))

                local f_seq_cycles = self:append(field.uint16("seq_cycles", swap_endian))
                local f_highest_seq = self:append(field.uint16("highest_seq_received", swap_endian))

                local f_jitter = self:append(field.uint32("jitter", swap_endian))
                local f_last_sr = self:append(field.uint32("last_sr", swap_endian))
                local f_delay_since_last_sr = self:append(field.uint32("delay_since_last_sr", swap_endian))

                local block = rtcp_rr_block_t.new()
                block.ssrc = f_ssrc.value
                block.fraction_lost = f_fraction_lost.value
                block.cumulative_lost = f_cumulative_lost.value

                block.seq_cycles = f_seq_cycles.value
                block.highest_seq = f_highest_seq.value

                block.jitter = f_jitter.value
                block.last_sr = f_last_sr.value
                block.delay_since_last_sr = f_delay_since_last_sr.value
                table.insert(rr.rr_blocks, block)
            end))
        end

    end, nil, fh.child_brief)
    return f
end

local function field_rtcp_sdes(len)
end

local function field_rtcp_bye(len)
end

local function field_rtcp_app(len)
end

--[[
--Common Packet Format for Feedback Messages
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |V=2|P|   FMT   |       PT      |          length               |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                  SSRC of packet sender                        |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                  SSRC of media source                         |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   :            Feedback Control Information (FCI)                 :
   :                                                               :

Transport Layer Feedback Message
   0:    unassigned
   1:    Generic NACK
   2-30: unassigned
   31:   reserved for future expansion of the identifier number space

-- FCI NACK: PT=RTPFB and FMT=1
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |            PID                |             BLP               |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

-- Slice Loss Indication (SLI) PT=PSFB and FMT=2
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |            First        |        Number           | PictureID |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

-- Receiver Estimated Max Bitrate (REMB)
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |V=2|P| FMT=15  |   PT=206      |             length            |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                  SSRC of packet sender                        |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |                  SSRC of media source                         |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |  Unique identifier 'R' 'E' 'M' 'B'                            |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |  Num SSRC     | BR Exp    |  BR Mantissa                      |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |   SSRC feedback                                               |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |  ...                                                          |

Payload-Specific Feedback Messages
      0:     unassigned
      1:     Picture Loss Indication (PLI)  //https://www.rfc-editor.org/rfc/rfc4585.html#section-6.3.1
      2:     Slice Loss Indication (SLI)    //https://www.rfc-editor.org/rfc/rfc4585.html#section-6.3.2
      3:     Reference Picture Selection Indication (RPSI) //https://www.rfc-editor.org/rfc/rfc4585.html#section-6.3.3
      4-14:  unassigned
      15:    Application layer FB (AFB) message //
      16-30: unassigned
      31:    reserved for future expansion of the sequence number space

--]]
local RTPFB_FMT = {
    NACK = 1,
    TCC = 15, --transport cc
}

local RTPFB_FMT_STR = {
    [RTPFB_FMT.NACK] = "NACK",
    [RTPFB_FMT.TCC] = "TCC"
}

local PSFB_FMT = {
    PLI  = 1, --picture loss indication
    SLI  = 2, --slice loss indication
    RPSI = 3, --reference picture selection indication
    AFB  = 15 --application layer fb
}
local PSFB_FMT_STR = {
    [PSFB_FMT.PLI]  = "PLI",
    [PSFB_FMT.SLI]  = "SLI",
    [PSFB_FMT.RPSI] = "RPLI",
    [PSFB_FMT.AFB]  = "AFB",
}

local function field_psfb_fci_pli(len)
    local f = field.list("PLI", len, function(self, ba)
        --PLI no parameters
    end)
    return f
end

local function field_psfb_fci_sli(len)
    local f = field.list("SLI", len, function(self, ba)
        for i=1, len do
            self:append( field.bit_list(string.format("SLI[%d]", i), nil, function(self, ba)
                self:append( field.ubits("first", 13) )
                self:append( field.ubits("number", 13) )
                self:append( field.ubits("picture_id", 6) )
            end))
        end
    end)
    return f
end

local function field_psfb_fci_afb(len)
    local f_num_ssrc = field.ubits("num_ssrc", 8)
    local f_br_exp = field.ubits("br_exp", 6)
    local f_br_mantissa = field.ubits("br_mantissa", 18)

    local function cb_brief_remb()
        local remb = f_br_mantissa.value * (2 ^ f_br_exp.value)
        return string.format("REMB:%d ", remb)
    end

    local f = field.list("AFB", len, function(self, ba)
        self:append( field.string("identifier", 4, fh.str_desc) )

        self:append( field.bit_list("bits", nil, function(self, ba)
            self:append( f_num_ssrc )
            self:append( f_br_exp )
            self:append( f_br_mantissa )
        end))

        for i=1, f_num_ssrc.value do
            self:append(field.uint32(string.format("ssrc_feedback[%d]", i), true))
        end
    end, nil, cb_brief_remb)
    return f
end

local function field_psfb_fci_unknown(len)
    local f = field.list("fci_unknown", len, function(self, ba)
        self:append(field.string("unknown", len))
    end)
    return f
end

local function field_rtpfb_fci_nack(len)
    local f = field.list("NACK", len, function(self, ba)
        local swap_endian = true
        local f_pid = self:append(field.uint16("PID", swap_endian))
        self:append(field.bit_list("BLP", 2, function(self, ba)
            for i=0, 15 do
                local v = ba:peek_ubits(1)
                if 1 == v then
                    local loss_pid = f_pid.value+(16-i)
                    local function cb_brief_loss(self)
                        return string.format("%d", loss_pid)
                    end
                    self:append(field.ubits(string.format("BLP[%d] LOSS %d", i, loss_pid), 1, nil, cb_brief_loss))
                else
                    self:append(field.ubits(string.format("BLP[%d]", i)))
                end
            end
        end, nil, fh.child_brief))
    end)
    return f
end

local dict_rtpfb_fci_field = {
    [RTPFB_FMT.NACK] = field_rtpfb_fci_nack,
    [RTPFB_FMT.TCC] = field_rtpfb_fci_tcc,
}

local dict_psfb_fci_field = {
    [PSFB_FMT.PLI]  = field_psfb_fci_pli,
    [PSFB_FMT.SLI]  = field_psfb_fci_sli,
    [PSFB_FMT.RPSI] = nil,
    [PSFB_FMT.AFB]  = field_psfb_fci_afb,
}

local function field_rtcp_rtpfb(len)
    local f = field.list("rtcp_rtpfb", len, function(self, ba)
        local pos = ba:position()
        local rtpfb = rtcp_rtpfb_t.new()
        self:append( field_rtcp_hdr(rtpfb) )

        local swap_endian = true
        local f_ssrc = self:append( field.uint32("ssrc", swap_endian) )
        rtpfb.ssrc = f_ssrc.value

        local f_media_ssrc = self:append( field.uint32("media_ssrc", swap_endian))
        rtpfb.media_ssrc = f_media_ssrc.value

        local remain = len - (ba:position() - pos)
        if remain <= 0 then return end

        local fmt = rtpfb.rc
        local fcb = dict_rtpfb_fci_field[fmt] or field_psfb_fci_unknown
        self:append( fcb(remain) )

        remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append( field.string("unparsed", remain) )
        end
    end, nil, fh.child_brief)
    return f
end

local function field_rtcp_psfb(len)
    local f = field.list("rtcp_psfb", len, function(self, ba)
        local pos = ba:position()
        local psfb = rtcp_psfb_t.new()
        self:append( field_rtcp_hdr(psfb) )

        local swap_endian = true
        local f_ssrc = self:append( field.uint32("ssrc", swap_endian) )
        psfb.ssrc = f_ssrc.value

        local f_media_ssrc = self:append( field.uint32("media_ssrc", swap_endian))
        psfb.media_ssrc = f_media_ssrc.value

        local remain = len - (ba:position() - pos)
        if remain <= 0 then return end

        local fmt = psfb.rc
        local fcb = dict_psfb_fci_field[fmt] or field_psfb_fci_unknown
        self:append( fcb(remain) )

        remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append( field.string("unparsed", remain) )
        end
    end, nil, fh.child_brief)
    return f
end

local function field_rtcp_fir(len)
    local f = field.list("rtcp_fir", len, function(self, ba)
        local fir = rtcp_fir_t.new()
        self:append( field_rtcp_hdr(fir) )

        local swap_endian = true
        local f_ssrc = self:append( field.uint32("ssrc", swap_endian) )
        fir.ssrc = f_ssrc.value
    end)
    return f
end

local function field_rtcp_nack(len)
    local f = field.list("rtcp_nack", len, function(self, ba)
        local nack = rtcp_nack_t.new()
        self:append( field_rtcp_hdr(nack) )

        local swap_endian = true
        local f_ssrc = self:append( field.uint32("ssrc", swap_endian) )
        self:append( field_rtpfb_fci_nack(16) )

        nack.ssrc = f_ssrc.value
    end)
    return f
end

local function field_rtpfb_fci_tcc(len)
    --TODO
end

--[[
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |     BT=4      |   reserved    |       block length = 2        |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |              NTP timestamp, most significant word             |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   |             NTP timestamp, least significant word             |
   +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
--]]
local function field_rtcp_xr_receiver_reference_time(len)
    local f = field.list("receiver_reference_time", len, function(self, ba)
        local swap_endian = true
        self:append(field.uint8("block_type", fh.mkdesc(XR_BLOCK_TYPE_STR), fh.mkbrief_v("BT", XR_BLOCK_TYPE_STR)))
        self:append(field.uint8("reserved"))
        self:append(field.uint16("block_length", swap_endian))

        local f_ntp_msw = self:append( field.uint32("ntp_msw", swap_endian) )
        local f_ntp_lsw = self:append( field.uint32("ntp_lsw", swap_endian, function(self)
                local ntp = (f_ntp_msw.value << 32) | self.value
                local ms = bi.ntp2ms(ntp)
                return string.format("%s %s: %u ms:%d %s ", self.type, self.name, self.value, ms, helper.ms2date(ms))
            end) )
    end)
    return f
end

--[[
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |     BT=5      |   reserved    |         block length          |
 +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
 |                 SSRC_1 (SSRC of first receiver)               | sub-
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ block
 |                         last RR (LRR)                         |   1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                   delay since last RR (DLRR)                  |
 +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
 |                 SSRC_2 (SSRC of second receiver)              | sub-
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+ block
 :                               ...                             :   2
 +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
--]]
local function field_rtcp_xr_dlrr(len)
    local f = field.list("dlrr", len, function(self, ba)
        local swap_endian = true
        self:append(field.uint8("block_type", fh.mkdesc(XR_BLOCK_TYPE_STR), fh.mkbrief_v("BT", XR_BLOCK_TYPE_STR)))
        self:append(field.uint8("reserved"))
        local f_len = self:append(field.uint16("block_length", swap_endian))
        if f_len.value <= 0 then return end
        local nblock = f_len.value / 3

        for i=1, nblock do
            self:append( field.list(string.format("receiver[%d]", i), nil, function(self, ba)
                self:append( field.uint32("ssrc", swap_endian, nil, fh.mkbrief_v("SSRC")) )
                self:append( field.uint32("last_rr", swap_endian, nil, fh.mkbrief_v("LRR")) )
                self:append( field.uint32("delay_since_last_rr", swap_endian, nil, fh.mkbrief_v("DLRR")) )
            end))
        end
    end)
    return f
end

local function field_rtcp_xr_block_unknown(len)
    local f = field.list("unknown", len, function(self, ba)
        local swap_endian = true
        self:append(field.uint8("block_type", fh.mkdesc(XR_BLOCK_TYPE_STR), fh.mkbrief_v("BT", XR_BLOCK_TYPE_STR)))

        self:append( field.string("unknown", len-1) )
    end)
    return f

end

local dict_rtcp_xr_field = {
    [XR_BLOCK_TYPE.LOSS_RLE]                = nil,
    [XR_BLOCK_TYPE.DUPLICATE_RLE]           = nil,
    [XR_BLOCK_TYPE.PACKET_RECEIPT_TIMES]    = nil,
    [XR_BLOCK_TYPE.RECEIVER_REFERENCE_TIME] = field_rtcp_xr_receiver_reference_time,
    [XR_BLOCK_TYPE.DLRR]                    = field_rtcp_xr_dlrr,
    [XR_BLOCK_TYPE.STATISTICS_SUMMARY]      = nil,
    [XR_BLOCK_TYPE.VOIP_METRICS]            = nil,
}

local function field_rtcp_xr(len)
    local f = field.list("rtcp_xr", len, function(self, ba)
        local pos = ba:position()
        local xr = rtcp_xr_t.new()
        self:append( field_rtcp_hdr(xr) )

        local swap_endian = true
        local f_ssrc = self:append( field.uint32("ssrc", swap_endian) )
        xr.ssrc = f_ssrc.value

        local remain = len - (ba:position() - pos)

        local block_type = ba:peek_uint8()
        local fcb = dict_rtcp_xr_field[block_type] or field_rtcp_xr_block_unknown
        self:append( fcb(remain) )

        remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append( field.string("unparsed", remain) )
        end
    end, nil, fh.child_brief)
    return f
end

local dict_pt = {
    [96] = field_rtp_video,
    [107] = field_rtp_video,

    [192] = field_rtcp_fir,
    [193] = field_rtcp_nack,

    [200] = field_rtcp_sr,
    [201] = field_rtcp_rr,
    [202] = field_rtcp_sdes,
    [203] = field_rtcp_bye,
    [204] = field_rtcp_app,
    [205] = field_rtcp_rtpfb,
    [206] = field_rtcp_psfb,
    [207] = field_rtcp_xr,
}

--handler( len )
local function set_payload_handler( pt, handler )
    dict_pt[pt] = handler
end

local function decode_rtp( ba, len, rtp_args )
    args = rtp_args

    if nil == codec_h264 then
        codec_h264 = helper.get_codec("h264")
    end

    local f = field.list("rtp", len, function(self, ba)
        local pos = ba:position()

        local u16 = ba:peek_uint16()
        local pt = (u16 >> 8) & 0x7F
        local pt_rtcp = (u16 >> 8) & 0xFF
        local f = dict_pt[pt] or dict_pt[pt_rtcp]

        if nil ~= f then
            self:append( f(len) )
        else
            --bi.log( string.format("cant find u16:0x%x pt:%s pt_rtcp:%s", u16, tostring(pt), tostring(pt_rtcp)) )
            local rtcp_hdr = rtcp_hdr_t.new()
            self:append( field_rtcp_hdr(rtcp_hdr) )
        end

        local remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append(field.string("remain", remain))
        end
    end, nil, fh.child_brief)

    return f
end

local function build_summary()
end

local function clear()
    if dict_stream_nalus then
        dict_stream_nalus:clear()
    end
    dict_seq = {}
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "Rtp_Rtcp",
    file_ext = "rtp rtcp",
    decode = decode_rtp,
    clear = clear,

    build_summary = build_summary,

    set_payload_handler = set_payload_handler,

    rtp_hdr_t = rtp_hdr_t,
    field_rtp_hdr = field_rtp_hdr,
    field_rtp_extension = field_rtp_extension,
    field_rtp_h264 = field_rtp_h264,
}

return codec
