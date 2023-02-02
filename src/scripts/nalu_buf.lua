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

function nalu_buf_t:append_stap(seq, stapa)
	local old = self.field_ebsps[seq]
	if nil ~= old then
		return
	end

	local arr = {
		is_stab = true,
		arr_data = {}
	}

	for _, stap in ipairs(stapa) do

		local t = {
			field_ebsp = stap.field_ebsp,
			i_nalu_header = stap.i_nalu_header,
			is_new_nal = true,
		}
	
		table.insert(arr.arr_data, t) 
	end
	self.field_ebsps[seq] = arr
end


function nalu_buf_t:clear()
    self.field_ebsps = {}
end

local proc_save_nalu = function(fp, data)
    local ebsp = data.field_ebsp:get_data()
    local nalu = nil
    if true == data.is_new_nal then
        local sig = nil
        if i == 1 then
            sig = string.pack("I4", 0x1000000)
        else
            sig = string.pack("I3", 0x10000)
        end
        nalu = sig .. string.pack("I1", data.i_nalu_header) .. ebsp
    else
        nalu = ebsp
    end

    fp:write(nalu)
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

		if t.is_stab then
			for _, data in ipairs(t.arr_data) do
				proc_save_nalu(fp, data)
			end
		else
			proc_save_nalu(fp, t)
		end
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


