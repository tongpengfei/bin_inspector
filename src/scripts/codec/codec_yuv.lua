local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

--yuv 420p : yyyy....u..v..
--yuv 420sp: yyyy....uv..uv..

local yuv_summary_t = class("yuv_summary_t")
function yuv_summary_t:ctor()
	self.width = 0
	self.height = 0
	self.fmt = 0
	self.frame_size = 0
    self.frames = 0
end

local yuv_summary = nil

local function field_yuv420p(index, w, h, frame_size)

	local y_size = w*h
	local u_size = w*h/4
	local v_size = u_size
    local f = field.list(string.format("✓ [%d]frame", index), frame_size, function(self, ba)
		local f_y = self:append( field.string("✓ y", y_size ))
		local f_u = self:append( field.string("✓ u", u_size ))
		local f_v = self:append( field.string("✓ v", v_size ))

		f_y.cb_click = function(self)
	        bi.clear_bmp()
			local data = self.parent:get_data()
			bi.draw_yuv( TYUV_FORMAT["420P"], data, w, h, 0x001 )
		end
		f_u.cb_click = function(self)
	        bi.clear_bmp()
			local data = self.parent:get_data()
			bi.draw_yuv( TYUV_FORMAT["420P"], data, w, h, 0x010 )
		end
		f_v.cb_click = function(self)
	        bi.clear_bmp()
			local data = self.parent:get_data()
			bi.draw_yuv( TYUV_FORMAT["420P"], data, w, h, 0x100 )
		end
	end)

    f.cb_click = function(self)
        bi.clear_bmp()

		local data = self:get_data()
		bi.draw_yuv( TYUV_FORMAT["420P"], data, w, h, 0x111 )
        --self.ffh:saveBmp(string.format("%s/d_%d.bmp", bi.get_tmp_dir(), f_nalu.index))
    end

	return f
end

--name_WxH_420p.yuv
local function decode_yuv( ba, len, args )

--	local width = 320
--	local height = 240

--	local width = 1280
--	local height = 720

	local width = 0
	local height = 0

	--TODO probe width,height

	if args then
		--parse width height from file name
		local base_name = helper.get_base_name(args.fname)
		local strs = helper.split(base_name, "_")
		for i=#strs, 2, -1 do
			local str = strs[i]
			if string.find(str, "x") then
				local solution = helper.split(str, "x")
				width = tonumber(solution[1])
				height = tonumber(solution[2])
			else
				--fmt
			end
		end
	end

	if width <= 0 or height <= 0 then
		--unknown width height
		bi.message_box("unknown yuv width, height\nfile name format: filename_WxH.yuv\neg. test_320x240.yuv")
    	local f_yuv = field.list("yuv", len, function(self, ba) end)
		return f_yuv
	end

 	yuv_summary = yuv_summary_t.new()
	--420p
	local frame_size = width * height * 3 / 2
	local frame_count = len / frame_size
	bi.log(string.format("decode_yuv %dx%d frame_size:%d frame_count:%d", width, height, frame_size, frame_count))
    local f_yuv = field.list("yuv", len, function(self, ba)

		local index = 0
		while ba:length() > 0 do
			self:append( field_yuv420p(index, width, height, frame_size) )
			index = index + 1
		end

		yuv_summary.frames = index
    end)

	yuv_summary.width = width
	yuv_summary.height= height
	yuv_summary.fmt = 0
	yuv_summary.frame_size = frame_size

    return f_yuv
end

local function clear()
end

local function build_summary()
    if nil == yuv_summary then return end

    bi.append_summary("width", yuv_summary.width)
    bi.append_summary("height", yuv_summary.height)
    bi.append_summary("fmt", "420p")
    bi.append_summary("frame_size", yuv_summary.frame_size)
    bi.append_summary("frames", yuv_summary.frames)
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "yuv",
    file_ext = "yuv",
    decode = decode_yuv,
    clear = clear,
    build_summary = build_summary,
}

return codec
