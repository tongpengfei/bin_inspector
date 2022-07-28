require("class")
local field = require("field")
local helper = require("helper")
local fh = require("field_helper")
local dict_parser = require("pcap_port_parser")

--https://github.com/pcapng/pcapng/blob/master/draft-ietf-opsawg-pcap.md
--https://github.com/pcapng/pcapng/blob/master/draft-ietf-opsawg-pcapng.md
--https://www.winpcap.org/ntar/draft/PCAP-DumpFileFormat.html

local MAGIC_PCAP_LE = 0xA1B2C3D4
local MAGIC_PCAP_BE = 0xD4C3B2A1

local MAGIC_PCAPNG = 0x0A0D0D0A 

local PCAP_LINK_TYPE = {
    DLT_NULL      = 0,     --BSD loopback encapsulation
    DLT_EN10MB    = 1,     --Ethernet (10Mb)
    DLT_EN3MB     = 2,     --Experimental Ethernet (3Mb)
    DLT_AX25      = 3,     --Amateur Radio AX.25
    DLT_PRONET    = 4,     --Proteon ProNET Token Ring
    DLT_CHAOS     = 5,     --Chaos
    DLT_IEEE802   = 6,     --802.5 Token Ring
    DLT_ARCNET    = 7,     --ARCNET, with BSD-style header
    DLT_SLIP      = 8,     --Serial Line IP
    DLT_PPP       = 9,     --Point-to-point Protocol
    DLT_FDDI      = 10,    --FDDI
    DLT_LINUX_SLL = 113,
    DLT_LTALK     = 114,
}

local PCAP_LINK_TYPE_STR = {
    [0] = "BSD loopback devices",
    [1] = "Ethernet, and Linux loopback devices",
    [2] = "Experimental Ethernet (3Mb)",
    [3] = "Amateur Radio AX.25",
    [4] = "Proteon ProNET Token Ring",
    [5] = "Chaos",
    [6] = "802.5 Token Ring",
    [7] = "ARCnet",
    [8] = "SLIP",
    [9] = "PPP",
    [10] = "FDDI",
    [100] = "LLC/SNAP-encapsulated ATM",
    [101] = "raw IP, with no link",
    [102] = "BSD/OS SLIP",
    [103] = "BSD/OS PPP",
    [104] = "Cisco HDLC",
    [105] = "802.11",
    [108] = "later OpenBSD loopback devices (with the AF_value in network byte order)",
    [113] = "linux cooked capture",
    [114] = "LocalTalk",
}

local PCAPNG_BLOCK_TYPE = {
    RESERVED = 0x00000000,
    IDB = 0x00000001, --interface description block
    PB  = 0x00000002, --packet block
    SPB = 0x00000003, --simple packet block
    NRB = 0x00000004, --name resolution block
    ISB = 0x00000005, --Interface Statistics Block
    EPB = 0x00000006, --Enhanced Packet Block
    ITB = 0x00000007, --IRIG Timestamp Block
    AFDX_EIB = 0x00000008, --Arinc 429 in AFDX Encapsulation Information Block
    SHB = 0x0A0D0D0A, --Section Header Block
--    0x0A0D0A00-0x0A0D0AFF   Reserved.
--    0x000A0D0A-0xFF0A0D0A   Reserved.
--    0x000A0D0D-0xFF0A0D0D   Reserved.
--    0x0D0D0A00-0x0D0D0AFF   Reserved.
}

local PCAPNG_BLOCK_TYPE_STR = {
    [PCAPNG_BLOCK_TYPE.RESERVED] = "reserved",
    [PCAPNG_BLOCK_TYPE.IDB] = "interface description block",
    [PCAPNG_BLOCK_TYPE.PB] = "packet block",
    [PCAPNG_BLOCK_TYPE.SPB] = "simple packet block",
    [PCAPNG_BLOCK_TYPE.NRB] = "name resolution block",
    [PCAPNG_BLOCK_TYPE.ISB] = "interface statistics block",
    [PCAPNG_BLOCK_TYPE.EPB] = "enhanced packet block",
    [PCAPNG_BLOCK_TYPE.ITB] = "IRIG timestamp block",
    [PCAPNG_BLOCK_TYPE.AFDX_EIB] = "Arinc 429 in AFDX Encapsulation Information Block",
    [PCAPNG_BLOCK_TYPE.SHB] = "section header block",
}

local ETHER_TYPE = {
    PUP     = 0x0200, --Xerox PUP
    SPRITE  = 0x0500, --Sprite
    IP      = 0x0800, --IP
    ARP     = 0x0806, --Address resolution
    REVARP  = 0x8035, --Reverse ARP
    AT      = 0x809B, --AppleTalk protocol
    AARP    = 0x80F3, --AppleTalk ARP
    VLAN    = 0x8100, --IEEE 802.1Q VLAN tagging
    IPX     = 0x8137, --IPX
    IPV6    = 0x86dd, --IP protocol version 6
    LOOPBACK= 0x9000, --used to test interfaces
}

local ETHER_TYPE_STR = {
    [ETHER_TYPE.PUP]      = "PUP",
    [ETHER_TYPE.SPRITE]   = "SPRITE",
    [ETHER_TYPE.IP]       = "IP",
    [ETHER_TYPE.ARP]      = "ARP",
    [ETHER_TYPE.REVARP]   = "RARP",
    [ETHER_TYPE.AT]       = "AT",
    [ETHER_TYPE.AARP]     = "AARP",
    [ETHER_TYPE.VLAN]     = "VLAN",
    [ETHER_TYPE.IPX]      = "IPX",
    [ETHER_TYPE.IPV6]     = "IPV6",
    [ETHER_TYPE.LOOPBACK] = "LOOPBACK",
}

local IPV4_PROTOCOL = {
    ICMP = 0x01,
    TCP = 0x06,
    UDP = 0x11
}

local IPV4_PROTOCOL_STR = {
    [IPV4_PROTOCOL.ICMP] = "ICMP",
    [IPV4_PROTOCOL.TCP] = "TCP",
    [IPV4_PROTOCOL.UDP] = "UDP",
}

local function cb_desc_mac(self)
    local s = self.value
    local mac = string.format("%02X:%02X:%02X:%02X:%02X:%02X", s:byte(1), s:byte(2), s:byte(3), s:byte(4), s:byte(5), s:byte(6))
    return string.format("%s: %s", self.name, mac)
end

local function cb_desc_ip(self)
    return string.format("%s %s: %u %s", self.type, self.name, self.value, helper.n2ip(self.value))
end

local function mkdesc_micro_secs(secs)
    local cb = function(self)
        local ms = math.floor(self.value / 1000)
        ms = secs * 1000 + ms
        return string.format("%s %s: %u %s", self.type, self.name, self.value, helper.ms2date(ms))
    end
    return cb
end

local function mkbrief_micro_secs(secs)
    local cb = function(self)
        local ms = math.floor(self.value / 1000)
        ms = secs * 1000 + ms
        return string.format("%s ", helper.ms2date(ms))
    end
    return cb
end

local pcap_pkthdr_t = class("pcap_pkthdr_t")
function pcap_pkthdr_t:ctor()
    self.time_secs = 0
    self.time_micro_secs = 0
    self.caplen = 0
    self.len = 0
end

local dlt_en10mb_t = class("dlt_en10mb_t")
function dlt_en10mb_t:ctor()
    self.src_mac = nil
    self.dst_mac = nil
    self.ether_type = nil
end


local dlt_linux_sll_t = class("dlt_linux_sll_t")
function dlt_linux_sll_t:ctor()
    self.pack_type = 0
    self.addr_type = 0
    self.addr_len = 0
    self.src_mac = nil
    self.ether_type = 0
end

local ipv4_hdr_t = class("ipv4_hdr_t")
function ipv4_hdr_t:ctor()
    self.ihl = 0
    self.tos = 0
    self.tos_len = 0
    self.id = 0
    self.flag_off = 0
    self.ttl = 0
    self.protocol = 0
    self.check = 0
    self.saddr = 0
    self.daddr = 0
end

local tcp_hdr_t = class("tcp_hdr_t")
function tcp_hdr_t:ctor()

    self.source = 0
    self.dest = 0
    self.seq = 0
    self.ack_seq = 0

    self.flags = {
        doff = 0,
        res1 = 0,
        res2 = 0,
        urg = 0,
        ack = 0,
        psh = 0,
        rst = 0,
        syn = 0,
        fin = 0,
    }

    self.window = 0
    self.check = 0
    self.urg_ptr = 0
end

local udp_hdr_t = class("udp_hdr_t")
function udp_hdr_t:ctor()
    self.source = 0
    self.dest = 0
    self.len = 0
    self.check = 0
end

local interface_t = class("interface_t")
function interface_t:ctor()
    self.link_type = 0
end

local pcap_t = class("pcap_t")
function pcap_t:ctor()
    self.interfaces = {}
    self.frame_count = 0
end

function pcap_t:add_interface( interface )
    table.insert( self.interfaces, interface )
end

function pcap_t:get_interface( i )
    local n = #self.interfaces
    if i < 1 or i > n then return nil end
    return self.interfaces[i]
end

local stream_frame_t = class("stream_frame_t")
function stream_frame_t:ctor()
    self.field_frames = {}
    self.ntcp = 0
    self.nudp = 0
end

function stream_frame_t:append( field_frame )
    table.insert( self.field_frames, field_frame )

    local protocol = field_frame.stream_info.protocol

    if protocol == IPV4_PROTOCOL.TCP then
        self.ntcp = self.ntcp + 1
    elseif protocol == IPV4_PROTOCOL.UDP then
        self.nudp = self.nudp + 1
    end
end

local dict_streams_t = class("dict_streams_t")
function dict_streams_t:ctor()
    self.streams = {}
    self.count = 0
end

function dict_streams_t:has( key )
    return nil ~= self.streams[key]
end

function dict_streams_t:get( key )
    local s = self.streams[key]
    if s then
        return s
    end

    s = stream_frame_t.new()
    self.streams[key] = s
    self.count = self.count + 1
    return s
end


local pcap = nil

local f_pcap_file_header = nil

local f_pcapng_shb = nil
local f_pcapng_idb = {}

local dict_stream_tcp = nil  --src -> dest
local dict_stream_tcp2 = nil --src <-> dest
local dict_stream_udp = nil
local dict_stream_udp2 = nil

local hex_desc = function(self)
    return string.format("%s %s: %d (0x%X)", self.type, self.name, self.value, self.value) 
end

local hex_brief = function(self)
    return string.format("%s:0x%X ", self.name, self.value)
end

local function field_pcap_file_header(swap_endian)
    local f = field.list("pcap_file_header", nil, function(self, ba)
        self:append(field.uint32("magic", swap_endian, hex_desc, hex_brief))
        self:append(field.uint16("version_major", swap_endian, nil, fh.mkbrief_v("major")))
        self:append(field.uint16("version_minor", swap_endian, nil, fh.mkbrief_v("minor")))
        self:append(field.uint32("thiszone", swap_endian))
        self:append(field.uint32("sigfigs", swap_endian))
        self:append(field.uint32("snaplen", swap_endian))
        local f_link_type = self:append(field.uint32("linktype", swap_endian, fh.mkdesc(PCAP_LINK_TYPE_STR), fh.mkbrief("LINK", PCAP_LINK_TYPE_STR)))

        local interface = interface_t.new()
        interface.link_type = f_link_type.value
        pcap:add_interface( interface )
    end)

    f_pcap_file_header = f
    return f
end

local function field_pcap_pkthdr(swap_endian, pcap_pkthdr)
    local f = field.list("pcap_pkthdr", nil, function(self, ba)
        local f_time_secs = self:append(field.uint32("time_secs", swap_endian))
        local f_time_micro_secs = self:append(field.uint32("time_micro_secs", swap_endian
                , mkdesc_micro_secs(f_time_secs.value), mkbrief_micro_secs(f_time_secs.value)))
        local f_caplen = self:append(field.uint32("caplen", swap_endian))
        local f_len = self:append(field.uint32("len", swap_endian))

        pcap_pkthdr.time_secs = f_time_secs.value
        pcap_pkthdr.time_micro_secs = f_time_micro_secs.value
        pcap_pkthdr.caplen = f_caplen.value
        pcap_pkthdr.len = f_len.value
    end, nil, fh.child_brief)
    return f
end

local function field_link_type_dlt_en10mb(swap_endian, dlt_en10mb)
    local f = field.list("ethernet", nil, function(self, ba)
        local f_src_mac = self:append( field.string("src_mac", 6, cb_desc_mac) )
        local f_dst_mac = self:append( field.string("dst_mac", 6, cb_desc_mac) )
        local f_ether_type = self:append( field.uint16("ether_type", swap_endian, fh.mkdesc_x(ETHER_TYPE_STR), fh.mkbrief("", ETHER_TYPE_STR)) )

        dlt_en10mb.src_mac = f_src_mac.value
        dlt_en10mb.dst_mac = f_dst_mac.value
        dlt_en10mb.ether_type = f_ether_type.value

    end, nil, fh.child_brief)
    return f
end

local function field_link_type_dlt_linux_sll(swap_endian, dlt_linux_sll)
    local f = field.list("linux_cooked_capture", nil, function(self, ba)
        local f_pack_type = self:append( field.int16("pack_type", swap_endian) )
        local f_addr_type = self:append( field.int16("addr_type", swap_endian) )
        local f_addr_len = self:append( field.int16("addr_len", swap_endian) )
        local f_src_mac = self:append( field.string("src_mac", 6, cb_desc_mac) )
        self:append( field.int16("unused", swap_endian) )
        local f_ether_type = self:append( field.uint16("ether_type", swap_endian, fh.mkdesc_x(ETHER_TYPE_STR), fh.mkbrief("", ETHER_TYPE_STR)) )

        dlt_linux_sll.pack_type = f_pack_type.value
        dlt_linux_sll.addr_type = f_addr_type.value
        dlt_linux_sll.addr_len = f_addr_len.value
        dlt_linux_sll.src_mac = f_src_mac.value
        dlt_linux_sll.ether_type = f_ether_type.value

    end, nil, fh.child_brief)
    return f
end

local function field_ipv4_hdr(swap_endian, ipv4_hdr)

    local f = field.list("ip_hdr", nil, function(self, ba)
        local f_ver = self:append( field.ubits("version", 4) )
        local f_ihl = self:append( field.ubits("ihl", 4) )

        local f_tos = self:append( field.uint8("tos") )
        local f_tos_len = self:append( field.uint16("tos_len", swap_endian) )
        local f_id = self:append( field.uint16("id", swap_endian) )
        local f_flag_off = self:append( field.uint16("flag_off", swap_endian) )
        local f_ttl = self:append( field.uint8("ttl") )
        --local f_protocol = self:append( field.uint8("protocol", fh.mkdesc(IPV4_PROTOCOL_STR), fh.mkbrief("", IPV4_PROTOCOL_STR)) )
        local f_protocol = self:append( field.uint8("protocol", fh.mkdesc_x(IPV4_PROTOCOL_STR)) )
        local f_check = self:append( field.uint16("check", swap_endian) )
        local f_saddr = self:append( field.uint32("saddr", swap_endian, cb_desc_ip) )
        local f_daddr = self:append( field.uint32("daddr", swap_endian, cb_desc_ip) )

        ipv4_hdr.ihl = f_ihl.value
        ipv4_hdr.tos = f_tos.value
        ipv4_hdr.tos_len = f_tos_len.value
        ipv4_hdr.id = f_id.value
        ipv4_hdr.flag_off = f_flag_off.value
        ipv4_hdr.ttl = f_ttl.value
        ipv4_hdr.protocol = f_protocol.value
        ipv4_hdr.check = f_check.value
        ipv4_hdr.saddr = f_saddr.value
        ipv4_hdr.daddr = f_daddr.value
    end, nil, fh.child_brief)
    return f
end

local function field_tcp_hdr(swap_endian, tcp_hdr)
    local f = field.list("tcp_hdr", nil, function(self, ba)
        local pos = ba:position()
        local f_source = self:append( field.uint16("source", swap_endian) )
        local f_dest = self:append( field.uint16("dest", swap_endian) )
        local f_seq = self:append( field.uint32("seq", swap_endian) )
        local f_ack_seq = self:append( field.uint32("ack_seq", swap_endian) )

        local f_doff = field.ubits("doff", 4, nil, fh.mkbrief_v("DOFF"))
        local f_res1 = field.ubits("res1", 4)
        local f_res2 = field.ubits("res2", 2)
        local f_urg = field.ubits("urg", 1, nil, fh.mkbrief_v("U"))
        local f_ack = field.ubits("ack", 1, nil, fh.mkbrief_v("A"))
        local f_psh = field.ubits("psh", 1, nil, fh.mkbrief_v("P"))
        local f_rst = field.ubits("rst", 1, nil, fh.mkbrief_v("R"))
        local f_syn = field.ubits("syn", 1, nil, fh.mkbrief_v("S"))
        local f_fin = field.ubits("fin", 1, nil, fh.mkbrief_v("F"))
        self:append( field.bit_list("flags", 2, function(self, ba)
            self:append( f_doff )
            self:append( f_res1 )
            self:append( f_res2 )

            self:append( f_urg )
            self:append( f_ack )
            self:append( f_psh )
            self:append( f_rst )
            self:append( f_syn )
            self:append( f_fin )
        end))

        local f_window = self:append( field.uint16("window", swap_endian) )
        local f_check = self:append( field.uint16("check", swap_endian) )
        local f_urg_ptr = self:append( field.uint16("urg_ptr", swap_endian) )

        local len_tcphdr = f_doff.value * 4
        local len_opt = len_tcphdr - (ba:position() - pos)
        if len_opt > 0 then
            self:append( field.string("opt_data", len_opt) )
        end

        tcp_hdr.source = f_source.value
        tcp_hdr.dest = f_dest.value
        tcp_hdr.seq = f_seq.value
        tcp_hdr.ack_seq = f_ack_seq.value

        local flags = tcp_hdr.flags
        flags.doff = f_doff.value
        flags.res1 = f_res1.value
        flags.res2 = f_res2.value
        flags.urg = f_urg.value
        flags.ack = f_ack.value
        flags.psh = f_psh.value
        flags.rst = f_rst.value
        flags.syn = f_syn.value
        flags.fin = f_fin.value

        tcp_hdr.window = f_window.value
        tcp_hdr.check = f_check.value
        tcp_hdr.urg_ptr = f_urg_ptr.value
    end)
    return f
end

local function field_udp_hdr(swap_endian, udp_hdr)
    local f = field.list("udp_hdr", nil, function(self, ba)
        local f_source = self:append(field.uint16("source", swap_endian))
        local f_dest = self:append(field.uint16("dest", swap_endian))
        local f_len = self:append(field.uint16("len", swap_endian))
        local f_check = self:append(field.uint16("check", swap_endian))

        udp_hdr.source = f_source.value
        udp_hdr.dest = f_dest.value
        udp_hdr.len = f_len.value
        udp_hdr.check = f_check.value
    end)
    return f
end

local cb_ipv4_brief = function(self)
    local child_brief = self:get_child_brief()
    local info = self.stream_info
    local sproto = IPV4_PROTOCOL_STR[info.protocol] or "??"

    local dir = string.format("%s %s:%d > %s:%d", sproto, helper.n2ip(info.saddr), info.src_port
            , helper.n2ip(info.daddr), info.dst_port)
    return string.format("%s %s", dir, child_brief)
end

local function field_ipv4()

    local len = nil
    local f = field.list("ipv4", nil, function(self, ba)
        local pos = ba:position()

        local ipv4_hdr = ipv4_hdr_t.new()
        self:append( field_ipv4_hdr(true, ipv4_hdr) )

        len = ipv4_hdr.tos_len
        self.len = len

        local parser_args = {}
        parser_args.ipv4_hdr = ipv4_hdr

        local ipv4_protocol = ipv4_hdr.protocol

        local src_port = 0
        local dst_port = 0
        if ipv4_protocol == IPV4_PROTOCOL.TCP then

            local tcp_hdr = tcp_hdr_t.new()
            self:append( field_tcp_hdr(true, tcp_hdr) )

            src_port = tcp_hdr.source
            dst_port = tcp_hdr.dest

            parser_args.tcp_hdr = tcp_hdr
        elseif ipv4_protocol == IPV4_PROTOCOL.UDP then

            local udp_hdr = udp_hdr_t.new()
            self:append( field_udp_hdr(true, udp_hdr) )

            src_port = udp_hdr.source
            dst_port = udp_hdr.dest

            parser_args.udp_hdr = udp_hdr
        else
            --error
        end

        self.stream_info = {
            protocol = ipv4_protocol,
            saddr = ipv4_hdr.saddr,
            daddr = ipv4_hdr.daddr,
            src_port = src_port,
            dst_port = dst_port,
        }

        local remain = len - (ba:position()-pos)
        if remain > 0 then

            self.stream_info.payload = {
                ba = ba,
                offset = ba:position(),
                len = remain,
            }

            local parser = dict_parser[src_port] or dict_parser[dst_port]
            if nil == parser then
                --bi.log(string.format("nil == parser, %d => %d", src_port, dst_port))
                self:append( field.string("data", remain) )
                return
            end

            local codec = helper.get_codec(parser)
            self:append( codec.decode(ba, remain, parser_args) )

            remain = len - (ba:position()-pos)
            if remain > 0 then
                self:append( field.string("data", remain) )
            end
        end
    end, nil, cb_ipv4_brief)
    return f
end

local function setup_menu_ipv4(f_ipv4, f_frame)

    local protocol = f_ipv4.stream_info.protocol
    if protocol ~= IPV4_PROTOCOL.TCP and protocol ~= IPV4_PROTOCOL.UDP then
        return
    end

    local is_tcp = protocol == IPV4_PROTOCOL.TCP

    local info = f_ipv4.stream_info
    f_frame.stream_info = info

    local sip = helper.n2ip(info.saddr)
    local dip = helper.n2ip(info.daddr)

    local key = string.format("%s_%d_%s_%d", sip, info.src_port, dip, info.dst_port)
    local key_revert = string.format("%s_%d_%s_%d", dip, info.dst_port, sip, info.src_port)
    local stream = nil
    local stream2 = nil
    if is_tcp then
        if nil == dict_stream_tcp then
            dict_stream_tcp = dict_streams_t.new()
            dict_stream_tcp2 = dict_streams_t.new()
        end
        stream = dict_stream_tcp:get(key)

        if true == dict_stream_tcp2:has(key_revert) then
            stream2 = dict_stream_tcp2:get(key_revert)
        else
            stream2 = dict_stream_tcp2:get(key)
        end
    else
        if nil == dict_stream_udp then
            dict_stream_udp = dict_streams_t.new()
            dict_stream_udp2 = dict_streams_t.new()
        end
        stream = dict_stream_udp:get(key)

        if true == dict_stream_udp2:has(key_revert) then
            stream2 = dict_stream_udp2:get(key_revert)
        else
            stream2 = dict_stream_udp2:get(key)
        end
    end
    stream:append( f_frame )
    stream2:append( f_frame )

    local save_stream = function( streams, file )
        bi.log(string.format("save_stream %s", file))
        local fp = io.open(file, "wb")
        if fp then
            if nil ~= f_pcap_file_header then
                fp:write( f_pcap_file_header:get_data() )
            else
                fp:write( f_pcapng_shb:get_data() )
                for _, v in ipairs(f_pcapng_idb) do
                    fp:write( v:get_data() )
                end
            end

            for _, frame in ipairs(streams) do
                fp:write( frame:get_data() )
            end
            fp:close()
        end
    end

    local save_payload = function( streams, file )
        bi.log(string.format("save_payload %s", file))
        local fp = io.open(file, "wb")
        if fp then
            for _, frame in ipairs(streams) do
                local payload = frame.stream_info.payload
                if nil ~= payload then
                    local ba = payload.ba
                    local data = ba:peek_bytes_from(payload.offset, payload.len)
                    fp:write( data )
                end
            end
            fp:close()
        end
    end

    local extract_stream = function(path, sproto, dict_stream)
        if nil == dict_stream then return end
        if dict_stream.count <= 0 then return end

        for k, s in pairs(dict_stream.streams) do
            local file = string.format("%s/%s_%s.pcap", path, sproto, k)
            save_stream( s.field_frames, file )
        end
    end

    local extract_payload = function(path, sproto, dict_stream)
        if dict_stream.count <= 0 then return end

        for k, s in pairs(dict_stream.streams) do
            local file = string.format("%s/%s_payload_%s.bin", path, sproto, k)
            save_payload( s.field_frames, file )
        end
    end

    f_ipv4.cb_context_menu = function(self, menu)
        local path = bi.get_tmp_dir()

        menu:add_action("extract all streams: src -> dest", function()
            extract_stream(path, "tcp", dict_stream_tcp)
            extract_stream(path, "udp", dict_stream_udp)
        end)
        menu:add_action("extract all streams: src <-> dest", function()
            extract_stream(path, "tcp", dict_stream_tcp2)
            extract_stream(path, "udp", dict_stream_udp2)
        end)

        if dict_stream_tcp and dict_stream_tcp.count > 0 then
            menu:add_action("extract tcp streams: src -> dest", function()
                extract_stream(path, "tcp", dict_stream_tcp)
            end)
        end

        if dict_stream_tcp2 and dict_stream_tcp2.count > 0 then
            menu:add_action("extract tcp streams: src <-> dest", function()
                extract_stream(path, "tcp", dict_stream_tcp2)
            end)
        end

        if dict_stream_tcp and dict_stream_tcp.count > 0 then
            menu:add_action("extract tcp stream payload: src -> dest", function()
                extract_payload(path, "tcp", dict_stream_tcp)
            end)
        end

        if dict_stream_udp and dict_stream_udp.count > 0 then
            menu:add_action("extract udp streams: src -> dest", function()
                extract_stream(path, "udp", dict_stream_udp)
            end)
        end

        if dict_stream_udp2 and dict_stream_udp2.count > 0 then
            menu:add_action("extract udp streams: src <-> dest", function()
                extract_stream(path, "udp", dict_stream_udp2)
            end)
        end

        if dict_stream_udp and dict_stream_udp.count > 0 then
            menu:add_action("extract udp payload: src -> dest", function()
                extract_payload(path, "udp", dict_stream_udp)
            end)
        end

        local sproto = nil
        if is_tcp then
            sproto = "tcp"
        else
            sproto = "udp"
        end
        menu:add_action(string.format("extract this %s stream %s", sproto, key), function()
            local file = string.format("%s/%s_%s.pcap", path, sproto, key)
            save_stream( stream.field_frames, file )
        end)

        menu:add_action(string.format("extract this %s payload %s", sproto, key), function()
            local file = string.format("%s/%s_payload_%s.bin", path, sproto, key)
            save_payload( stream.field_frames, file )
        end)

    end
end


local function field_pcap_frame(index, swap_endian)

    local interface = pcap:get_interface(1)
    local link_type = interface.link_type
    local f = field.list(string.format("frame[%d]", index), nil, function(self, ba)
        local pcap_pkthdr = pcap_pkthdr_t.new()
        self:append( field_pcap_pkthdr(swap_endian, pcap_pkthdr) )

        local pos = ba:position()

        local ether_type = nil
        if link_type == PCAP_LINK_TYPE.DLT_LINUX_SLL then

            local dlt_linux_sll = dlt_linux_sll_t.new()
            self:append( field_link_type_dlt_linux_sll(true, dlt_linux_sll) )

            ether_type = dlt_linux_sll.ether_type
        elseif link_type == PCAP_LINK_TYPE.DLT_EN10MB then
            local dlt_en10mb = dlt_en10mb_t.new()
            self:append( field_link_type_dlt_en10mb(true, dlt_en10mb) )

            ether_type = dlt_en10mb.ether_type
        end

        if ether_type == ETHER_TYPE.IP then
            local f_ipv4 = self:append( field_ipv4() )

            setup_menu_ipv4(f_ipv4, self)
        end

        local remain = pcap_pkthdr.len - (ba:position() - pos)
        if remain > 0 then
            self:append(field.string("remain", remain))
        end

        local skip = pcap_pkthdr.caplen - pcap_pkthdr.len
        if skip > 0 then
            self:append(field.string("skip", skip))
        end
    end)
    return f
end



local function field_pcap(ba, len, swap_endian)

    local f_pcap = field.list("PCAP", len, function(self, ba)
        self:append( field_pcap_file_header(swap_endian) )

        local index = 0
        while ba:length() > 0 do
            index = index + 1

            self:append(field_pcap_frame(index, swap_endian))

            local pos = ba:position()
            bi.set_progress_value(pos)
        end
        pcap.frame_count = index
    end)

    return f_pcap
end

local function field_pcapng_section_header_block(index, swap_endian)
    local f = field.list("SHB", nil, function(self, ba)
        local pos = ba:position()
        self:append( field.uint32("magic", swap_endian) )
        local f_total_len = self:append( field.uint32("total_len", swap_endian) )
        self:append( field.uint32("byte_order", swap_endian) )
        self:append( field.uint16("major", swap_endian) )
        self:append( field.uint16("minor", swap_endian) )
        self:append( field.uint64("section_length", swap_endian) )
--[[
        while true do
            self:append( field.uint16("option_code", swap_endian) )
            local f_opt_len = self:append( field.uint16("option_length", swap_endian) )
            if f_opt_len.value == 0 then
                break
            end

            self:append( field.string("option_value", f_opt_len.value) )
        end
--]]
        local remain = f_total_len.value - (ba:position()-pos) - 4
        if remain > 0 then
            self:append( field.string("opt", remain) )
        end

        self:append( field.uint32("total_len", swap_endian) )
    end)

    f_pcapng_shb = f
    return f
end

local function field_pcapng_packet_block(index, swap_endian)
    local f = field.list("PB", nil, function(self, ba)
        local pos = ba:position()

        self:append(field.uint32("block_type", swap_endian))
        local f_total_len = self:append(field.uint32("total_len", swap_endian))

        local remain = f_total_len.value - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("data", remain) )
        end
    end)
    return f
end

local function field_pcapng_interface_description_block(index, swap_endian)
    local f = field.list("IDB", nil, function(self, ba)
        local pos = ba:position()

        self:append(field.uint32("block_type", swap_endian))
        local f_total_len = self:append(field.uint32("total_len", swap_endian))
        local f_link_type = self:append(field.uint16("link_type", swap_endian))
        self:append(field.uint16("reserved", swap_endian))
        self:append(field.uint32("snap_len", swap_endian))

        local interface = interface_t.new()
        interface.link_type = f_link_type.value
        pcap:add_interface( interface )

        local remain = f_total_len.value - (ba:position()-pos) - 4
        if remain > 0 then
            self:append( field.string("options", remain) )
        end

        self:append( field.uint32("total_len", swap_endian) )
    end)
    table.insert(f_pcapng_idb, f)
    return f
end

--[[
https://github.com/boundary/wireshark/blob/master/wiretap/pcapng.c
ts = (((guint64)wblock->data.packet.ts_high) << 32) | ((guint64)wblock->data.packet.ts_low);
wblock->packet_header->ts.secs = (time_t)(ts / int_data.time_units_per_second);
wblock->packet_header->ts.nsecs = (int)(((ts % int_data.time_units_per_second) * 1000000000) / int_data.time_units_per_second);
--]]

local function field_pcapng_enhanced_packet_block(index, swap_endian)
    local f = field.list(string.format("EPB[%d]", index), nil, function(self, ba)
        local pos = ba:position()

        self:append(field.uint32("block_type", swap_endian))
        local f_total_len = self:append(field.uint32("total_len", swap_endian))

        local f_interface_id = self:append(field.uint32("interface_id", swap_endian))

        local f_ts_high = self:append(field.uint32("ts_high", swap_endian))
        local f_ts_low = self:append(field.uint32("ts_low", swap_endian))

        local ts = (f_ts_high.value << 32) | f_ts_low.value
        --TODO IDB.if_tsresol
        local secs = ts / 1000000
        local ms = (ts % 1000000) / 1000
        ms = math.floor(secs * 1000 + ms)

        f_ts_low.get_desc = function(self)
            return string.format("%s %s: %u %s", self.type, self.name, self.value, helper.ms2date(ms))
        end
        f_ts_low.get_brief = function(self)
            return string.format("%s ", helper.ms2date(ms))
        end
        
        self:append(field.uint32("capture_len", swap_endian))
        local f_packet_len = self:append(field.uint32("packet_len", swap_endian))

        local interface = pcap:get_interface( f_interface_id.value + 1 )

        if nil ~= interface then

            local link_type = interface.link_type
            if link_type == PCAP_LINK_TYPE.DLT_NULL then

                local f_family = self:append( field.uint32("family", swap_endian) )
                if f_family.value == 2 then --IP
                    local f_ipv4 = self:append( field_ipv4() )
                    setup_menu_ipv4(f_ipv4, self)
                end

            elseif link_type == PCAP_LINK_TYPE.DLT_EN10MB then

                local dlt_en10mb = dlt_en10mb_t.new()
                self:append( field_link_type_dlt_en10mb(true, dlt_en10mb) )

                local ether_type = dlt_en10mb.ether_type
                if ether_type == ETHER_TYPE.IP then
                    local f_ipv4 = self:append( field_ipv4() )
                    setup_menu_ipv4(f_ipv4, self)
                end

            end
        end

        local remain = f_total_len.value - (ba:position()-pos) - 4
        if remain > 0 then
            self:append( field.string("options", remain) )
        elseif remain < 0 then
            bi.log(string.format("pcap epb %s remain < 0: %d", self.name, remain))
            ba:back_pos(math.abs(remain))
        end

        self:append( field.uint32("total_len", swap_endian) )
    end)
    return f
end

local function field_pcapng_unknown_block(index, swap_endian)
    local f = field.list("unknown_block", nil, function(self, ba)
        local pos = ba:position()

        self:append(field.uint32("block_type", swap_endian))
        local f_total_len = self:append(field.uint32("total_len", swap_endian))

        local remain = f_total_len.value - (ba:position()-pos)
        if remain > 0 then
            self:append( field.string("data", remain) )
        end
    end)
    return f
end

local field_pcapng_blocks = {
    [PCAPNG_BLOCK_TYPE.SHB] = field_pcapng_section_header_block,
    [PCAPNG_BLOCK_TYPE.PB] = field_pcapng_packet_block,
    [PCAPNG_BLOCK_TYPE.IDB] = field_pcapng_interface_description_block,
    [PCAPNG_BLOCK_TYPE.EPB] = field_pcapng_enhanced_packet_block,
}


local function field_pcapng(ba, len, swap_endian)
    local f_pcapng = field.list("PCAPNG", len, function(self, ba)

        local index = 0
        while ba:length() > 0 do

            local block_type = ba:peek_uint32()
            if block_type == PCAPNG_BLOCK_TYPE.EPB then
                index = index + 1            
            end

            local cb_field = field_pcapng_blocks[block_type] or field_pcapng_unknown_block
            self:append( cb_field(index, swap_endian) )

            local pos = ba:position()
            bi.set_progress_value(pos)
        end
        pcap.frame_count = index
    end)

    return f_pcapng

end

local function decode_pcap( ba, len )
    pcap = pcap_t.new()

    local swap_endian = false
    local magic = ba:peek_uint32(swap_endian)

    if magic == MAGIC_PCAP_LE or magic == MAGIC_PCAP_BE then
        if magic == MAGIC_PCAP_BE then
            swap_endian = true
        end

        local f_pcap = field_pcap(ba, len, swap_endian)
        return f_pcap
    elseif magic == MAGIC_PCAPNG then

        ba:read_uint64()
        local endian = ba:read_uint32(is_bigendian)
        ba:back_pos(12)

        local pcapng_big_endian = 0x4D3C2B1A 
        if endian == pcapng_big_endian then
            is_bigendian = true
        end

        local f_pcapng = field_pcapng(ba, len, swap_endian)
        return f_pcapng
    else
        bi.log(string.format("unknown pcap magic: 0x0X", magic))
        return
    end
end

local function clear()
    pcap = nil
    f_pcap_file_header = nil

    f_pcapng_shb = nil
    f_pcapng_idb = {}
    dict_stream_tcp = nil
    dict_stream_tcp2 = nil
    dict_stream_udp = nil
    dict_stream_udp2 = nil
end

local function build_summary()
    if nil == pcap then return end

    bi.append_summary("frames", pcap.frame_count)
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "tcpdump",
    file_ext = "pcap pcapng",
    decode = decode_pcap,
    clear = clear,
    build_summary = build_summary,
}

return codec
