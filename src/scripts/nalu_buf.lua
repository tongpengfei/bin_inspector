require("class")

nalu_buf_t = class("nalu_buf_t")
function nalu_buf_t:ctor()
    self.field_ebsps = {}
end

function nalu_buf_t:append( seq, field_ebsp, i_nalu_header, is_new_nal )
    local old = self.field_ebsps[seq]
    if nil ~= old then
        return
    end

    local t = {
        field_ebsp = field_ebsp,
        i_nalu_header = i_nalu_header,
        is_new_nal = is_new_nal
    }
    self.field_ebsps[seq] = t
end


function nalu_buf_t:clear()
    self.field_ebsps = {}
end

function nalu_buf_t:save(file)

    local fp = io.open(file, "wb")
    if nil == fp then 
        bi.message_box(string.format("cant save file to:%s", file))
        return 
    end

    local seqs = {}
    for k, _ in pairs(self.field_ebsps) do
        table.insert( seqs, k )
    end
    table.sort(seqs, function(a, b) return a < b end)

    for i, seq in ipairs(seqs) do
        local t = self.field_ebsps[seq]

        local ebsp = t.field_ebsp:get_data()
        local nalu = nil
        if true == t.is_new_nal then
            local sig = nil
            if i == 1 then
                sig = string.pack("I4", 0x1000000)
            else
                sig = string.pack("I3", 0x10000)
            end
            nalu = sig .. string.pack("I1", t.i_nalu_header) .. ebsp
        else
            nalu = ebsp
        end

        fp:write(nalu)
    end

    fp:close()
end

dict_stream_nalus_t = class("dict_stream_nalus_t")
function dict_stream_nalus_t:ctor()
    self.stream_nalus = {}
    self.nstream = 0
end

--key: ip_port_ssrc
function dict_stream_nalus_t:get(key)
    local stream = self.stream_nalus[key]
    if stream then
        return stream
    end

    stream = nalu_buf_t.new()
    self.stream_nalus[key] = stream
    self.nstream = self.nstream + 1
    return stream
end

function dict_stream_nalus_t:clear()
    for k, v in pairs(self.stream_nalus) do
        v:clear()
    end

    self.stream_nalus = {}
    self.nstream = 0
end


