local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

--https://www.cnblogs.com/CoderTian/p/6657844.html
--https://www.jianshu.com/p/9fdc0eaa2dea

--http://soundfile.sapp.org/doc/WaveFormat/
--[[
The canonical WAVE format starts with the RIFF header:

0         4   ChunkID          Contains the letters "RIFF" in ASCII form
                               (0x52494646 big-endian form).
4         4   ChunkSize        36 + SubChunk2Size, or more precisely:
                               4 + (8 + SubChunk1Size) + (8 + SubChunk2Size)
                               This is the size of the rest of the chunk 
                               following this number.  This is the size of the 
                               entire file in bytes minus 8 bytes for the
                               two fields not included in this count:
                               ChunkID and ChunkSize.
8         4   Format           Contains the letters "WAVE"
                               (0x57415645 big-endian form).

The "WAVE" format consists of two subchunks: "fmt " and "data":
The "fmt " subchunk describes the sound data's format:

12        4   Subchunk1ID      Contains the letters "fmt "
                               (0x666d7420 big-endian form).
16        4   Subchunk1Size    16 for PCM.  This is the size of the
                               rest of the Subchunk which follows this number.
20        2   AudioFormat      PCM = 1 (i.e. Linear quantization)
                               Values other than 1 indicate some 
                               form of compression.
22        2   NumChannels      Mono = 1, Stereo = 2, etc.
24        4   SampleRate       8000, 44100, etc.
28        4   ByteRate         == SampleRate * NumChannels * BitsPerSample/8
32        2   BlockAlign       == NumChannels * BitsPerSample/8
                               The number of bytes for one sample including
                               all channels. I wonder what happens when
                               this number isn't an integer?
34        2   BitsPerSample    8 bits = 8, 16 bits = 16, etc.
          2   ExtraParamSize   if PCM, then doesn't exist
          X   ExtraParams      space for extra parameters

The "data" subchunk contains the size of the data and the actual sound:

36        4   Subchunk2ID      Contains the letters "data"
                               (0x64617461 big-endian form).
40        4   Subchunk2Size    == NumSamples * NumChannels * BitsPerSample/8
                               This is the number of bytes in the data.
                               You can also think of this as the size
                               of the read of the subchunk following this 
                               number.
44        *   Data             The actual sound data.
--]]

local CHANNEL_TYPE = {
	MONO = 1,
	STEREO = 2,
}
local CHANNEL_TYPE_STR = {
	[CHANNEL_TYPE.MONO] = "Mono",
	[CHANNEL_TYPE.STEREO] = "Stereo",
}

local AUDIO_FORMAT = {
	PCM = 1,
}

local AUDIO_FORMAT_STR = {
	[AUDIO_FORMAT.PCM] = "PCM"
}

local swap_endian = false

local wav_t = class("wav_t")
function wav_t:ctor()
	self.fname = nil
	self.audio_format = 0
	self.num_ch = 0
	self.sample_rate = 0
	self.byte_rate = 0
	self.bits_per_sample = 0

	self.duration = 0
	self.nsample = 0
	self.bitrate = 0
end

local wav = nil

local function field_wav_hdr()
	local f = field.list("wav_hdr", nil, function(self, ba)
		local f_chunk_id = self:append(field.string("chunk_id", 4, fh.str_desc, fh.mkbrief("ID"))) --RIFF
		local f_chunk_size = self:append(field.uint32("chunk_size", swap_endian, fh.mkbrief("SIZE")))
		local f_format = self:append(field.string("format", 4, fh.str_desc, fh.mkbrief("FMT"))) --WAVE
	end)
	return f
end

local function field_wav_fmt()
	local f = field.list("wav_fmt", nil, function(self, ba)
		local f_sub_chunk1_id = self:append(field.string("sub_chunk1_id", 4, fh.str_desc, fh.mkbrief("ID")))
		local f_sub_chunk1_size = self:append(field.uint32("sub_chunk1_size", swap_endian, fh.mkbrief("SIZE")))

		local pos = ba:position()

		local f_audio_format = self:append(field.uint16("audio_format", swap_endian, fh.mkdesc(AUDIO_FORMAT_STR), fh.mkbrief("FMT", AUDIO_FORMAT_STR)))
		local f_num_ch = self:append(field.uint16("num_channels", swap_endian, fh.mkdesc(CHANNEL_TYPE_STR), fh.mkbrief("CH", CHANNEL_TYPE_STR)))
		local f_sample_rate = self:append(field.uint32("sample_rate", swap_endian, nil, fh.mkbrief("SAMPLE_RATE")))

		--byte_rate = sample_rate * num_channels * bits_per_sample/8
		local f_byte_rate = self:append(field.uint32("byte_rate", swap_endian, nil, fh.mkbrief("BYTE_RATE")))

		--block_align = num_channels * bits_per_sample/8
		local f_block_align = self:append(field.uint16("block_align", swap_endian))
		local f_bits_per_sample = self:append(field.uint16("bits_per_sample", swap_endian, nil, fh.mkbrief("BITS_PER_SAMPLE")))

		local remain = f_sub_chunk1_size.value - (ba:position() - pos)
		if remain > 0 then
			self:append(field.string("extra", remain))
		end

		wav.audio_format = f_audio_format.value
		wav.num_ch = f_num_ch.value
		wav.sample_rate = f_sample_rate.value
		wav.byte_rate = f_byte_rate.value
		wav.bits_per_sample = f_bits_per_sample.value
	end)

	return f
end

local function field_wav_chunk()
	local cb_brief_id = function(self)
		return string.format("ID:%s ", self:get_data())
	end

	local f = field.list("wav_chunk", nil, function(self, ba)
		local f_sub_chunk2_id = self:append(field.string("sub_chunk2_id", 4, fh.str_desc, cb_brief_id))

		--sub_chunk2_size = num_samples * num_channels * bits_per_sample/8
		local f_sub_chunk2_size = self:append(field.uint32("sub_chunk2_size", swap_endian, nil, fh.mkbrief("SIZE")))

		local tp = f_sub_chunk2_id:get_data()
		tp = string.upper(tp)
		bi.log( string.format( "id: %s %d", tp, f_sub_chunk2_size.value ) )
		if tp == "LIST" then
			self:append( field.string("data", f_sub_chunk2_size.value) )
		elseif tp == "DATA" then
			--pcm data
			local f_pcm = self:append( field.string("data", f_sub_chunk2_size.value) )
			local byte_per_sample = wav.bits_per_sample / 8
			local byte_per_ch = wav.num_ch * byte_per_sample
			wav.sample_count = f_sub_chunk2_size.value / byte_per_ch
			wav.duration = wav.sample_count / (wav.sample_rate/1000)
			wav.bitrate = f_sub_chunk2_size.value / wav.duration * 8

			f_pcm:set_context_menu(function(self, menu)
				menu:add_action("extract all channel pcm", function()
					local fname = string.format("%s_%dx%dx%d.pcm", wav.fname, wav.num_ch, wav.bits_per_sample, wav.sample_rate )
					helper.save_data( fname, self:get_data() )
				end)

				if wav.num_ch == 2 then

					local pcm_len = f_sub_chunk2_size.value
					local half_len = pcm_len/2

					local cb_save_half_ch = function( is_left )
						bi.show_progress("waiting...")
						bi.set_progress_max( pcm_len )
						local tmp_ba = byte_stream( pcm_len )
						tmp_ba:set_data( self:get_data(), pcm_len )

						local ch_ba = byte_stream( half_len )
						local remain = tmp_ba:length()

						local nloop = 0
						while remain > 0 do
							if is_left then
								local lpcm = tmp_ba:read_bytes(byte_per_ch)
								ch_ba:append( lpcm, byte_per_ch )
								tmp_ba:read_bytes(byte_per_ch)
							else
								tmp_ba:read_bytes(byte_per_ch)
								local rpcm = tmp_ba:read_bytes( byte_per_ch )
								ch_ba:append( rpcm, byte_per_ch )
							end

							remain = tmp_ba:length()

							nloop = nloop + 1
							if nloop > 500 then
								bi.set_progress_value( pcm_len - remain )
							end
						end
						bi.close_progress()

						local sch = "L"
						if false == is_left then sch = "R" end

						local fname = string.format("%s_%s_%dx%dx%d.pcm", wav.fname, sch, 1, wav.bits_per_sample, wav.sample_rate )
						helper.save_data( fname, ch_ba:read_bytes(half_len) )
					end

					menu:add_action("extract left channel pcm", function()
						cb_save_half_ch(true)
					end)
					menu:add_action("extract right channel pcm", function()
						cb_save_half_ch(false)
					end)
				end
			end)


--[[
			local byte_per_sample = wav.bits_per_sample / 8
			local byte_per_ch = wav.num_ch * byte_per_sample
			local remain = f_sub_chunk2_size.value

			local f_type = nil
			if byte_per_sample == 1 then
				f_type = field.uint8
			elseif byte_per_sample == 2 then
				f_type = field.uint16
			elseif byte_per_sample == 4 then
				f_type = field.uint32
			elseif byte_per_sample == 8 then
				f_type = field.uint64
			end

			local index = 0
			while remain > 0 do
				self:append( field.list(string.format("[%d]pcm", index), nil, function(self, ba)
					for i=1, wav.num_ch, 1 do
						self:append( f_type("pcm") )
					end
				end))
				index = index + 1

				remain = remain - byte_per_ch
			end
--]]
		else
			self:append( field.string("data", f_sub_chunk2_size.value) )
		end
	end)

	return f
end

local function decode_wav( ba, len, args )
	wav = wav_t.new()
	if args then
		wav.fname = helper.get_base_name(args.fname)
	end

    local f_pcap = field.list("wav", len, function(self, ba)
		self:append( field_wav_hdr() )
		self:append( field_wav_fmt() )

		while true do
			local remain = ba:length()
			if remain < 4 then 
				if remain > 0 then
					self:append( field.string("remain", remain) )
				end
				break 
			end
			self:append( field_wav_chunk() )
		end
    end)

    return f_pcap
end

local function clear()
end

local function build_summary()
	if nil == wav then return end

    bi.append_summary("audio_format", AUDIO_FORMAT_STR[wav.audio_format] or "??")
    bi.append_summary("num_ch", CHANNEL_TYPE_STR[wav.num_ch] or "??")
    bi.append_summary("sample_rate", wav.sample_rate)
    bi.append_summary("byte_rate", wav.byte_rate)
    bi.append_summary("bits_per_sample", wav.bits_per_sample)

    bi.append_summary("sample_count", wav.sample_count)
    bi.append_summary("duration", helper.ms2time(wav.duration))

	local kbps = string.format("%.2f kbps", wav.bitrate)
	bi.append_summary("bitrate", kbps)

end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "wave file",
    file_ext = "wav",
    decode = decode_wav,
    clear = clear,
    build_summary = build_summary,
}

return codec
