require("class")

local helper = require("helper")
local field = require("field")
local fh = require("field_helper")
local json = require("cjson")

--reference
--https://github.com/NVIDIA/vdpau-hevc-example/blob/master/gsth265parser.c

local NALU_TYPE = {
	TRAIL_N = 0,
	TRAIL_R = 1,
	TSA_N = 2,
	TSA_R = 3,
	STSA_N = 4,
	STSA_R = 5,
	RADL_N = 6,
	RADL_R = 7,
	RASL_N = 8,
	RASL_R = 9,
	RSV_VCL_N10 = 10,
	RSV_VCL_N12 = 12,
	RSV_VCL_N14 = 14,
	RSV_VCL_R11 = 11,
	RSV_VCL_R13 = 13,
	RSV_VCL_R15 = 15,
	BLA_W_LP = 16,
	BLA_W_RADL = 17,
	BLA_N_LP = 18,
	IDR_W_RADL = 19,
	IDR_N_LP = 20,
	RSV_IRAP_VCL22 = 22,
	RSV_IRAP_VCL23 = 23,
	RSV_VCL24 = 24,
	RSV_VCL25 = 25,
	RSV_VCL26 = 26,
	RSV_VCL27 = 27,
	RSV_VCL28 = 28,
	RSV_VCL29 = 29,
	RSV_VCL30 = 30,
	RSV_VCL31 = 31,
	VPS_NUT = 32,
	SPS_NUT = 33,
	PPS_NUT = 34,
	AUD_NUT = 35,
	EOS_NUT = 36,
	EOB_NUT = 37,
	FD_NUT = 38,
	PREFIX_SEI_NUT = 39,
	SUFFIX_SEI_NUT = 40,
	RSV_NVCL41 = 41,
	RSV_NVCL42 = 42,
	RSV_NVCL43 = 43,
	RSV_NVCL44 = 44,
	RSV_NVCL45 = 45,
	RSV_NVCL46 = 46,
	RSV_NVCL47 = 47,
	UNSPEC48 = 48,
	UNSPEC49 = 49,
	UNSPEC50 = 50,
	UNSPEC51 = 51,
	UNSPEC52 = 52,
	UNSPEC53 = 53,
	UNSPEC54 = 54,
	UNSPEC55 = 55,
	UNSPEC56 = 56,
	UNSPEC57 = 57,
	UNSPEC58 = 58,
	UNSPEC59 = 59,
	UNSPEC60 = 60,
	UNSPEC61 = 61,
	UNSPEC62 = 62,
	UNSPEC63 = 63,
}

local NALU_TYPE_STR = {
	[0] = "TRAIL_N",
	[1] = "TRAIL_R",
	[2] = "TSA_N",
	[3] = "TSA_R",
	[4] = "STSA_N",
	[5] = "STSA_R",
	[6] = "RADL_N",
	[7] = "RADL_R",
	[8] = "RASL_N",
	[9] = "RASL_R",
	[10] = "RSV_VCL_N10",
	[12] = "RSV_VCL_N12",
	[14] = "RSV_VCL_N14",
	[11] = "RSV_VCL_R11",
	[13] = "RSV_VCL_R13",
	[15] = "RSV_VCL_R15",
	[16] = "BLA_W_LP",
	[17] = "BLA_W_RADL",
	[18] = "BLA_N_LP",
	[19] = "IDR_W_RADL",
	[20] = "IDR_N_LP",
	[22] = "RSV_IRAP_VCL22",
	[23] = "RSV_IRAP_VCL23",
	[24] = "RSV_VCL24",
	[25] = "RSV_VCL25",
	[26] = "RSV_VCL26",
	[27] = "RSV_VCL27",
	[28] = "RSV_VCL28",
	[29] = "RSV_VCL29",
	[30] = "RSV_VCL30",
	[31] = "RSV_VCL31",
	[32] = "VPS_NUT",
	[33] = "SPS_NUT",
	[34] = "PPS_NUT",
	[35] = "AUD_NUT",
	[36] = "EOS_NUT",
	[37] = "EOB_NUT",
	[38] = "FD_NUT",
	[39] = "PREFIX_SEI_NUT",
	[40] = "SUFFIX_SEI_NUT",
	[41] = "RSV_NVCL41",
	[42] = "RSV_NVCL42",
	[43] = "RSV_NVCL43",
	[44] = "RSV_NVCL44",
	[45] = "RSV_NVCL45",
	[46] = "RSV_NVCL46",
	[47] = "RSV_NVCL47",
	[48] = "UNSPEC48",
	[49] = "UNSPEC49",
	[50] = "UNSPEC50",
	[51] = "UNSPEC51",
	[52] = "UNSPEC52",
	[53] = "UNSPEC53",
	[54] = "UNSPEC54",
	[55] = "UNSPEC55",
	[56] = "UNSPEC56",
	[57] = "UNSPEC57",
	[58] = "UNSPEC58",
	[59] = "UNSPEC59",
	[60] = "UNSPEC60",
	[61] = "UNSPEC61",
	[62] = "UNSPEC62",
	[63] = "UNSPEC63",
}

local nal_t = class("nal_t")
function nal_t:ctor()
    self.nal_unit_type = 0
    self.nuh_layer_id = 0
    self.temporal_id = 0
end


local h265_t = class("h265_t")
function h265_t:ctor()
    self.sps = {} --sps[seq_parameter_set_id] = SPS
    self.pps = {} --pps[pps_id] = PPS
    self.nal = nil --current nal

    self.nalus = {}
end

local function field_nalu_header()
    local field_forbidden_bit = field.ubits("forbidden_bit", 1, nil, fh.mkbrief("F"))
    local field_nal_unit_type = field.ubits("nal_unit_type", 6, fh.mkdesc(NALU_TYPE_STR), fh.mkbrief("T", NALU_TYPE_STR))
    local field_nuh_layer_id = field.ubits("nuh_layer_id", 6, nil, fh.mkbrief("LayerId"))
    local field_nuh_temporal_id_plus1 = field.ubits("nuh_temporal_id_plus1", 3, nil, function(self)
                return string.format("TemporalId:%d ", self.value-1)
            end)

    local f = field.bit_list("NALU HEADER", 2, function(self, ba)
                self:append( field_forbidden_bit )
                self:append( field_nal_unit_type )
                self:append( field_nuh_layer_id )
                self:append( field_nuh_temporal_id_plus1 )

                self.nalu_type = field_nal_unit_type.value
                self.nuh_layer_id = field_nuh_layer_id.value
                self.temporal_id = field_nuh_temporal_id_plus1.value - 1
            end, nil, fh.child_brief)
    return f
end

local function field_vps(ebsp_len, nal)
end

local function field_profile_tier_level( bit_list, sps_max_sub_layers_minus1 )

    bit_list:append( field.ubits("profile_space", 2) )
    bit_list:append( field.ubits("tier_flag", 1) )
    bit_list:append( field.ubits("profile_idc", 5) )

    for i=1,32 do
        bit_list:append( field.ubits(string.format("profile_compatibility_flag[%d]", i), 1) )
    end

    bit_list:append( field.ubits("progressive_source_flag", 1) )
    bit_list:append( field.ubits("interlaced_source_flag", 1) )
    bit_list:append( field.ubits("non_packed_constraint_flag", 1) )
    bit_list:append( field.ubits("frame_only_constraint_flag", 1) )

    bit_list:append( field.ubits("skip", 22) )
    bit_list:append( field.ubits("skip", 22) )
    bit_list:append( field.ubits("level_idc", 8) )

    local sub_layer_profile_present_flag = {}
    local sub_layer_level_present_flag = {}

    for i=1, sps_max_sub_layers_minus1 do
        local f_tmp0 = bit_list:append( field.ubits(string.format("sub_layer_profile_present_flag[%d]", i)) )
        local f_tmp1 = bit_list:append( field.ubits(string.format("sub_layer_level_present_flag[%d]", i)) )

        table.insert( sub_layer_profile_present_flag, f_tmp0.value )
        table.insert( sub_layer_level_present_flag, f_tmp1.value )
    end

    if sps_max_sub_layers_minus1 > 0 then
        for i=sps_max_sub_layers_minus1, 7 do
            bit_list:append( field.ubits("skip", 2) )
        end
    end

    for i=1, sps_max_sub_layers_minus1 do
        if sub_layer_profile_present_flag[i] ~= 0 then
            bit_list:append( field.ubits(string.format("sub_layer_profile_space[%d]", i), 2 ) )
            bit_list:append( field.ubits(string.format("sub_layer_tier_flag[%d]", i), 2 ) )
            bit_list:append( field.ubits(string.format("sub_layer_profile_idc[%d]", i), 2 ) )

            for j=1, 32 do
                bit_list:append( field.ubits(string.format("sub_layer_profile_idc[%d]", i), 2 ) )
            end
        end

        if sub_layer_level_present_flag[i] ~= 0 then
            bit_list:append( field.ubits(string.format("sub_layer_profile_compatibility_flag[%d][%d]", i, j), 1 ) )
        end

        bit_list:append( field.ubits(string.format("sub_layer_progressive_source_flag[%d]", i), 1 ) )
        bit_list:append( field.ubits(string.format("sub_layer_interlaced_source_flag[%d]", i), 1 ) )
        bit_list:append( field.ubits(string.format("sub_layer_non_packed_constraint_flag[%d]", i), 1 ) )
        bit_list:append( field.ubits(string.format("sub_layer_frame_only_constraint_flag[%d]", i), 1 ) )

        bit_list:append( field.ubits("skip", 22) )
        bit_list:append( field.ubits("skip", 22) )
    end

end

local function field_scaling_list_data()

    local f = field.bit_list("scaling_list_data", nil, function(self, ba)

        for sizeId=0, 3 do
            local step = 1
            if sizeId == 3 then
                step = 3
            end

            for matrixId=0, 5, step do
                local f_tmp = self:append( field.ubits(string.format("scaling_list_pred_mode_flag[%d][%d]", sizeId, matrixId), 1) )
                if f_tmp.value == 0 then
                    self:append( field.uebits(string.format("scaling_list_pred_matrix_id_delta[%d][%d]", sizeId, matrixId) ) )
                else
                    local nextCoef = 8
                    local coefNum = math.min( 64, ( 1 << ( 4 + ( sizeId << 1 ) ) ) )
                    if sizeId > 1 then
                        local f_tmp2=self:append(field.sebits(string.format("scaling_list_dc_coef_minus8[%d][%d]", sizeId-2, matrixId)))
                        nextCoef = f_tmp2.value + 8
                    end

                    for i=0, coefNum-1 do
                        local f_scaling_list_delta_coef = self:append(field.sebits("scaling_list_delta_coef"))
                        nextCoef = ( nextCoef + f_scaling_list_delta_coef.value + 256 ) % 256
                        --ScalingList[ sizeId ][ matrixId ][ i ] = nextCoef
                    end
                end
            end
        end

    end)
    return f
end

local function field_st_ref_pic_set(stRpsIdx, num_short_term_ref_pic_sets )
    local f = field.bit_list(string.format("st_ref_pic_set[%d]", stRpsIdx), nil, function(self, ba)

        local NumNegativePics = {}
        local NumPositivePics = {}
        local NumDeltaPocs = {}

        local inter_ref_pic_set_prediction_flag = 0
        if stRpsIdx ~= 0 then
            local f_tmp = self:append(field.ubits("inter_ref_pic_set_prediction_flag", 1))       
            inter_ref_pic_set_prediction_flag = f_tmp.value
        end
        if 0 ~= inter_ref_pic_set_prediction_flag then
            if stRpsIdx == num_short_term_ref_pic_sets then
                self:append(field.uebits("delta_idx_minus1"))
            end
            self:append(field.ubits("delta_rps_sign", 1))
            self:append(field.uebits("abs_delta_rps_minus1"))
            for j=0, NumDeltaPocs[stRpsIdx] do
                local f_used_by_curr_pic_flag = self:append(field.ubits(string.format("used_by_curr_pic_flag[%d]", j)), 1)
                if 0 == f_used_by_curr_pic_flag.value then
                    self:append(field.ubits(string.format("use_delta_flag[%d]", j), 1))
                end
            end
        else
            local f_num_negative_pics = self:append(field.uebits("num_negative_pics"))
            local f_num_positive_pics = self:append(field.uebits("num_positive_pics"))
            for i=0, f_num_negative_pics.value-1 do
                self:append(field.uebits(string.format("delta_poc_s0_minus1[%d]", i)))
                self:append(field.ubits(string.format("used_by_curr_pic_s0_flag[%d]", i), 1))
            end
            for i=0, f_num_positive_pics.value-1 do
                self:append(field.uebits(string.format("delta_poc_s1_minus1[%d]", i)))
                self:append(field.ubits(string.format("used_by_curr_pic_s1_flag[%d]", i), 1))
            end
            NumNegativePics[stRpsIdx] = f_num_negative_pics.value
            NumPositivePics[stRpsIdx] = f_num_positive_pics.value
            NumDeltaPocs[stRpsIdx] = NumNegativePics[stRpsIdx] + NumPositivePics[stRpsIdx]
        end

    end)
    return f
end

local function field_sps(ebsp_len, nal)
    local f = field.bit_list("SPS", ebsp_len, function(self, ba)
        self:append( field.ubits("sps_video_parameter_set_id", 4) )

        local sps_ext_or_max_sub_layers_minus1 = 0
        local sps_max_sub_layers_minus1 = 0
        if nal.nuh_layer_id == 0 then
            local f_tmp = self:append( field.ubits("sps_max_sub_layers_minus1", 3) )
            sps_max_sub_layers_minus1 = f_tmp.value
        else
            local f_tmp = self:append( field.ubits("sps_ext_or_max_sub_layers_minus1", 3) )
            sps_ext_or_max_sub_layers_minus1 = f_tmp.value
        end

        local multi_layer_ext_sps_flag = ( nal.nuh_layer_id ~= 0 and sps_ext_or_max_sub_layers_minus1 == 7 )
        if not multi_layer_ext_sps_flag then
            self:append( field.ubits("sps_temporal_id_nesting_flag", 1) )
            field_profile_tier_level( self, sps_max_sub_layers_minus1 )
        end

        self:append( field.uebits("sps_seq_parameter_set_id" ) )

        if multi_layer_ext_sps_flag then
            local f_update_rep_format_flag = self:append( field.ubits("update_rep_format_flag", 1) )
            if f_update_rep_format_flag.value ~= 0 then
                self:append( field.ubits("sps_rep_format_idx", 8) )
            end
        else
            local f_chroma_format_idc = self:append( field.uebits("chroma_format_idc") )
            if f_chroma_format_idc.value == 3 then
                self:append( field.ubits("separate_colour_plane_flag", 1) )
            end
            self:append( field.uebits("pic_width_in_luma_samples") )
            self:append( field.uebits("pic_height_in_luma_samples") )
            local f_conformance_window_flag = self:append( field.ubits("conformance_window_flag", 1) )
            if f_conformance_window_flag.value ~= 0 then
                self:append( field.uebits("conf_win_left_offset") )
                self:append( field.uebits("conf_win_right_offset") )
                self:append( field.uebits("conf_win_top_offset") )
                self:append( field.uebits("conf_win_bottom_offset") )
            end
            
            self:append( field.uebits("bit_depth_luma_minus8") )
            self:append( field.uebits("bit_depth_chroma_minus8") )
        end

        local f_log2_max_pic_order_cnt_lsb_minus4 = self:append( field.uebits("log2_max_pic_order_cnt_lsb_minus4") )

        if not multi_layer_ext_sps_flag then
            self:append( field.ubits("sps_sub_layer_ordering_info_present_flag", 1) )
            local n = 0
            if sps_sub_layer_ordering_info_present_flag == 0 then
                n = sps_max_sub_layers_minus1
            end
            for i=n, sps_max_sub_layers_minus1 do
                self:append( field.uebits(string.format("sps_max_dec_pic_buffering_minus1[%d]", i)) )
                self:append( field.uebits(string.format("sps_max_num_reorder_pics[%d]", i)) )
                self:append( field.uebits(string.format("sps_max_latency_increase_plus1[%d]", i)) )
            end
        end

        self:append( field.uebits("log2_min_luma_coding_block_size_minus3") )
        self:append( field.uebits("log2_diff_max_min_luma_coding_block_size") )
        self:append( field.uebits("log2_min_luma_transform_block_size_minus2") )
        self:append( field.uebits("log2_diff_max_min_luma_transform_block_size") )
        self:append( field.uebits("max_transform_hierarchy_depth_inter") )
        self:append( field.uebits("max_transform_hierarchy_depth_intra") )
        local f_scaling_list_enabled_flag = self:append( field.ubits("scaling_list_enabled_flag", 1) )
        if 0 ~= f_scaling_list_enabled_flag.value then
            local f_sps_scaling_list_data_present_flag = self:append( field.ubits("sps_scaling_list_data_present_flag", 1) )
            if 0 ~= f_sps_scaling_list_data_present_flag.value then
                self:append( field_scaling_list_data() )
            end
        end

        self:append( field.ubits("amp_enabled_flag", 1) )
        self:append( field.ubits("sample_adaptive_offset_enabled_flag", 1) )
        local f_pcm_enabled_flag = self:append( field.ubits("pcm_enabled_flag", 1) )

        if f_pcm_enabled_flag.value ~= 0 then
            self:append(field.ubits("pcm_sample_bit_depth_luma_minus1", 4))
            self:append(field.ubits("pcm_sample_bit_depth_chroma_minus1", 4))
            self:append(field.uebits("log2_min_pcm_luma_coding_block_size_minus3"))
            self:append(field.uebits("log2_diff_max_min_pcm_luma_coding_block_size"))
            self:append(field.ubits("pcm_loop_filter_disabled_flag", 1))
        end

        local f_num_short_term_ref_pic_sets = self:append(field.uebits("num_short_term_ref_pic_sets"))
--[[
        for i=0, f_num_short_term_ref_pic_sets.value-1 do
            self:append( field_st_ref_pic_set(i, f_num_short_term_ref_pic_sets.value) )
        end

        local f_long_term_ref_pics_present_flag = self:append(field.ubits("long_term_ref_pics_present_flag", 1))
        if f_long_term_ref_pics_present_flag.value ~= 0 then
            local f_num_long_term_ref_pics_sps = self:append( field.uebits("num_long_term_ref_pics_sps") )

            for i=0, f_num_long_term_ref_pics_sps.value-1 do
                self:append(field.ubits(string.format("lt_ref_pic_poc_lsb_sps[%d]", i), f_log2_max_pic_order_cnt_lsb_minus4.value + 4))
                self:append(field.ubits(string.format("used_by_curr_pic_lt_sps_flag[%d]", i), 1))
            end
        end

        self:append( field.ubits("temporal_mvp_enabled_flag", 1) )
        self:append( field.ubits("strong_intra_smoothing_enabled_flag", 1) )
        local f_vui_parameters_present_flag = self:append( field.ubits("vui_parameters_present_flag", 1) )

        if f_vui_parameters_present_flag.value ~= 0 then
            --parse_vui_parameters
            --gst_h265_parse_vui_parameters (sps, &nr)
        end
--]]


        --[[

  READ_UINT8 (&nr, sps->sps_extension_flag, 1);

  /* calculate ChromaArrayType */
  if (sps->separate_colour_plane_flag)
    sps->chroma_array_type = 0;
  else
    sps->chroma_array_type = sps->chroma_format_idc;

  /* Calculate  width and height */
  sps->width = sps->pic_width_in_luma_samples;
  sps->height = sps->pic_height_in_luma_samples;
  if (sps->width < 0 || sps->height < 0) {
    GST_WARNING ("invalid width/height in SPS");
    goto error;
  }
  sps->fps_num = 0;
  sps->fps_den = 1;

  if (vui && vui->timing_info_present_flag) {
    /* derive framerate for progressive stream if the pic_struct
     * syntax element is not present in picture timing SEI messages */
    /* Fixme: handle other cases also */
    if (parse_vui_params && vui->timing_info_present_flag
        && !vui->field_seq_flag && !vui->frame_field_info_present_flag) {
      sps->fps_num = vui->time_scale;
      sps->fps_den = vui->num_units_in_tick;
      printf("framerate %d/%d", sps->fps_num, sps->fps_den);
    }
  } else {
    printf("No VUI, unknown framerate");
  }
        --]]

    end)

    return f
end

local function field_pps(ebsp_len, nal)
end

local function field_nalu(h265, index, pos, raw_data, raw_data_len, ebsp_len)

    local nal = nal_t.new()
    h265.nal = nal

    local f_nalu = field.list("NALU", raw_data_len, function(self, ba)
        local pos_start = ba:position()

        self:append( field.callback("SYNTAX", function(self, ba)
                if ba:peek_uint24() == 0x10000 then
                    return ba:read_uint24(), 3
                elseif ba:peek_uint32() == 0x1000000 then
                    return ba:read_uint32(), 4
                end
                return nil
            end, function(self)
                return string.format("%s: 0x%X", self.name, self.value)
            end, function(self)
                return string.format(" S:0x%X ", self.value)
            end) )

        local f_nalu_header = self:append( field_nalu_header() )

        local ebsp_len = raw_data_len - (ba:position()-pos_start)

        self:append( field.select("EBSP", ebsp_len, function() 
                local t = f_nalu_header.nalu_type

                nal.nal_unit_type = t
                nal.nuh_layer_id = f_nalu_header.nuh_layer_id
                nal.temporal_id = f_nalu_header.temporal_id

                if t == NALU_TYPE.VPS_NUT then return field_vps(ebsp_len, nal) end
                if t == NALU_TYPE.SPS_NUT then return field_sps(ebsp_len, nal) end
                if t == NALU_TYPE.PPS_NUT then return field_pps(ebsp_len, nal) end

            end, nil, nil) )

    end, function(self)
        --NALU cb_desc
        local brief = self:get_child_brief()
        local bmp_flag = "✓"
        if nil == self.bmp then
            bmp_flag = " " --"✗"
        end
        return string.format("[%d] %s %s%s POS:%u LEN:%d", index, bmp_flag, self.name, brief, pos, raw_data_len)
    end)

    f_nalu.cb_click = function(self)
        if nil == self.bmp then 
            bi.clear_bmp()
            return 
        end
        local bmp = self.bmp
        bi.draw_bmp(bmp.data, bmp.w, bmp.h)

        --bi.save_bmp(string.format("%s/d_%d.bmp", f_nalu.index), bi.get_tmp_dir(), bmp.data, bmp.w, bmp.h)
    end

    --field nalu dump self data
    f_nalu:set_raw_data(raw_data)
    return f_nalu
end

local nalu_syntax24 = string.pack("I3", 0x10000)
local nalu_syntax32 = string.pack("I4", 0x1000000)

local function find_nalu_syntax(ba)
    local i24_pos = ba:search(nalu_syntax24, 3)
    if i24_pos < 0 then
        return -1
    end

    if i24_pos > ba:position() and ba:cmp(i24_pos-1, nalu_syntax32, 4) == 0 then
        --start with 00 00 00 01
        return i24_pos-1, 4
    end

    --start with 00 00 01
    return i24_pos, 3
end

local function find_nalu(ba)

    local data = nil

    local old_pos = ba:position()

    --find first syntax
    local pos_syntax, nbyte = find_nalu_syntax(ba)
    if pos_syntax < 0 then
        return nil
    end

    local pos = ba:position()
    if pos_syntax > pos then
        --skip n bytes
        ba:read_bytes(pos_syntax - pos)
    end

    if nbyte == 3 then
        data = string.pack("I3", ba:read_uint24())
    else
        data = string.pack("I4", ba:read_uint32())
    end

    local pos_next_syntax = find_nalu_syntax(ba)

    local ebsp_len = 0
    if pos_next_syntax < 0 then
        ebsp_len = ba:length()
    elseif pos_next_syntax > 0 then
        ebsp_len = pos_next_syntax - ba:position()
    end

    if ebsp_len > 0 then
        local ebsp = ba:read_bytes(ebsp_len)
        local _, rbsp = bi.nalu_unshell(ebsp, ebsp_len)
        data = data .. rbsp
    end

    return data, pos_syntax, ebsp_len
end
local function decode_h265(ba, len)
    local h265 = h265_t.new()

    local f_h265 = field.list("H265", len, function(self, ba)

        local index = 0
        while ba:length() > 0 do
            local pos = ba:position()

            bi.set_progress_value(pos)

            local data, pos_syntax, ebsp_len = find_nalu(ba)

            if data then
                table.insert(h265.nalus, data)

                --parse unshelled nalu data
                local data_len = #data
                local nalu_ba = byte_stream(data_len)
                nalu_ba:set_data(data, data_len)
    
                --bi.log(string.format("nalu data len %d pos:%d", data_len, ba:position()))
                local fnalu = field_nalu(h265, index, pos_syntax, data, data_len, ebsp_len)
                self:append( fnalu, nalu_ba )
--[[
                local t = h265.nal.nal_unit_type
                if enable_decode_video(t) then
                    --decode data: start with nalu signature
                    local bmp_size, bmp, w, h = bi.decode_frame_to_bmp(AV_CODEC_ID.H265, data, data_len)
                    if bmp_size > 0 then
                        fnalu.bmp = {
                            data=bmp,
                            w = w,
                            h = h,
                            size = bmp_size
                        }
                        --bi.save_bmp(string.format("%s/d_%d.bmp", index), bi.get_tmp_dir(), bmp, w, h)
                    end
                end
--]]
                fnalu.index = index

                index = index + 1
            else
                break
            end
        end
    end)

    return f_h265
end

local function build_summary()
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "H265 video",
    file_ext = "h265 265",
    decode = decode_h265,
    build_summary = build_summary,

    field_nalu_header = field_nalu_header,
    field_sps = field_sps,
    field_pps = field_pps,
}

return codec
