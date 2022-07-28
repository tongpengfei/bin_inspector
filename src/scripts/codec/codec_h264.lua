require("class")
local helper = require("helper")
local field = require("field")
local fh = require("field_helper")
local json = require("cjson")

--reference
--https://www.ietf.org/rfc/rfc3984.txt
--https://github.com/ChristianFeldmann/h264Bitstream.git
--https://www.zzsin.com/article/sps_width_height.html

--nal start with [00 00 01] or [00 00 00 01]
--eg.: 00 00 00 01 67 42 80 0c

--| start code(4byte) | nal header(1byte) | nal ebsp(nbyte) |

local NALU_TYPE = {
    SLICE  = 1,    --Coded slice of a non-IDR picture
    DPA    = 2,    --Coded slice data partition A
    DPB    = 3,    --Coded slice data partition B
    DPC    = 4,    --Coded slice data partition C
    IDR    = 5,    --Coded slice of an IDR picture
    SEI    = 6,    --Supplemental enhancement information (SEI)
    SPS    = 7,    --Sequence parameter set
    PPS    = 8,    --Picture parameter set
    AUD    = 9,    --Access unit delimiter
    EOSEQ  = 10,   --End of sequence
    EOSTREAM = 11, --End of stream
    FILL   = 12,   --Filler data
    SPS_EXT = 13,  --Sequence parameter set extension

    AUX    = 19,

    STAP_A = 24,   --multiple nalu in a rtp packet
    STAP_B = 25,
    MTAP_16= 26,
    MTAP_24= 27,
    FU_A   = 28,   --partial nalu over many rtp packets
    FU_B   = 29
}

local NALU_TYPE_STR = {
    [NALU_TYPE.SLICE] = "SLICE",
    [NALU_TYPE.DPA] = "DPA",
    [NALU_TYPE.DPB] = "DPB",
    [NALU_TYPE.DPC] = "DPC",
    [NALU_TYPE.IDR] = "IDR",
    [NALU_TYPE.SEI] = "SEI",
    [NALU_TYPE.SPS] = "SPS",
    [NALU_TYPE.PPS] = "PPS",
    [NALU_TYPE.AUD] = "AUD",
    [NALU_TYPE.EOSEQ] = "EOSEQ",
    [NALU_TYPE.EOSTREAM] = "EOSTREAM",
    [NALU_TYPE.FILL] = "FILL",
    [NALU_TYPE.SPS_EXT] = "SPS_EXT",

    [NALU_TYPE.AUX] = "AUX",

    [NALU_TYPE.STAP_A] = "STAP_A",
    [NALU_TYPE.STAP_B] = "STAP_B",
    [NALU_TYPE.MTAP_16] = "MTAP_16",
    [NALU_TYPE.MTAP_24] = "MTAP_24",
    [NALU_TYPE.FU_A] = "FU_A",
    [NALU_TYPE.FU_B] = "FU_B",
}

local SLICE_TYPE = {
    P = 0,
    B = 1,
    I = 2,
    SP= 3,
    SI= 4,

    P_ONLY = 5,
    B_ONLY = 6,
    I_ONLY = 7,
    SP_ONLY = 8,
    SI_ONLY = 9,
}

local SLICE_TYPE_STR = {
    [SLICE_TYPE.P] = "P",
    [SLICE_TYPE.B] = "B",
    [SLICE_TYPE.I] = "I",
    [SLICE_TYPE.SP] = "SP",
    [SLICE_TYPE.SI] = "SI",
    [SLICE_TYPE.P_ONLY] = "P_ONLY",
    [SLICE_TYPE.B_ONLY] = "B_ONLY",
    [SLICE_TYPE.I_ONLY] = "I_ONLY",
    [SLICE_TYPE.SP_ONLY] = "SP_ONLY",
    [SLICE_TYPE.SI_ONLY] = "SI_ONLY",
}

local YUV_FORMAT = {
    YUV_Y   = 0,
    YUV_420 = 1,
    YUV_422 = 2,
    YUV_444 = 3,
}

local YUV_FORMAT_STR = {
    [YUV_FORMAT.YUV_Y] = "YUV_Y",
    [YUV_FORMAT.YUV_420] = "YUV_420",
    [YUV_FORMAT.YUV_422] = "YUV_422",
    [YUV_FORMAT.YUV_444] = "YUV_444",
}

local NALU_SAR = {
    UNSPECIFIED = 0,
    _1_1   = 1,
    _12_11 = 2,
    _10_11 = 3,
    _16_11 = 4,
    _40_33 = 5,
    _24_11 = 6,
    _20_11 = 7,
    _32_11 = 8,
    _80_33 = 9,
    _18_11 = 10,
    _15_11 = 11,
    _64_33 = 12,
    _160_99 = 13,

    EXTENDED = 255
}

local nal_t = class("nal_t")
function nal_t:ctor()
    self.nal_unit_type = 0
end

local sps_t = class("sps_t")
function sps_t:ctor()
    self.log2_max_frame_num_minus4 = 0
    self.frame_mbs_only_flag = 0
    self.pic_order_cnt_type = 0
    self.log2_max_pic_order_cnt_lsb_minus4 = 0
    self.delta_pic_order_always_zero_flag = 0
    self.chroma_format_idc = 1
    self.separate_colour_plane_flag = 0

    self.frame_cropping_flag = 0
    self.frame_crop_left_offset = 0
    self.frame_crop_right_offset = 0
    self.frame_crop_top_offset = 0
    self.frame_crop_bottom_offset = 0

    self.pic_width_in_mbs_minus1 = 0
    self.pic_height_in_map_units_minus1 = 0
end

function sps_t:calc_width_height()
    local chroma_array_type = 0
    if self.separate_colour_plane_flag == 0 then
        chroma_array_type = self.chroma_format_idc;
    end

    local sub_width_c = 0
    local sub_height_c = 0
    if chroma_array_type == 1 then
        sub_width_c = 2
        sub_height_c= 2
    elseif ChromaArrayType == 2 then
        sub_width_c = 2
        sub_height_c= 1
    elseif ChromaArrayType == 3 then
        sub_width_c = 1
        sub_height_c= 1
    end 

    local width = (self.pic_width_in_mbs_minus1 + 1) * 16
    local height = (2 - self.frame_mbs_only_flag) * (self.pic_height_in_map_units_minus1 + 1) * 16

    if self.frame_cropping_flag ~= 0 then
        local crop_unit_x = 0
        local crop_unit_y = 0

        if chroma_array_type == 0 then
            crop_unit_x = 1
            crop_unit_y = 2 - self.frame_mbs_only_flag
        elseif chroma_array_type == 1 or chroma_array_type == 2 or chroma_array_type == 3 then
            crop_unit_x = sub_width_c;
            crop_unit_y = sub_height_c * (2 - self.frame_mbs_only_flag);
        end

        width = width - crop_unit_x * (self.frame_crop_left_offset + self.frame_crop_right_offset);
        height = height - crop_unit_y * (self.frame_crop_top_offset + self.frame_crop_bottom_offset);
    end
    return width, height
end

local pps_t = class("pps_t")
function pps_t:ctor()
    self.seq_parameter_set_id = 0
    self.pic_order_present_flag = 0
    self.redundant_pic_cnt_present_flag = 0
    self.weighted_pred_flag = 0
    self.weighted_bipred_idc = 0
    self.entropy_coding_mode_flag = 0
    self.deblocking_filter_control_present_flag = 0
    self.num_slice_groups_minus1 = 0
    self.slice_group_map_type = 0
    self.pic_size_in_map_units_minus1 = 0
    self.slice_group_change_rate_minus1 = 0
    self.num_ref_idx_l0_active_minus1 = 0
    self.num_ref_idx_l1_active_minus1 = 0
end

local h264_t = class("h264_t")
function h264_t:ctor()
    self.sps = {} --sps[seq_parameter_set_id] = SPS
    self.pps = {} --pps[pps_id] = PPS
    self.nal = nil --current nal
    self.fps = 0

    self.nalus = {}
    self.fnalus = {}
end

local h264_summary_t = class("h264_summary_t")
function h264_summary_t:ctor()
    self.frame_count = 0
    self.width = 0
    self.height = 0
    self.yuv_format = "??"
    self.fps = 0
end

local g_h264 = nil

local function intlog2(x)
    local log = 0
    if x < 0 then x = 0 end

    while ((x >> log) > 0) do
        log = log+1
    end
    if log > 0 and x == 1<<(log-1) then
        log = log-1
    end
    return log;
end

local function is_slice_type(slice_type, cmp_type)
    if slice_type >= 5 then slice_type = slice_type - 5 end
    if cmp_type >= 5 then cmp_type = cmp_type - 5 end
    if slice_type == cmp_type then return true end
    return false
end

local function enable_decode_video(slice_type)
    if slice_type == NALU_TYPE.SPS then return true end
    if slice_type == NALU_TYPE.PPS then return true end
    if slice_type == NALU_TYPE.SLICE then return true end
    if slice_type == NALU_TYPE.IDR then return true end
    if slice_type == NALU_TYPE.AUX then return true end
    return false
end

local function field_scaling_list(name, ba, sizeof_scaling_list)
    local f_scaling_list = field.bit_list(name, nil, function(self, ba)

            local scaling_list = {}
            for i=1, sizeof_scaling_list do
                table.insert(scaling_list, 0)
            end
    
            local last_scale = 8;
            local next_scale = 8;
            for j=1, sizeof_scaling_list do
                if next_scale ~= 0 then
                    local delta_scale = self:append( field.sebits(ba) )

                    next_scale = ( last_scale + delta_scale.value + 256 ) % 256;
                    --useDefaultScalingMatrixFlag = ( j == 0 && next_scale == 0 );
                end

                if next_scale == 0 then
                    scaling_list[j] = last_scale
                else
                    scaling_list[j] = next_scale
                end
                last_scale = scaling_list[j];
            end
        end)
    return f_scaling_list
end

local function field_hrd_parameters(ba)
    local hrd = field.bit_list("hrd", nil, function(self, ba)

            local f_cpb_cnt_minus1 = self:append( field.uebits("cpb_cnt_minus1") )
            self:append( field.ubits("bit_rate_scale", 4) )
            self:append( field.ubits("cpb_size_scale", 4) )

            self:append( field.bit_list("cpb_cnt_minus_list", nil, function(self, ba)
                for i=0, f_cpb_cnt_minus1.value do
                    self:append( field.uebits(string.format("bit_rate_value_minus1[%d]", i)) )
                    self:append( field.uebits(string.format("cpb_size_value_minus1[%d]", i)) )
                    self:append( field.ubits(string.format("cbr_flag[%d]", i)) )
                end
            end))

            self:append( field.ubits("initial_cpb_removal_delay_length_minus1", 5) )
            self:append( field.ubits("cpb_removal_delay_length_minus1", 5) )
            self:append( field.ubits("dpb_output_delay_length_minus1", 5) )
            self:append( field.ubits("time_offset_length", 5) )
        end)
    return hrd
end

local function field_vui_parameters(ba, h264)

    local field_yui = field.bit_list("vui", nil, function(self, ba)
        local f_aspect_ratio_info_present_flag = self:append( field.ubits("aspect_ratio_info_present_flag", 1) )
        if f_aspect_ratio_info_present_flag.value ~= 0 then
            local f_aspect_ratio_idc = self:append( field.ubits("aspect_ratio_idc", 8) )
            if f_aspect_ratio_idc.value == NALU_SAR.EXTENDED then
                self:append( field.ubits("sar_width", 16) )
                self:append( field.ubits("sar_height", 16) )
            end
        end

        local f_overscan_info_present_flag = self:append( field.ubits("overscan_info_present_flag", 1) )
        if f_overscan_info_present_flag.value ~= 0 then
            self:append( field.ubits("overscan_appropriate_flag", 1) )
        end

        local f_video_signal_type_present_flag = self:append( field.ubits("video_signal_type_present_flag", 1) )
        if f_video_signal_type_present_flag.value ~= 0 then

            self:append( field.ubits("video_format", 3) )
            self:append( field.ubits("video_full_range_flag", 1) )
            local f_colour_description_present_flag = self:append( field.ubits("colour_description_present_flag", 1) )
            if f_colour_description_present_flag.value ~= 0 then
                self:append( field.ubits("colour_primaries", 8) )
                self:append( field.ubits("transfer_characteristics", 8) )
                self:append( field.ubits("matrix_coefficients", 8) )
            end
        end

        local f_chroma_loc_info_present_flag = self:append( field.ubits("chroma_loc_info_present_flag", 1) )
        if f_chroma_loc_info_present_flag.value ~= 0 then
            self:append( field.uebits("chroma_sample_loc_type_top_field") )
            self:append( field.uebits("chroma_sample_loc_type_bottom_field") )
        end

        local f_timing_info_present_flag = self:append( field.ubits("timing_info_present_flag", 1) )
        if f_timing_info_present_flag.value ~= 0 then
            self:append( field.bit_list("timing_info", nil, function(self, ba)
                local f_num_units_in_tick = self:append(field.ubits("num_units_in_tick", 32))
                local f_time_scale = self:append(field.ubits("time_scale", 32))
                local f_fixed_frame_rate_flag = self:append(field.ubits("fixed_frame_rate_flag", 1))

                local fps = f_time_scale.value / f_num_units_in_tick.value
                --if f_fixed_frame_rate_flag.value == 1 then
                    fps = fps / 2
                --end
				if h264 then
	                h264.fps = fps
				end
            end))
        end

        local f_nal_hrd_parameters_present_flag = self:append( field.ubits("nal_hrd_parameters_present_flag", 1) )
        if f_nal_hrd_parameters_present_flag.value ~= 0 then
            self:append( field_hrd_parameters(ba) )
        end

        local f_vcl_hrd_parameters_present_flag = self:append( field.ubits("vcl_hrd_parameters_present_flag", 1) )
        if f_vcl_hrd_parameters_present_flag.value ~= 0 then
            self:append( field_hrd_parameters(ba) )
        end

        if f_nal_hrd_parameters_present_flag.value ~= 0 or f_vcl_hrd_parameters_present_flag.value ~= 0 then
            self:append(field.ubits("low_delay_hrd_flag", 1) )
        end

        self:append( field.ubits("pic_struct_present_flag", 1) ) 

        local f_bitstream_restriction_flag = self:append( field.ubits("bitstream_restriction_flag", 1) )
        if f_bitstream_restriction_flag.value ~= 0 then

            self:append( field.bit_list("bitstream_restriction", nil, function(self, ba)
                self:append_list({
                    field.ubits("motion_vectors_over_pic_boundaries_flag", 1),
                    field.uebits("max_bytes_per_pic_denom"),
                    field.uebits("max_bits_per_mb_denom" ),
                    field.uebits("log2_max_mv_length_horizontal"),
                    field.uebits("log2_max_mv_length_vertical"),
                    field.uebits("num_reorder_frames"),
                    field.uebits("max_dec_frame_buffering"),
                })
            end))

        end
    end)
    return field_yui
end

local function field_sps(ebsp_len, h264)

    local f_sps = field.bit_list("SPS", ebsp_len, function(self, ba) --len:unknown

            local f_profile_idc = self:append( field.ubits("profile_idc", 8) )

            self:append_list({
                    field.ubits("constraint_set0_flag", 1),
                    field.ubits("constraint_set1_flag", 1),
                    field.ubits("constraint_set2_flag", 1),
                    field.ubits("constraint_set3_flag", 1),
                    field.ubits("constraint_set4_flag", 1),
                    field.ubits("constraint_set5_flag", 1),
                    field.ubits("reserved_zero_2bits", 2),
                    field.ubits("level_idc", 8),
                })
            local f_seq_parameter_set_id = self:append( field.uebits("seq_parameter_set_id") )

            local sps = sps_t.new()
            if h264 then
                h264.sps[f_seq_parameter_set_id.value] = sps
            end

            local v_profile_idc = f_profile_idc.value
            local cond = (v_profile_idc == 100 or
                          v_profile_idc == 110 or
                          v_profile_idc == 122 or
                          v_profile_idc == 144)
            if cond then
				local f_chroma_format_idc = self:append( field.uebits("chroma_format_idc", fh.mkdesc(YUV_FORMAT_STR)) )
                sps.chroma_format_idc = f_chroma_format_idc.value

				if f_chroma_format_idc.value == 3 then
					local f_separate_colour_plane_flag = self:append( field.ubits("separate_colour_plane_flag", 1) )
                    sps.separate_colour_plane_flag = f_separate_colour_plane_flag.value
				end

	            self:append_list( {
                        field.uebits("bit_depth_luma_minus8"),
                        field.uebits("bit_depth_chroma_minus8"),
                        field.ubits("qpprime_y_zero_transform_bypass_flag", 1),
                    })

                local f_seq_scaling_matrix_present_flag = self:append( field.ubits("seq_scaling_matrix_present_flag", 1) )

                if f_seq_scaling_matrix_present_flag.value ~= 0 then
                    for i=1, 8 do

                        local f_seq_scaling_list_present_flag = self:append( field.ubits("seq_scaling_list_present_flag_" .. i, 1) )
                        if f_seq_scaling_matrix_present_flag.value ~= 0 then
                            if i < 6 then
                                self:append( field_scaling_list("scaling_list_4x4", ba, 16) )
                            else
                                self:append( field_scaling_list("scaling_list_8x8", ba, 64) )
                            end
                        end
                    end
                end
            end

            local f_log2_max_frame_num_minus4 = self:append( field.uebits("log2_max_frame_num_minus4") )
            sps.log2_max_frame_num_minus4 = f_log2_max_frame_num_minus4.value

            
            local f_pic_order_cnt_type = self:append( field.uebits("pic_order_cnt_type") )
            sps.pic_order_cnt_type = f_pic_order_cnt_type.value

            if f_pic_order_cnt_type.value == 0 then
                local f_log2_max_pic_order_cnt_lsb_minus4 = self:append( field.uebits("log2_max_pic_order_cnt_lsb_minus4") )
                sps.log2_max_pic_order_cnt_lsb_minus4 = f_log2_max_pic_order_cnt_lsb_minus4.value
            elseif f_pic_order_cnt_type.value == 1 then

                local f_delta_pic_order_always_zero_flag =  self:append( field.ubits( "delta_pic_order_always_zero_flag", 1) )
                sps.delta_pic_order_always_zero_flag = f_delta_pic_order_always_zero_flag.vlaue

                self:append( field.sebits( "offset_for_non_ref_pic" ) )

                self:append( field.sebits( "offset_for_top_to_bottom_field" ) )
                local f_num_ref_frames_in_pic_order_cnt_cycle = self:append( field.uebits( "num_ref_frames_in_pic_order_cnt_cycle" ) )
                for i=0, f_num_ref_frames_in_pic_order_cnt_cycle.value-1 do
                    self:append( field.sebits( "offset_for_ref_frame_" .. i ) )
                end
            end

            --bi.log("read num_ref_frames")

            self:append( field.uebits("num_ref_frames") )
            self:append( field.ubits("gaps_in_frame_num_value_allowed_flag", 1) )

            local f_pic_width_in_mbs_minus1 = self:append( field.uebits("pic_width_in_mbs_minus1", 
                        function(self)
                            return string.format("[%2d bits] %s %d (%d)", self.len, self.name, self.value, (self.value+1)*16)
                        end, function(self)
                            local width, _ = sps:calc_width_height()
                            return string.format("%dx", width)
                        end) )
            sps.pic_width_in_mbs_minus1 = f_pic_width_in_mbs_minus1.value

            local f_pic_height_in_map_units_minus1 = self:append( field.uebits("pic_height_in_map_units_minus1", 
                        function(self)
                            return string.format("[%2d bits] %s %d (%d)", self.len, self.name, self.value, (self.value+1)*16)
                        end, function(self)
                            local _, height = sps:calc_width_height()
                            return string.format("%d", height)
                        end) )
            sps.pic_height_in_map_units_minus1 = f_pic_height_in_map_units_minus1.value

            local f_frame_mbs_only_flag = self:append( field.ubits("frame_mbs_only_flag", 1) )
            sps.frame_mbs_only_flag = f_frame_mbs_only_flag.value

            if f_frame_mbs_only_flag.value == 0 then
                self:append( field.ubits("mb_adaptive_frame_field_flag", 1) )
            end

            self:append( field.ubits("direct_8x8_inference_flag", 1) )

            local f_frame_cropping_flag = self:append( field.ubits("frame_cropping_flag", 1) )
            if f_frame_cropping_flag.value ~= 0 then
                sps.frame_cropping_flag = f_frame_cropping_flag.value

                self:append( field.bit_list("frame_crop", nil, function(self, ba)
                    local f_frame_crop_left_offset = self:append( field.uebits("frame_crop_left_offset") )
                    local f_frame_crop_right_offset = self:append( field.uebits("frame_crop_right_offset") )
                    local f_frame_crop_top_offset = self:append( field.uebits("frame_crop_top_offset") )
                    local f_frame_crop_bottom_offset = self:append( field.uebits("frame_crop_bottom_offset") )

                    sps.frame_crop_left_offset = f_frame_crop_left_offset.value
                    sps.frame_crop_right_offset = f_frame_crop_right_offset.value
                    sps.frame_crop_top_offset = f_frame_crop_top_offset.value
                    sps.frame_crop_bottom_offset = f_frame_crop_bottom_offset.value
                end))
            end

            local f_vui_parameters_present_flag = self:append( field.ubits("vui_parameters_present_flag", 1) )
            if f_vui_parameters_present_flag.value ~= 0 then
                self:append( field_vui_parameters(ba, h264) )
            end

            --read_rbsp_trailing_bits(h, b);
        end)
    return f_sps
end

local function more_rbsp_data(ba)
    if ba:length() <= 0 then return 0 end
    if ba:peek_ubits(1) == 1 then return 0 end --if next bit is 1, we've reached the stop bit
    return 1;
end

local function field_pps(ebsp_len, h264)
    local f_pps = field.bit_list("PPS", ebsp_len, function(self, ba)

            local f_pps_id = self:append( field.uebits("pps_id") )

            local pps = pps_t.new()
            if h264 then
                h264.pps[f_pps_id.value] = pps
            end

            local f_seq_parameter_set_id = self:append( field.uebits("seq_parameter_set_id") )
            pps.seq_parameter_set_id = f_seq_parameter_set_id.value

            local f_entropy_coding_mode_flag = self:append( field.ubits("entropy_coding_mode_flag", 1) )
            pps.entropy_coding_mode_flag = f_entropy_coding_mode_flag.value

            local f_pic_order_present_flag = self:append( field.ubits("pic_order_present_flag", 1) )
            pps.pic_order_present_flag = f_pic_order_present_flag.value 

            local f_num_slice_groups_minus1 = self:append( field.uebits("num_slice_groups_minus1") )
            pps.num_slice_groups_minus1 = f_num_slice_groups_minus1.value 

            if f_num_slice_groups_minus1.value > 0 then
                local f_slice_group_map_type = self:append( field.uebits("slice_group_map_type") )
                pps.slice_group_map_type = f_slice_group_map_type.value 

                local v_slice_group_map_type = f_slice_group_map_type.value
                if v_slice_group_map_type == 0 then

                    self:append( field.bit_list("run_length_minus1_list", nil, function(self, ba)
                        for i=0, f_num_slice_groups_minus1.value do
                            self:append( field.uebits(string.format("run_length_minus1[%d]", i)) )
                        end
                    end))
                end

            elseif v_slice_group_map_type == 2 then
                self:append( field.bit_list("run_length_minus1_list", nil, function(self, ba)
                    for i=0, f_num_slice_groups_minus1.value-1 do
                        self:append( field.uebits(string.format("top_left[%d]", i)) )
                        self:append( field.uebits(string.format("bottom_right[%d]", i)) )
                    end
                end))

            elseif v_slice_group_map_type == 3 or v_slice_group_map_type == 4 or v_slice_group_map_type == 5 then
                self:append( field.ubits("slice_group_change_direction_flag", 1) )
                local f_slice_group_change_rate_minus1 = self:append( field.uebits("slice_group_change_rate_minus1" ) )
                pps.slice_group_change_rate_minus1 = f_slice_group_change_rate_minus1.value 

            elseif v_slice_group_map_type == 6 then
                local f_pic_size_in_map_units_minus1 = self:append( field.uebits("pic_size_in_map_units_minus1") )
                pps.pic_size_in_map_units_minus1 = f_pic_size_in_map_units_minus1.value 

                for i=0, f_pic_size_in_map_units_minus1.value do
                    local nbits = intlog2( f_num_slice_groups_minus1.value + 1 )
                    self:append( field.ubits(string.format("slice_group_id[%d]", i), nbits ))
                end
            end

            local f_num_ref_idx_l0_active_minus1 = self:append( field.uebits("num_ref_idx_l0_active_minus1") )
            pps.num_ref_idx_l0_active_minus1 = f_num_ref_idx_l0_active_minus1.value 

            local f_num_ref_idx_l1_active_minus1 = self:append( field.uebits("num_ref_idx_l1_active_minus1") )
            pps.num_ref_idx_l1_active_minus1 = f_num_ref_idx_l1_active_minus1.value

            local f_weighted_pred_flag = self:append( field.ubits("weighted_pred_flag", 1) )
            pps.weighted_pred_flag = f_weighted_pred_flag.value

            local f_weighted_bipred_idc = self:append( field.ubits("weighted_bipred_idc", 2) )
            pps.weighted_bipred_idc = f_weighted_bipred_idc.value

            self:append( field.sebits("pic_init_qp_minus26") )
            self:append( field.sebits("pic_init_qs_minus26") )
            self:append( field.sebits("chroma_qp_index_offset") )
            local f_deblocking_filter_control_present_flag = self:append( field.ubits("deblocking_filter_control_present_flag", 1) )
            pps.deblocking_filter_control_present_flag = f_deblocking_filter_control_present_flag.value 

            self:append( field.ubits("constrained_intra_pred_flag", 1) )
            local f_redundant_pic_cnt_present_flag = self:append( field.ubits("redundant_pic_cnt_present_flag", 1) )
            pps.redundant_pic_cnt_present_flag = f_redundant_pic_cnt_present_flag.value

            local more_rbsp_data_present = more_rbsp_data(ba)
            if more_rbsp_data_present ~= 0 then
                local f_transform_8x8_mode_flag = self:append( field.ubits("transform_8x8_mode_flag", 1) )
                local f_pic_scaling_matrix_present_flag = self:append( field.ubits("pic_scaling_matrix_present_flag", 1) )
                if f_pic_scaling_matrix_present_flag.value ~= 0 then

                    self:append( field.bit_list("pic_scaling_list", nil, function(self, ba)

                        local loop = 6 + 2*f_transform_8x8_mode_flag.value - 1

                        for i=0, loop do

                            local f_pic_scaling_list_present_flag = self:append(
                                field.ubits(string.format("pic_scaling_list_present_flag[%d]", i), 1) )

                            if f_pic_scaling_list_present_flag.value ~= 0 then
                                if i < 6 then
                                    self:append( field_scaling_list("scaling_list_4x4", ba, 16) )
                                else
                                    self:append( field_scaling_list("scaling_list_4x4", ba, 64) )
                                end
                            end
                        end

                    end))

                end
                self:append( field.sebits("second_chroma_qp_index_offset") )

            end

        end)
    return f_pps
end


local function field_ref_pic_list_reordering(h264, ba, slice_type)

    if false == is_slice_type( slice_type, SLICE_TYPE.I ) and false == is_slice_type( slice_type, SLICE_TYPE.SI ) then
        local field_ref_pic_list_reordering = field.bit_list("ref_pic_list_reordering", nil, function(self, ba)


            local f_ref_pic_list_reordering_flag_l0 = self:append( field.ubits("ref_pic_list_reordering_flag_l0", 1) )
            if f_ref_pic_list_reordering_flag_l0.value ~= 0 then

                local f_reordering_of_pic_nums_idc = self:append( field.uebits("reordering_of_pic_nums_idc") )
                local index = 0
                while f_reordering_of_pic_nums_idc.value ~= 3 do
                    if f_reordering_of_pic_nums_idc.value == 0 or f_reordering_of_pic_nums_idc.value == 1 then
                        self:append( field.uebits(string.format("abs_diff_pic_num_minus1[%d]", index)))
                    elseif f_reordering_of_pic_nums_idc.value == 2 then
                        self:append( field.uebits(string.format("long_term_pic_num[%d]", index)))
                    end

                    index = index + 1

                    if ba:length() <= 0 then break end
                    f_reordering_of_pic_nums_idc = self:append( field.uebits("reordering_of_pic_nums_idc") )
                end

            end
        end)

        return field_ref_pic_list_reordering
    end

    if is_slice_type( slice_type, SLICE_TYPE.B ) then

        local field_ref_pic_list_reordering = field.bit_list("ref_pic_list_reordering", nil, function(self, ba)
            local f_ref_pic_list_reordering_flag_l1 = self:append(field.ubits("ref_pic_list_reordering_flag_l1", 1))
            if f_ref_pic_list_reordering_flag_l1.value ~= 0 then

                local index = 0
                local f_reordering_of_pic_nums_idc = self:append( field.uebits("reordering_of_pic_nums_idc") )
                while f_reordering_of_pic_nums_idc.value ~= 3 do
                    if f_reordering_of_pic_nums_idc.value == 0 or f_reordering_of_pic_nums_idc.value == 1 then
                        self:append( field.uebits(string.format("abs_diff_pic_num_minus1[%d]", index)) )
                    elseif f_reordering_of_pic_nums_idc.value == 2 then
                        self:append( field.uebits(string.format("long_term_pic_num[%d]", index) ))
                    end

                    index = index + 1

                    if ba:length() <= 0 then break end
                    f_reordering_of_pic_nums_idc = self:append( field.uebits("reordering_of_pic_nums_idc") )
                end

            end
        end)
        return field_ref_pic_list_reordering
    end
    return nil
end

local function field_pred_weight_table(h264, ba, slice_type, sps, pps)
    local f = field.bit_list("pred_weight_table", nil, function(self, ba)

        self:append( field.uebits("luma_log2_weight_denom") )
        if sps.chroma_format_idc ~= 0 then
            self:append( field.uebits("chroma_log2_weight_denom") )
        end
        for i=0, pps.num_ref_idx_l0_active_minus1 do
            local f_luma_weight_l0_flag = self:append(field.ubits(string.format("luma_weight_l0_flag[%d]", i), 1))

            if f_luma_weight_l0_flag.value ~= 0 then
                self:append( field.sebits(string.format("luma_weight_l0[%d]", i)) )
                self:append( field.sebits(string.format("luma_offset_l0[%d]", i)) )
            end
            if sps.chroma_format_idc ~= 0 then
                local f_chroma_weight_l0_flag = self:append(field.ubits(string.format("chroma_weight_l0_flag[%d]", i), 1))
                if f_chroma_weight_l0_flag.value ~= 0 then
                    for j =0, 1 do
                        self:append(field.sebits(string.format("chroma_weight_l0[%d][%d]", i, j)))
                        self:append(field.sebits(string.format("chroma_offset_l0[%d][%d]", i, j)))
                    end
                end
            end
        end

        if is_slice_type( slice_type, SLICE_TYPE.B ) then
            for i=0, pps.num_ref_idx_l1_active_minus1 do
                local f_luma_weight_l1_flag = self:append(field.ubits(string.format("luma_weight_l1_flag[%d]", i), 1))
                if f_luma_weight_l1_flag.value ~= 0 then
                    self:append(field.sebits(string.format("luma_weight_l1[%d]", i)))
                    self:append(field.sebits(string.format("luma_offset_l1[%d]", i)))
                end
                if sps.chroma_format_idc ~= 0 then
                    local f_chroma_weight_l1_flag = self:append(field.ubits(string.format("chroma_weight_l1_flag[%d]", i), 1))

                    if f_chroma_weight_l1_flag.value ~= 0 then
                        for j=0, 1 do
                            self:append(field.sebits(string.format("chroma_weight_l1[%d][%d]", i, j)))
                            self:append(field.sebits(string.format("chroma_offset_l1[%d][%d]", i, j)))
                        end
                    end
                end
            end
        end
    end)
    return f
end

local function field_slice_header(h264)

    local hdr = field.bit_list("SLICE_HEADER", nil, function(self, ba)

            self:append( field.uebits("first_mb_in_slice") )
            local f_slice_type = self:append( field.uebits("slice_type", fh.mkdesc(SLICE_TYPE_STR) ) )
            local slice_type = f_slice_type.value
            self.slice_type = slice_type
            local f_pic_parameter_set_id = self:append( field.uebits("pic_parameter_set_id") )

            local pps = h264.pps[f_pic_parameter_set_id.value]
            if nil == pps then return end

            local sps = h264.sps[pps.seq_parameter_set_id]
            if nil == sps then return end

            local nal = h264.nal
            if nil == nal then return end

            local f_frame_num = self:append( field.ubits("frame_num", sps.log2_max_frame_num_minus4 + 4 ) )
            local v_field_pic_flag = 0
            if sps.frame_mbs_only_flag == 0 then
                local f_field_pic_flag = self:append( field.ubits("field_pic_flag", 1) )
                v_field_pic_flag = f_field_pic_flag.value
                if f_field_pic_flag.value ~= 0 then
                    self:append( field.ubits("bottom_field_flag", 1) )
                end
            end
            if nal.nal_unit_type == 5 then
                self:append( field.uebits("idr_pic_id") )
            end

            if sps.pic_order_cnt_type == 0 then
                self:append( field.ubits("pic_order_cnt_lsb", sps.log2_max_pic_order_cnt_lsb_minus4+4 ) )
                if pps.pic_order_present_flag ~= 0 and v_field_pic_flag == 0 then
                    self:append( field.sebits("delta_pic_order_cnt_bottom") )
                end
            end

            if sps.pic_order_cnt_type == 1 and sps.delta_pic_order_always_zero_flag == 0 then
                self:append( field.sebits("delta_pic_order_cnt[0]") )
                if( pps.pic_order_present_flag ~= 0 and v_field_pic_flag == 0 ) then
                    self:append( field.sebits("delta_pic_order_cnt[1]") )
                end
            end

            if pps.redundant_pic_cnt_present_flag ~= 0 then
                self:append( field.uebits("redundant_pic_cnt") )
            end

            if( is_slice_type( slice_type, SLICE_TYPE.B ) ) then
                self:append( field.ubits("direct_spatial_mv_pred_flag", 1) )
            end
           
            if  is_slice_type( slice_type, SLICE_TYPE.P ) or
                is_slice_type( slice_type, SLICE_TYPE.SP ) or 
                is_slice_type( slice_type, SLICE_TYPE.B ) then
                local f_num_ref_idx_active_override_flag = field.ubits("num_ref_idx_active_override_flag", 1)
                if f_num_ref_idx_active_override_flag.value ~= 0 then
                    self:append( field.uebits("num_ref_idx_l0_active_minus1") )
                    if is_slice_type( slice_type, SLICE_TYPE.B ) then
                        self:append( field.uebits("num_ref_idx_l1_active_minus1") )
                    end
                end
            end

            local f_ref_pic_list_reordering = field_ref_pic_list_reordering(h264, ba, slice_type)
            if nil ~= f_ref_pic_list_reordering then
                self:append( f_ref_pic_list_reordering )
            end

            local is_p = is_slice_type(slice_type, SLICE_TYPE.P) or is_slice_type(slice_type, SLICE_TYPE.SP)
            local is_b = is_slice_type(slice_type, SLICE_TYPE.B)
            if (pps.weighted_pred_flag ~= 0 and is_p) or (pps.weighted_bipred_idc == 1 and is_b) then
                self:append( field_pred_weight_table(h264, ba, slice_type, sps, pps) )
            end

            if nal.nal_ref_idc ~= 0 then
                --TODO read_dec_ref_pic_marking
            end

            --[[
            if pps.entropy_coding_mode_flag ~= 0 and 
                    false == is_slice_type(slice_type, SLICE_TYPE.I) and
                    false == is_slice_type(slice_type, SLICE_TYPE.SI) then

                self:append( field.uebits("cabac_init_idc") )
            end

            if is_slice_type(slice_type, SLICE_TYPE.SP) or is_slice_type(slice_type, SLICE_TYPE.SI) then
                if is_slice_type( slice_type, SLICE_TYPE.SP) then
                    self:append( field.ubits("sp_for_switch_flag", 1) )
                end
                self:append( field.sebits("slice_qs_delta") )
            end
            --]]

            --TODO
        end)
    return hdr
end

local function field_slice(h264, typ)

    local name = NALU_TYPE_STR[typ] or "??"

    local f_slice_hdr = field_slice_header(h264)

    local slice = field.bit_list(name, nil, function(self, ba)
            self:append( f_slice_hdr )
        end, nil, function(self)
            local stype = SLICE_TYPE_STR[f_slice_hdr.slice_type] or "??"
            return string.format("%s", stype)
        end)

    return slice
end

--[[
      +---------------+
      |0|1|2|3|4|5|6|7|
      +-+-+-+-+-+-+-+-+
      |F|NRI|  Type   |
      +---------------+
--]]

local function field_nalu_header()
    local field_forbidden_bit = field.ubits("forbidden_bit", 1, nil, fh.mkbrief("F"))
    local field_nal_reference_idc = field.ubits("nal_reference_idc", 2, nil, fh.mkbrief("N"))
    local field_nal_unit_type = field.ubits("nal_unit_type", 5, fh.mkdesc(NALU_TYPE_STR), fh.mkbrief("T", NALU_TYPE_STR))

    local f = field.bit_list("NALU HEADER", 1, function(self, ba)
        self:append( field_forbidden_bit )
        self:append( field_nal_reference_idc )
        self:append( field_nal_unit_type )

        self.nalu_type = field_nal_unit_type.value
    end, nil, fh.child_brief)
    return f
end

local function field_fu_header()
    local f = field.bit_list("FU_HEADER", 1, function(self, ba)
        local f_S = self:append( field.ubits("S", 1) )
        local f_E = self:append( field.ubits("E", 1) )
        local f_R = self:append( field.ubits("R", 1) )
        local f_T = self:append( field.ubits("T", 5, fh.mkdesc(NALU_TYPE_STR), fh.mkbrief("FUT", NALU_TYPE_STR)) )

        self.fu = {
            S = f_S.value,
            E = f_E.value,
            R = f_R.value,
            T = f_T.value,
        }
    end)
    return f
end

local function field_nalu(h264, index, pos, raw_data, raw_data_len, ebsp_len)

    local nal = nal_t.new()
    h264.nal = nal

    local f_nalu = field.list("NALU", raw_data_len, function(self, ba)

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

		local tp = f_nalu_header.nalu_type
		if tp == NALU_TYPE.SPS then
			self:set_bg_color("#FFFF55")
		elseif tp == NALU_TYPE.PPS then
			self:set_bg_color("#AAAAFF")
		elseif tp == NALU_TYPE.IDR then
			self:set_bg_color("#55FF55")
		end

        self:append( field.select("EBSP", ebsp_len, function() 
                local t = f_nalu_header.nalu_type

                nal.nal_unit_type = t

                if t == NALU_TYPE.SPS then
                    h264.sps_data = raw_data                    
                    return field_sps(ebsp_len, h264) 
                end 
                if t == NALU_TYPE.PPS then
                    h264.pps_data = raw_data
                    return field_pps(ebsp_len, h264) 
                end

                if t == NALU_TYPE.SLICE then return field_slice(h264, NALU_TYPE.SLICE) end
                if t == NALU_TYPE.IDR then return field_slice(h264, NALU_TYPE.IDR) end
                if t == NALU_TYPE.AUX then return field_slice(h264, NALU_TYPE.AUX) end
            end, nil, nil) )

    end, function(self)
        --NALU cb_desc
        local brief = self:get_child_brief()
        local bmp_flag = "✓"
        if nil == self.ffh then
            bmp_flag = " " --"✗"
        end
        return string.format("[%d] %s %s%s POS:%u LEN:%d", index, bmp_flag, self.name, brief, pos, raw_data_len)
    end)

    f_nalu.cb_click = function(self)
        bi.clear_bmp()

        if nil ~= self.ffh then
            self.ffh:drawBmp()
        end
        --self.ffh:saveBmp(string.format("%s/d_%d.bmp", bi.get_tmp_dir(), f_nalu.index))
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
local function decode_h264(ba, len)
    g_h264 = h264_t.new()

    local f_h264 = field.list("H264", len, function(self, ba)

        local index = 0
        while ba:length() > 0 do
            local pos = ba:position()

            bi.set_progress_value(pos)

            local data, pos_syntax, ebsp_len = find_nalu(ba)

            if data then
                table.insert(g_h264.nalus, data)

                --parse unshelled nalu data
                local data_len = #data
                local nalu_ba = byte_stream(data_len)
                nalu_ba:set_data(data, data_len)
    
                --bi.log(string.format("nalu data len %d pos:%d", data_len, ba:position()))
                local fnalu = field_nalu(g_h264, index, pos_syntax, data, data_len, ebsp_len)
                self:append( fnalu, nalu_ba )

                table.insert( g_h264.fnalus, fnalu )

                local t = g_h264.nal.nal_unit_type
                if enable_decode_video(t) then
                    fnalu.ffh = bi.decode_avframe(AV_CODEC_ID.H264, data, data_len)
                end

                fnalu.index = index

                index = index + 1
            else
                break
            end
        end
    end)
    return f_h264
end

local function build_summary()
    if nil == g_h264 then return end
    --set summary
    local summary = h264_summary_t.new()
    summary.fps = g_h264.fps
    summary.frame_count = index
    for _, sps in pairs(g_h264.sps) do
        summary.width, summary.height = sps:calc_width_height()
        summary.yuv_format = YUV_FORMAT_STR[sps.chroma_format_idc] or "??"
        break
    end

    bi.append_summary("frame_count", #g_h264.fnalus)

    if summary.width ~= 0 then
        bi.append_summary("resolution", string.format("%dx%d", summary.width, summary.height))
    else
        bi.append_summary("resolution", "??x??")
    end
    bi.append_summary("yuv_format", summary.yuv_format)
    bi.append_summary("fps", summary.fps)
end

local function clear()
    if nil == g_h264 then return end

    --free all ffh
    for i, fnalu in ipairs(g_h264.fnalus) do
        if nil ~= fnalu.ffh then
            bi.ffmpeg_helper_free(fnalu.ffh)
        end
    end
    g_h264.fnalus = nil

    g_h264 = nil
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "H264 video",
    file_ext = "h264 264",
    decode = decode_h264,
    build_summary = build_summary,


    clear = clear,

    field_nalu_header = field_nalu_header,
    field_fu_header = field_fu_header,
    field_sps = field_sps,
    field_pps = field_pps,

    NALU_TYPE = NALU_TYPE,
    NALU_TYPE_STR = NALU_TYPE_STR
}

return codec
