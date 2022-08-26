local field = require("field")
local helper = require("helper")
local fh = require("field_helper")

--https://docs.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-image_nt_headers32
--https://0xrick.github.io/win-internals/pe8/#a-dive-into-the-pe-file-format---lab-1-writing-a-pe-parser

local terminal0 = string.pack("I1", 0x0);

local IMAGE_NUMBEROF_DIRECTORY_ENTRIES = 16
local IMAGE_DIRECTORY_ENTRY = {
    EXPORT        = 0,  -- Export Directory
    IMPORT        = 1,  -- Import Directory
    RESOURCE      = 2,  -- Resource Directory
    EXCEPTION     = 3,  -- Exception Directory
    SECURITY      = 4,  -- Security Directory
    BASERELOC     = 5,  -- Base Relocation Table
    DEBUG         = 6,  -- Debug Directory
--  COPYRIGHT     = 7,  -- (X86 usage)
    ARCHITECTURE  = 7,  -- Architecture Specific Data
    GLOBALPTR     = 8,  -- RVA of GP
    TLS           = 9,  -- TLS Directory
    LOAD_CONFIG   =10,  -- Load Configuration Directory
    BOUND_IMPORT  =11,  -- Bound Import Directory in headers
    IAT           =12,  -- Import Address Table
    DELAY_IMPORT  =13,  -- Delay Load Import Descriptors
    COM_DESCRIPTOR=14,  -- COM Runtime descriptor
    RESERVED      =15,
}

local IMAGE_DIRECTORY_ENTRY_STR = {
    [IMAGE_DIRECTORY_ENTRY.EXPORT]        = "EXPORT",                -- Export Directory
    [IMAGE_DIRECTORY_ENTRY.IMPORT]        = "IMPORT",                -- Import Directory
    [IMAGE_DIRECTORY_ENTRY.RESOURCE]      = "RESOURCE",              -- Resource Directory
    [IMAGE_DIRECTORY_ENTRY.EXCEPTION]     = "EXCEPTION",             -- Exception Directory
    [IMAGE_DIRECTORY_ENTRY.SECURITY]      = "SECURITY",              -- Security Directory
    [IMAGE_DIRECTORY_ENTRY.BASERELOC]     = "BASE_RELOC",            -- Base Relocation Table
    [IMAGE_DIRECTORY_ENTRY.DEBUG]         = "DEBUG",                 -- Debug Directory
--  COPYRIGHT     = 7,  -- (X86 usage)
    [IMAGE_DIRECTORY_ENTRY.ARCHITECTURE]  = "ARCHITECTURE",          -- Architecture Specific Data
    [IMAGE_DIRECTORY_ENTRY.GLOBALPTR]     = "GLOBALPTR",             -- RVA of GP
    [IMAGE_DIRECTORY_ENTRY.TLS]           = "TLS",                   -- TLS Directory
    [IMAGE_DIRECTORY_ENTRY.LOAD_CONFIG]   = "LOAD_CONFIG",           -- Load Configuration Directory
    [IMAGE_DIRECTORY_ENTRY.BOUND_IMPORT]  = "BOUND_IMPORT",          -- Bound Import Directory in headers
    [IMAGE_DIRECTORY_ENTRY.IAT]           = "IMPORT_ADDRESS_TABLE",  -- Import Address Table
    [IMAGE_DIRECTORY_ENTRY.DELAY_IMPORT]  = "DELAY_LOAD_IMPORT",     -- Delay Load Import Descriptors
    [IMAGE_DIRECTORY_ENTRY.COM_DESCRIPTOR]= "COM_DESCRIPTOR",        -- COM Runtime descriptor
    [IMAGE_DIRECTORY_ENTRY.RESERVED]      = "RESERVED",
}

local DICT_CONSTS = {
    IMAGE_DOS_SIGNATURE = 0x5A4D, --MZ
    IMAGE_PE_SIGNATURE = 0x4550,  --PE
    IMAGE_NT_OPTIONAL_HDR32_MAGIC = 0x10B,
    IMAGE_NT_OPTIONAL_HDR64_MAGIC = 0x20B,
}

local DICT_CONSTS_STR = {
    [DICT_CONSTS.IMAGE_DOS_SIGNATURE] = "MZ",
    [DICT_CONSTS.IMAGE_PE_SIGNATURE] = "PE",
    [DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR32_MAGIC] = "x86",
    [DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR64_MAGIC] = "x64",
}

local IMAGE_FILE = {
    RELOCS_STRIPPED         = 0x0001, -- Relocation info stripped from file.
    EXECUTABLE_IMAGE        = 0x0002, -- File is executable  (i.e. no unresolved external references).
    LINE_NUMS_STRIPPED      = 0x0004, -- Line nunbers stripped from file.
    LOCAL_SYMS_STRIPPED     = 0x0008, -- Local symbols stripped from file.
    AGGRESIVE_WS_TRIM       = 0x0010, -- Aggressively trim working set
    LARGE_ADDRESS_AWARE     = 0x0020, -- App can handle >2gb addresses
    BYTES_REVERSED_LO       = 0x0080, -- Bytes of machine word are reversed.
    _32BIT_MACHINE          = 0x0100, -- 32 bit word machine.
    DEBUG_STRIPPED          = 0x0200, -- Debugging info stripped from file in .DBG file
    REMOVABLE_RUN_FROM_SWAP = 0x0400, -- If Image is on removable media, copy and run from the swap file.
    NET_RUN_FROM_SWAP       = 0x0800, -- If Image is on Net, copy and run from the swap file.
    SYSTEM                  = 0x1000, -- System File.
    DLL                     = 0x2000, -- File is a DLL.
    UP_SYSTEM_ONLY          = 0x4000, -- File should only be run on a UP machine
    BYTES_REVERSED_HI       = 0x8000, -- Bytes of machine word are reversed.
}


local IMAGE_FILE_MACHINE = {
    UNKNOWN     = 0,
    TARGET_HOST = 0x0001, --Useful for indicating we want to interact with the host and not a WoW guest.
    I386        = 0x014c, --Intel 386.
    R3000       = 0x0162, -- MIPS little-endian, 0x160 big-endian
    R4000       = 0x0166, -- MIPS little-endian
    R10000      = 0x0168, -- MIPS little-endian
    WCEMIPSV2   = 0x0169, -- MIPS little-endian WCE v2
    ALPHA       = 0x0184, -- Alpha_AXP
    SH3         = 0x01a2, -- SH3 little-endian
    SH3DSP      = 0x01a3,
    SH3E        = 0x01a4, -- SH3E little-endian
    SH4         = 0x01a6, -- SH4 little-endian
    SH5         = 0x01a8, -- SH5
    ARM         = 0x01c0, -- ARM Little-Endian
    THUMB       = 0x01c2, -- ARM Thumb/Thumb-2 Little-Endian
    ARMNT       = 0x01c4, -- ARM Thumb-2 Little-Endian
    AM33        = 0x01d3,
    POWERPC     = 0x01F0, -- IBM PowerPC Little-Endian
    POWERPCFP   = 0x01f1,
    IA64        = 0x0200, -- Intel 64
    MIPS16      = 0x0266, -- MIPS
    ALPHA64     = 0x0284, -- ALPHA64
    MIPSFPU     = 0x0366, -- MIPS
    MIPSFPU16   = 0x0466, -- MIPS
--    AXP64       = IMAGE_FILE_MACHINE.ALPHA64,
    TRICORE     = 0x0520, -- Infineon
    CEF         = 0x0CEF,
    EBC         = 0x0EBC, -- EFI Byte Code
    AMD64       = 0x8664, -- AMD64 (K8)
    M32R        = 0x9041, -- M32R little-endian
    ARM64       = 0xAA64, -- ARM64 Little-Endian
    CEE         = 0xC0EE,
}

local IMAGE_FILE_MACHINE_STR = {
    [IMAGE_FILE_MACHINE.UNKNOWN] = "UNKNOWN",
    [IMAGE_FILE_MACHINE.TARGET_HOST] = "TARGET_HOST",
    [IMAGE_FILE_MACHINE.I386] = "I386",
    [IMAGE_FILE_MACHINE.R3000] = "R3000",
    [IMAGE_FILE_MACHINE.R4000] = "R4000",
    [IMAGE_FILE_MACHINE.R10000]= "R10000",
    [IMAGE_FILE_MACHINE.WCEMIPSV2] = "WCEMIPSV2",
    [IMAGE_FILE_MACHINE.ALPHA]    = "ALPHA",
    [IMAGE_FILE_MACHINE.SH3]      = "SH3",
    [IMAGE_FILE_MACHINE.SH3DSP]   = "SH3DSP",
    [IMAGE_FILE_MACHINE.SH3E]     = "SH3E",
    [IMAGE_FILE_MACHINE.SH4]      = "SH4",
    [IMAGE_FILE_MACHINE.SH5]      = "SH5",
    [IMAGE_FILE_MACHINE.ARM]      = "ARM",
    [IMAGE_FILE_MACHINE.THUMB]    = "THUMB",
    [IMAGE_FILE_MACHINE.ARMNT]    = "ARMNT",
    [IMAGE_FILE_MACHINE.AM33]     = "AM33",
    [IMAGE_FILE_MACHINE.POWERPC]  = "POWERPC",
    [IMAGE_FILE_MACHINE.POWERPCFP]= "POWERPCFP",
    [IMAGE_FILE_MACHINE.IA64]     = "IA64",
    [IMAGE_FILE_MACHINE.MIPS16]   = "MIPS16",
    [IMAGE_FILE_MACHINE.ALPHA64]  = "ALPHA64",
    [IMAGE_FILE_MACHINE.MIPSFPU]  = "MIPSFPU",
    [IMAGE_FILE_MACHINE.MIPSFPU16]= "MIPSFPU16",
--    [IMAGE_FILE_MACHINE.AXP64]    = "ALPHA64",
    [IMAGE_FILE_MACHINE.TRICORE]  = "TRICORE",
    [IMAGE_FILE_MACHINE.CEF]      = "CEF",
    [IMAGE_FILE_MACHINE.EBC]      = "EBC",
    [IMAGE_FILE_MACHINE.AMD64]    = "AMD64",
    [IMAGE_FILE_MACHINE.M32R]     = "M32R",
    [IMAGE_FILE_MACHINE.ARM64]    = "ARM64",
    [IMAGE_FILE_MACHINE.CEE]      = "CEE",
}

local OS_VER_STR = {
	["1.1"]  = "Windows 1.01",
	["1.2"]  = "Windows 1.02",
	["1.3"]  = "Windows 1.03",
	["1.4"]  = "Windows 1.04",
	["2.1"]  = "Windows 2.01",
	["2.3"]  = "Windows 2.03",
	["2.1"]  = "Windows 2.1",
	["2.11"] = "Windows 2.11",
	["3.0"]  = "Windows 3.0",
	["3.1"]  = "Windows 3.1",
	["3.1"]  = "Windows NT 3.1",
	["3.11"] = "Windows 3.11",
	["3.2"]  = "Windows 3.2",
	["3.5"]  = "Windows NT 3.5",
	["3.51"] = "Windows NT 3.51",
	["4.0"]  = "Windows 95",
	["4.1"]  = "Windows 98",
	["4.9"]  = "Windows Me",
	["5.0"]  = "Windows 2000",
	["5.1"]  = "Windows XP",
	["5.2"]  = "Windows XP",
	["6.0"]  = "Windows Vista",
	["6.1"]  = "Windows 7",
	["6.2"]  = "Windows 8",
	["6.3"]  = "Windows 8.1",
	["10.0"] = "Windows 10",
}

local SUBSYSTEM_STR = {
	[0]  = "Unknown",
	[1]  = "Native",
	[2]  = "WindowsGui",
	[3]  = "WindowsCui",
	[5]  = "OS2Cui",
	[7]  = "PosixCui",
	[8]  = "NativeWindows",
	[9]  = "WindowsCEGui",
	[10] = "EfiApplication",
	[11] = "EfiBootServiceDriver",
	[12] = "EfiRuntimeDriver",
	[13] = "EfiRom",
	[14] = "Xbox",
	[16] = "WindowsBootApplication",
}

local IMAGE_DEBUG_TYPE_STR = {
	[0] = "UNKNOWN",
	[1] = "COFF",
	[2] = "CODEVIEW",
	[3] = "FPO",
	[4] = "MISC",
	[5] = "EXCEPTION",
	[6] = "FIXUP",
	[7] = "OMAP_TO_SRC",
	[8] = "OMAP_FROM_SRC",
	[9] = "BORLAND",
	[10]= "RESERVED10",
	[11]= "CLSID",
	[12]= "VC_FEATURE",
	[13]= "POGO",
	[14]= "ILTCG",
	[15]= "MPX",
	[16]= "REPRO",
}

local image_dos_header_t = class("image_dos_header_t")
function image_dos_header_t:ctor()
	self.magic = 0 --0x5A4D MZ
	self.cblp = 0
	self.cp = 0
	self.crlc = 0
	self.cparhdr = 0
	self.minalloc = 0
	self.maxalloc = 0
	self.ss = 0
	self.sp = 0
	self.csum = 0
	self.ip = 0
	self.cs = 0
	self.lfarlc = 0
	self.ovno = 0

    self.res = {} --len: 4
    self.oemid = 0
    self.oeminfo = 0
    self.res2 = {} --len: 10
    self.lfanew = 0
end

local image_file_header_t = class("image_file_header_t")
function image_file_header_t:ctor()
    self.machine = 0
    self.number_of_sections = 0
    self.time_date_stamp = 0
    self.pointer_to_symbol_table = 0
    self.number_of_symbols = 0;
    self.size_of_optional_header = 0
    self.characteristics = 0
end

local image_data_directory_t = class("image_data_directory_t")
function image_data_directory_t:ctor()
    self.virtual_address = 0
    self.size = 0

     --tmp data
    self.id = 0
    self.offset = 0
end

local image_optional_header_t = class("image_optional_header_t")
function image_optional_header_t:ctor()

    self.magic = nil
    self.major_linker_version = nil
    self.minor_linker_version = nil
    self.size_of_code = nil
    self.size_of_initialized_data = nil
    self.size_of_uninitialized_data = nil
    self.address_of_entry_point = nil
    self.base_of_code = nil

    --if x86
    self.base_of_data = nil

    self.image_base = nil
    self.section_alignment = nil
    self.file_alignment = nil
    self.major_operating_system_version = nil
    self.minor_operating_system_version = nil
    self.major_image_version = nil
    self.minor_image_version = nil
    self.major_subsystem_version = nil
    self.minor_subsystem_version = nil
    self.win32_version_value = nil
    self.size_of_image = nil
    self.size_of_headers = nil
    self.check_sum = nil
    self.subsystem = nil
    self.dll_characteristics = nil
    self.size_of_stack_reserve = nil
    self.size_of_stack_commit = nil
    self.size_of_heap_reserve = nil
    self.size_of_heap_commit = nil
    self.loader_flags = nil
    self.number_of_rva_and_sizes = nil

    self.image_data_directoris = {}
end

local image_section_header_t = class("image_section_header_t")
function image_section_header_t:ctor()
    self.name = nil
    self.virtual_size = nil
    self.virtual_address = nil
    self.size_of_raw_data = nil
    self.pointer_to_raw_data = nil
    self.pointer_to_relocations = nil
    self.pointer_to_line_numbers = nil
    self.number_of_relocations = nil
    self.number_of_line_numbers = nil
    self.characteristics = nil
end

local image_import_descriptor_t = class("image_import_descriptor_t")
function image_import_descriptor_t:ctor()
    self.original_first_thunk = nil;
    self.time_date_stamp = nil
    self.forwarder_chain = nil
    self.name = nil
    self.first_thunk = nil

    --tmp data
    self.id = nil
    self.dll_name = nil
end

local image_import_by_name_t = class("image_import_by_name_t")
function image_import_by_name_t:ctor()
    self.hint = 0
    self.name = nil
end


local image_base_relocation_t = class("image_base_relocation_t")
function image_base_relocation_t:ctor()
    self.virtual_address = 0
    self.size_of_block = 0
--  WORD    TypeOffset[1];
end


--_IMAGE_EXPORT_DIRECTORY
local image_export_directory_t = class("image_export_directory_t")
function image_export_directory_t:ctor()
    self.characteristics = 0
    self.time_date_stamp = 0
    self.major_version = 0
    self.minor_version = 0
    self.name = 0
    self.base = 0
    self.number_of_functions = 0
    self.number_of_names = 0
    self.address_of_functions = 0
    self.address_of_names = 0
    self.address_of_name_ordinals = 0
end


--IMAGE_DIRECTORY_ENTRY.RESOURCE
local image_resource_directory_t = class("image_resource_directory_t")
function image_resource_directory_t:ctor()
    self.characteristics = 0
    self.time_date_stamp = 0
    self.major_version = 0
    self.minor_version = 0
    self.number_of_named_entries = 0
    self.number_of_id_entries = 0

--  IMAGE_RESOURCE_DIRECTORY_ENTRY DirectoryEntries[];
end


local offset_field_t = class("field_offset_t")
function offset_field_t:ctor()
    self.offset = 0
    self.field = nil
end

local export_func_info_t = class("export_func_info_t")
function export_func_info_t:ctor()
    self.address_of_function = 0
    self.address_of_name = 0
    self.address_of_ordinal = 0
    self.func_name = nil
end

local import_func_info_t = class("import_func_info_t")
function import_func_info_t:ctor()
    self.ordinal = 0
    self.func_name = nil
end

local pe_t = class("pe_t")
function pe_t:ctor()

    self.image_dos_header = nil
    self.image_file_header = nil
    self.image_optional_header = nil

    self.image_section_headers = {}

    self.image_export_directory = nil

    --tmp
    self.image_base_relocations = {}
    self.image_import_descriptors = {}

    --ilt: import lookup table
    --int: import name table
    --iat: import address table

    self.image_import_descriptor_int = {} --order by original_first_thunk
    self.image_import_descriptor_iat = {} --order by first_thunk
    self.image_import_descriptor_dll = {}  --order by name
    self.sorted_directoris = nil
    self.dict_int = {} -- import_descriptor[id] = {int, int}
    self.dict_iat = {} -- import_descriptor[id] = {iat, iat}

    self.import_dlls = {}
    self.import_funcs = {} --{ {import_func_info_t, ... }, {import_func_info_t, ...} }

    self.export_funcs = {} --{ export_func_info_t }

    self.fname = nil
    self.fpath = nil
	self.fsize = 0
    self.signature = nil
    self.is_x64 = false

    self.offset_fields = {}
end

local g_pe = nil

local function directory_rva_to_section(pe, rva)
    local nsec = pe.image_file_header.number_of_sections
    for i=1, nsec do
        local sec = pe.image_section_headers[i]
        local vmax = sec.virtual_address + sec.virtual_size

        if rva >= sec.virtual_address and rva < vmax then
            return i, sec
        end
    end
    return -1, nil
end

local function virtual_addr_to_offset(pe, rva)
    local isec, sec = directory_rva_to_section(pe, rva)
    if nil == sec then
        return -1
    end

    local offset = (rva - sec.virtual_address) + sec.pointer_to_raw_data
--    bi.log( string.format("rva 0x%X rva:0x%X pointer:0x%X offset:0x%X", rva, sec.virtual_address, sec.pointer_to_raw_data, offset) )
    return offset
end

local desc_rva_fpos = function(self)
    local offset = 0
    if self.value ~= 0 then
        offset = virtual_addr_to_offset( g_pe, self.value )
    end
    return string.format("%s %s: 0x%X (fpos:0x%X %d)", self.type, self.name, self.value, offset, offset)
end

local mkbrief_rva = function(nm)
    local f = function(self)
        local offset = 0
        if self.value ~= 0 then
            offset = virtual_addr_to_offset( g_pe, self.value )
            return string.format("%s:0x%08X (0x%X %d) ", nm, self.value, offset, offset)
        end
        return string.format("%s:%d ", nm, self.value)
    end
    return f
end

local function find_dll_path( g_pe, fname )

    local arr_path = {}

	local os = bi.get_os_name()

	--win32: c:\windows\system32
	--mac: nil
	local sys_path = bi.get_sys_path()
	if "" ~= sys_path then
		table.insert( arr_path, sys_path )
	end

	table.insert( arr_path, g_pe.fpath )

    local env_path = helper.get_env_paths()
    for _, path in ipairs(env_path) do
		local skip = false
		if "" ~= sys_path then
			local lpath = string.lower(sys_path)
			if lpath == string.lower(path) then
				skip = true
			end
		end
		if false == skip then
	        table.insert(arr_path, path)
		end
    end

    for _, path in ipairs(arr_path) do
        local full = string.format("%s/%s", path, fname)
        if true == helper.is_file_exists( full ) then
            return full
        end
    end

    return nil
end


local function field_image_dos_header()

	local f_dos = field.list("image_dos_header", nil, function(self, ba)
        local hdr = image_dos_header_t.new()

		local f_magic = self:append( field.uint16("magic", false, fh.mkdesc_x(DICT_CONSTS_STR), fh.mkbrief("", DICT_CONSTS_STR)) ) --MZ
		local f_cblp = self:append( field.uint16("cblp", false, fh.num_desc_vx) )
		local f_cp = self:append( field.uint16("cp") )
		local f_crlc = self:append( field.uint16("crlc") )
		local f_cparhdr = self:append( field.uint16("cparhdr") )
		local f_minalloc = self:append( field.uint16("minalloc") )
		local f_maxalloc = self:append( field.uint16("maxalloc") )
		local f_ss = self:append( field.uint16("ss", false, fh.num_desc_x) )
		local f_sp = self:append( field.uint16("sp", false, fh.num_desc_x) )
		local f_csum = self:append( field.uint16("csum") )
		local f_ip = self:append( field.uint16("ip", false, fh.num_desc_x) )
		local f_cs = self:append( field.uint16("cs", false, fh.num_desc_x) )
		local f_lfarlc = self:append( field.uint16("lfarlc", fh.num_desc_x) )
		local f_ovno = self:append( field.uint16("ovno") )
        for i=1, 4 do
		    local f_res = self:append( field.uint16(string.format("res[%d]", i-1)) )
            table.insert( hdr.res, f_res.value )
        end

		local f_oemid = self:append( field.uint16("oemid") )
		local f_oeminfo = self:append( field.uint16("oeminfo") )

        for i=1, 10 do
		    local f_res2 = self:append( field.uint16(string.format("res2[%d]", i-1)) )
            table.insert( hdr.res2, f_res2.value )
        end

		local f_lfanew = self:append( field.uint32("lfanew", false, nil, fh.mkbrief("lfanew")) )
        hdr.magic = f_magic.value
	    hdr.cblp = f_cblp.value
        hdr.cp = f_cp.value
        hdr.crlc = f_crlc.value
	    hdr.cparhdr = f_cparhdr.value
        hdr.minalloc = f_minalloc.value
        hdr.maxalloc = f_maxalloc.value
        hdr.ss = f_ss.value
	    hdr.sp = f_sp.value
	    hdr.csum = f_csum.value
        hdr.ip = f_ip.value
	    hdr.cs = f_cs.value
	    hdr.lfarlc = f_lfarlc.value
	    hdr.ovno = f_ovno.value
        hdr.oemid = f_oemid.value
        hdr.oeminfo = f_oeminfo.value
        hdr.lfanew = f_lfanew.value

        g_pe.image_dos_header = hdr
	end, nil, fh.child_brief)
	return f_dos
end

--[[
local function field_rich_header()
    local f = field.list("rich_header", nil, function(self, ba)
        
    end)
    return f
end

local function field_dos_stub()
    local f = field.list("dos_stub", nil, function(self, ba)
        self:append( field.string("data", 64) )
        self:append( field_rich_header() )
    end)
    return f
end
--]]

local function field_image_file_header()
    local f = field.list("image_file_header", nil, function(self, ba)
        local f_machine = self:append( field.uint16("machine", false, fh.mkdesc_x(IMAGE_FILE_MACHINE_STR), fh.mkbrief("", IMAGE_FILE_MACHINE_STR)) )
        local f_number_of_sections = self:append( field.uint16("number_of_sections", false, nil, fh.mkbrief("NSEC")) )
        local f_time_date_stamp = self:append( field.uint32("time_date_stamp", false, fh.desc_sec2date) )
        local f_pointer_to_symbol_table = self:append( field.uint32("pointer_to_symbol_table") )
        local f_number_of_symbols = self:append( field.uint32("number_of_symbols") )
        local f_size_of_optional_header = self:append( field.uint16("size_of_optional_header") )

        local characteristics = ba:peek_uint16()
        local f_characteristics = self:append( field.bit_list("characteristics", 2, function(self, bs)
--[[
            self:append( field.ubits("UNUSED") )
            self:append( field.ubits("0x0001 IMAGE_FILE_RELOCS_STRIPPED") )
            self:append( field.ubits("0x0002 IMAGE_FILE_EXECUTABLE_IMAGE") )
            self:append( field.ubits("0x0004 IMAGE_FILE_LINE_NUMS_STRIPPED") )
            self:append( field.ubits("0x0008 IMAGE_FILE_LOCAL_SYMS_STRIPPED") )
            self:append( field.ubits("0x0010 IMAGE_FILE_AGGRESIVE_WS_TRIM") )
            self:append( field.ubits("0x0020 IMAGE_FILE_LARGE_ADDRESS_AWARE") )
            self:append( field.ubits("0x0080 IMAGE_FILE_BYTES_REVERSED_LO") )
--]]

            self:append( field.ubits("0x0080 IMAGE_FILE_BYTES_REVERSED_LO") )
            self:append( field.ubits("0x0040 RESERVED") )
            self:append( field.ubits("0x0020 IMAGE_FILE_LARGE_ADDRESS_AWARE") )
            self:append( field.ubits("0x0010 IMAGE_FILE_AGGRESIVE_WS_TRIM") )
            self:append( field.ubits("0x0008 IMAGE_FILE_LOCAL_SYMS_STRIPPED") )
            self:append( field.ubits("0x0004 IMAGE_FILE_LINE_NUMS_STRIPPED") )
            self:append( field.ubits("0x0002 IMAGE_FILE_EXECUTABLE_IMAGE") )
            self:append( field.ubits("0x0001 IMAGE_FILE_RELOCS_STRIPPED") )


            self:append( field.ubits("0x8000 IMAGE_FILE_BYTES_REVERSED_HI") )
            self:append( field.ubits("0x4000 IMAGE_FILE_UP_SYSTEM_ONLY") )
            self:append( field.ubits("0x2000 IMAGE_FILE_DLL") )
            self:append( field.ubits("0x1000 IMAGE_FILE_SYSTEM") )
            self:append( field.ubits("0x0800 IMAGE_FILE_NET_RUN_FROM_SWAP") )
            self:append( field.ubits("0x0400 IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP") )
            self:append( field.ubits("0x0200 IMAGE_FILE_DEBUG_STRIPPED") )
            self:append( field.ubits("0x0100 IMAGE_FILE_32BIT_MACHINE") )
        end) )

        local hdr = image_file_header_t.new()
        hdr.machine = f_machine.value
        hdr.number_of_sections = f_number_of_sections.value
        hdr.time_date_stamp = f_time_date_stamp.value
        hdr.pointer_to_symbol_table = f_pointer_to_symbol_table.value
        hdr.number_of_symbols = f_number_of_symbols.value
        hdr.size_of_optional_header = f_size_of_optional_header.value
        hdr.characteristics = characteristics

        g_pe.image_file_header = hdr
    end)
    return f
end

local function field_image_data_directory(index, data_directory)
    local entry_name = IMAGE_DIRECTORY_ENTRY_STR[index] or ""
    local f = field.list(string.format("image_data_directory[%2d %-20s]", index, entry_name), nil, function(self, ba)
        local f_virtual_address = self:append( field.uint32("virtual_address", false, fh.num_desc_vx, function(self)
            local offset = 0
            if self.value ~= 0 then
                offset = virtual_addr_to_offset(g_pe, self.value)
            end
            return string.format("RVA: 0x%08X (fpos:0x%08X %7s) ", self.value, offset, tostring(offset))
        end))
        local f_size = self:append( field.uint32("size", false, fh.num_desc_vx, fh.mkbrief("SIZE")) )

        data_directory.id = index
        data_directory.virtual_address = f_virtual_address.value
        data_directory.size = f_size.value
    end)
    return f
end

local function field_image_optional_header()

    local len = g_pe.image_file_header.size_of_optional_header

    local f = field.list("iamge_optional_header", len, function(self, ba)
        local pos = ba:position()
        local f_magic = self:append( field.uint16("magic", false, fh.mkdesc_x(DICT_CONSTS_STR), fh.mkbrief("", DICT_CONSTS_STR)) )

        local is_x64 = false
        local field_long = nil
        if f_magic.value == DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR32_MAGIC then
            field_long = field.uint32
        elseif f_magic.value == DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR64_MAGIC then
            is_x64 = true
            field_long = field.uint64
        else
            --error
            return
        end

        local f_major_linker_version = self:append( field.uint8("major_linker_version") )
        local f_minor_linker_version = self:append( field.uint8("minor_linker_version") )
        local f_size_of_code = self:append( field.uint32("size_of_code") )
        local f_size_of_initialized_data = self:append( field.uint32("size_of_initialized_data") )
        local f_size_of_uninitialized_data = self:append( field.uint32("size_of_uninitialized_data") )
        local f_address_of_entry_point = self:append( field.uint32("address_of_entry_point", false, fh.num_desc_vx) )
        local f_base_of_code = self:append( field.uint32("base_of_code", false, fh.num_desc_vx) )

        if false == is_x64 then
            local f_base_of_data = self:append( field.uint32("base_of_data") )
        end

        local f_image_base = self:append( field_long("image_base", false, fh.num_desc_vx) )
        local f_section_alignment = self:append( field.uint32("section_alignment", false, fh.num_desc_vx) )
        local f_file_alignment = self:append( field.uint32("file_alignment", false, fh.num_desc_vx) )
        local f_major_operating_system_version = self:append( field.uint16("major_operating_system_version") )
        local f_minor_operating_system_version = self:append( field.uint16("minor_operating_system_version") )
        local f_major_image_version = self:append( field.uint16("major_image_version") )
        local f_minor_image_version = self:append( field.uint16("minor_image_version") )
        local f_major_subsystem_version = self:append( field.uint16("major_subsystem_version") )
        local f_minor_subsystem_version = self:append( field.uint16("minor_subsystem_version") )
        local f_win32_version_value = self:append( field.uint32("win32_version_value") )
        local f_size_of_image = self:append( field.uint32("size_of_image", false, fh.num_desc_vx) )
        local f_size_of_headers = self:append( field.uint32("size_of_headers") )
        local f_check_sum = self:append( field.uint32("check_sum") )
        local f_subsystem = self:append( field.uint16("subsystem", false, fh.mkdesc_x(SUBSYSTEM_STR)) )
        local f_dll_characteristics = self:append( field.uint16("dll_characteristics", false, fh.num_desc_vx) )
        local f_size_of_stack_reserve = self:append( field_long("size_of_stack_reserve", false, fh.num_desc_vx) )
        local f_size_of_stack_commit = self:append( field_long("size_of_stack_commit", false, fh.num_desc_vx) )
        local f_size_of_heap_reserve = self:append( field_long("size_of_heap_reserve", false, fh.num_desc_vx) )
        local f_size_of_heap_commit = self:append( field_long("size_of_heap_commit", false, fh.num_desc_vx) )
        local f_loader_flags = self:append( field.uint32("loader_flags") )
        local f_number_of_rva_and_sizes = self:append( field.uint32("number_of_rva_and_sizes", false, fh.num_desc_vx) )

        local hdr = image_optional_header_t.new()

        local sorted_directoris = {}
        for i=1, IMAGE_NUMBEROF_DIRECTORY_ENTRIES do

            local data_directory  = image_data_directory_t.new()
            self:append( field_image_data_directory(i-1, data_directory) )

            table.insert( hdr.image_data_directoris, data_directory)

            if data_directory.size > 0 then
                table.insert( sorted_directoris, data_directory )
            end
        end

        local remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append( field.string("remain", remain) )
        end

        hdr.magic = f_magic.value
        hdr.major_linker_version = f_major_linker_version.value
        hdr.minor_linker_version = f_minor_linker_version.value
        hdr.size_of_code = f_size_of_code.value
        hdr.size_of_initialized_data = f_size_of_initialized_data.value
        hdr.size_of_uninitialized_data = f_size_of_uninitialized_data.value
        hdr.address_of_entry_point = f_address_of_entry_point.value
        hdr.base_of_code = f_base_of_code.value

        if f_base_of_data then
            hdr.base_of_data = f_base_of_data.value
        end

        hdr.image_base = f_image_base.value
        hdr.section_alignment = f_section_alignment.value
        hdr.file_alignment = f_file_alignment.value
        hdr.major_operating_system_version = f_major_operating_system_version.value
        hdr.minor_operating_system_version = f_minor_operating_system_version.value
        hdr.major_image_version = f_major_image_version.value
        hdr.minor_image_version = f_minor_image_version.value
        hdr.major_subsystem_version = f_major_subsystem_version.value
        hdr.minor_subsystem_version = f_minor_subsystem_version.value
        hdr.win32_version_value = f_win32_version_value.value
        hdr.size_of_image = f_size_of_image.value
        hdr.size_of_headers = f_size_of_headers.value
        hdr.check_sum = f_check_sum.value
        hdr.subsystem = f_subsystem.value
        hdr.dll_characteristics = f_dll_characteristics.value
        hdr.size_of_stack_reserve = f_size_of_stack_reserve.value
        hdr.size_of_stack_commit = f_size_of_stack_commit.value
        hdr.size_of_heap_reserve = f_size_of_headers.value
        hdr.size_of_heap_commit = f_size_of_heap_commit.value
        hdr.loader_flags = f_loader_flags.value
        hdr.number_of_rva_and_sizes = f_number_of_rva_and_sizes.value
        g_pe.image_optional_header = hdr

        g_pe.sorted_directoris = sorted_directoris
        g_pe.is_x64 = is_x64
    end)
    return f
end

local function field_image_nt_header()
    local f = field.list("image_nt_header", nil, function(self, ba)
        local f_signature = self:append( field.uint32("signature", false, fh.mkdesc_x(DICT_CONSTS_STR)) ) --PE

        self:append( field_image_file_header() )
        self:append( field_image_optional_header() )

        g_pe.signature = f_signature.value
    end)
    return f
end

local function field_image_section_header(index, hdr)
    local f = field.list(string.format("image_section_header[%d]", index), nil, function(self, ba)
        local f_name = self:append( field.string("name", 8, fh.str_desc, function(self)
            return string.format("%8s ", self:get_str())
        end) )
        local f_physical_address = self:append( field.uint32("virtual_size", false, fh.num_desc_vx, fh.mkbrief_v("VSIZE")) )
        local f_virtual_address = self:append( field.uint32("virtual_address", false, fh.num_desc_vx, fh.mkbrief_x("RVA")) )
        local f_size_of_raw_data = self:append( field.uint32("size_of_raw_data", false, fh.num_desc_vx, fh.mkbrief_v("SRAW") ) )
        local f_pointer_to_raw_data = self:append( field.uint32("pointer_to_raw_data", false, fh.num_desc_vx, fh.mkbrief_x("PRAW")) )
        local f_pointer_to_relocations = self:append( field.uint32("pointer_to_relocations") )
        local f_pointer_to_line_numbers = self:append( field.uint32("pointer_to_line_numbers") )
        local f_number_of_relocations = self:append( field.uint16("number_of_relocations") )
        local f_number_of_line_numbers = self:append( field.uint16("number_of_line_numbers") )
        local f_characteristics = self:append( field.uint32("characteristics", false, fh.num_desc_x) )

        hdr.name = f_name:get_str()
        hdr.virtual_size = f_physical_address.value
        hdr.virtual_address = f_virtual_address.value
        hdr.size_of_raw_data = f_size_of_raw_data.value
        hdr.pointer_to_raw_data = f_pointer_to_raw_data.value
        hdr.pointer_to_relocations = f_pointer_to_relocations.value
        hdr.pointer_to_line_numbers = f_pointer_to_line_numbers.value
        hdr.number_of_relocations = f_number_of_relocations.value
        hdr.number_of_line_numbers = f_number_of_line_numbers.value
        hdr.characteristics = f_characteristics.value
    end)
    return f
end

local function field_image_section_headers()
    local nsec = g_pe.image_file_header.number_of_sections
    local f = field.list(string.format("image_section_headers count:%d", nsec), nil, function(self, ba)

        for i=1, nsec do

            local hdr = image_section_header_t.new()
            self:append( field_image_section_header(i-1, hdr) )
            table.insert(g_pe.image_section_headers, hdr)
        end
    end)
    return f
end

--_IMAGE_IMPORT_DESCRIPTOR
local function field_image_import_descriptor( index, descriptor )

    local tmp_ba = byte_stream(128)

    local f = field.list(string.format("[%d]image_import_descriptor", index), nil, function(self, ba)
        local f_original_first_thunk = self:append(field.uint32("original_first_thunk(import name table)", false, desc_rva_fpos, mkbrief_rva("INT")))
        local f_time_date_stamp = self:append(field.uint32("time_date_stamp", false, nil, mkbrief_rva("TDS")))
        local f_forwarder_chain = self:append(field.uint32("forwarder_chain", false, nil, mkbrief_rva("FC")))

        local f_name = self:append(field.uint32("name", false, desc_rva_fpos, mkbrief_rva("NM")))
        local f_first_trunk = self:append(field.uint32("first_thunk(import address table)", false, desc_rva_fpos, mkbrief_rva("IAT")))

        local name_offset = virtual_addr_to_offset( g_pe, f_name.value )
        local dll_name = string.format("%s", ba:peek_bytes_from(name_offset, 128))

        tmp_ba:set_data(dll_name, #dll_name)
        local p0 = tmp_ba:search(terminal0, 1)
        dll_name = tmp_ba:read_bytes(p0)

        descriptor.original_first_thunk = f_original_first_thunk.value
        descriptor.time_date_stamp = f_time_date_stamp.value
        descriptor.forwarder_chain = f_forwarder_chain.value
        descriptor.name = f_name.value
        descriptor.first_thunk = f_first_trunk.value

        descriptor.id = index
        descriptor.dll_name = dll_name
        self.dll_name = dll_name

    end, function(self)
        return string.format("%s %s%s", self.name, self:get_child_brief(), self.dll_name)
    end)
    return f
end

--_IMAGE_EXPORT_DIRECTORY
local function field_image_export_directory()

    local f = field.list("image_export_directory", nil, function(self, ba)
        local f_characteristics = self:append(field.uint32("characteristics", false, fh.num_desc_x))
        local f_time_date_stamp = self:append(field.uint32("time_date_stamp", false, fh.desc_sec2date))
        local f_major_version = self:append(field.uint16("major_version", false))
        local f_minor_version = self:append(field.uint16("minor_version", false))
        local f_name = self:append(field.uint32("name", false, desc_rva_fpos))
        local f_base = self:append(field.uint32("base", false, fh.num_desc_x))
        local f_number_of_functions = self:append(field.uint32("number_of_functions", false))
        local f_number_of_names = self:append(field.uint32("number_of_names", false))
        local f_address_of_functions = self:append(field.uint32("address_of_functions", false, desc_rva_fpos))
        local f_address_of_names = self:append(field.uint32("address_of_names", false, desc_rva_fpos))
        local f_address_of_name_ordinals = self:append(field.uint32("address_of_name_ordinals", false, desc_rva_fpos))

        local o = image_export_directory_t.new()
        o.characteristics = f_characteristics.value
        o.time_date_stamp = f_time_date_stamp.value
        o.major_version = f_major_version.value
        o.minor_version = f_minor_version.value
        o.name = f_name.value
        o.base = f_base.value
        o.number_of_functions = f_number_of_functions.value
        o.number_of_names = f_number_of_names.value
        o.address_of_functions = f_address_of_functions.value
        o.address_of_names = f_address_of_names.value
        o.address_of_name_ordinals = f_address_of_name_ordinals.value

        g_pe.image_export_directory = o
    end)
    return f
end

local function field_export_dll_name()
    local f = field.callback("export_dll_name", function(self, ba)
        local pos = ba:position()
        local pos_end = ba:search( terminal0, 1 )
        local len = pos_end - pos + 1
        self.dll_name = ba:read_bytes(len)
        return self.dll_name, len
    end, function(self)
        return string.format("export_dll len:%d %s", self.len, self.dll_name)
    end)
    return f
end
--[[
local function field_export_address_of_function(index)
    local f = field.list(string.format("export_address_of_function[%d]", index), nil, function(self, ba)
        self:append( field.uint32("export_rva", false, desc_rva_fpos, mkbrief_rva("EXPORT_RVA")))
    end)
    return f
end
--]]
local function field_export_address_of_functions()
    local ncount = g_pe.image_export_directory.number_of_functions
    local f = field.list(string.format("export_address_of_functions count:%d", ncount), nil, function(self, ba)
        for i=1, ncount do
            local f_addr = self:append( field.uint32(string.format("export_address_of_function[%d]", i-1), false, desc_rva_fpos, mkbrief_rva("EXPORT_RVA")))

            g_pe.export_funcs[i].address_of_function = f_addr.value
        end

    end)
    return f
end

local function field_export_address_of_names()
    local ncount = g_pe.image_export_directory.number_of_names
    local f = field.list(string.format("export_address_of_names count:%d", ncount), nil, function(self, ba)
        for i=1, ncount do
            local f_addr = self:append( field.uint32(string.format("export_address_of_name[%d]", i-1), false, desc_rva_fpos ))
            g_pe.export_funcs[i].address_of_name = f_addr.value
        end
    end)
    return f
end

local function field_export_address_of_name_ordinals()
    local ncount = g_pe.image_export_directory.number_of_names
    local f = field.list(string.format("export_address_of_name_ordinals count:%d", ncount), nil, function(self, ba)
        for i=1, ncount do
            local f_addr = self:append( field.uint16(string.format("export_address_of_name_ordinal[%d]", i-1), false, fh.num_desc_vx) )
            g_pe.export_funcs[i].address_of_ordinal = f_addr.value
        end
    end)
    return f
end

local function field_image_directory_export()
    local export_directory = g_pe.image_optional_header.image_data_directoris[IMAGE_DIRECTORY_ENTRY.EXPORT+1]
    local len = export_directory.size
    local f = field.list("image_directory_export", len, function(self, ba)
        local pos = ba:position()
        self:append( field_image_export_directory() )

        local ncount = g_pe.image_export_directory.number_of_names

        for i=1, ncount do
            table.insert( g_pe.export_funcs, export_func_info_t.new() )
        end

        local offset_fields = {}

        local export_directory = g_pe.image_export_directory
        local of_name = offset_field_t.new()
        of_name.offset = virtual_addr_to_offset(g_pe, export_directory.name)
        of_name.field = field_export_dll_name
        table.insert( offset_fields, of_name )

        local of = offset_field_t.new()
        of.offset = virtual_addr_to_offset(g_pe, export_directory.address_of_functions)
        of.field = field_export_address_of_functions
        table.insert( offset_fields, of )

        local of = offset_field_t.new()
        of.offset = virtual_addr_to_offset(g_pe, export_directory.address_of_names)
        of.field = field_export_address_of_names
        table.insert( offset_fields, of )

        local of = offset_field_t.new()
        of.offset = virtual_addr_to_offset(g_pe, export_directory.address_of_name_ordinals)
        of.field = field_export_address_of_name_ordinals
        table.insert( offset_fields, of )

        table.sort( offset_fields, function(a, b) return a.offset < b.offset end )

        for i, of in ipairs(offset_fields) do
            local pos_of = ba:position()
            local nskip = of.offset - pos_of
            if nskip > 0 then
                self:append( field.string("skip", nskip) )
            end

            self:append( of.field() )
        end

        --field export function names
        self:append(field.list(string.format("export_functions[%d]", ncount), nil, function(self, ba)
            for i=1, ncount do
                local pos_s = ba:position()
                local pos_e = ba:search( terminal0, 1 )
                local name_len = pos_e - pos_s + 1
                local f_name = self:append( field.string(string.format("export_function[%d]", i-1), name_len, fh.str_desc) )

                g_pe.export_funcs[i].func_name = f_name:get_str()
            end
        end))

        local remain = len - (ba:position() - pos)
        if remain > 0 then
            self:append( field.string("data", remain) )
        end
    end)
    return f
end

local function field_image_directory_import()
    local f = field.list("image_directory_import", nil, function(self, ba)
        g_pe.image_import_descriptors = {}
        g_pe.image_import_descriptor_int = {}
        g_pe.image_import_descriptor_iat = {}
        g_pe.image_import_descriptor_dll = {}
        g_pe.import_dlls = {}
   
        local sizeof_desc = 20 
        local tmp_ba = byte_stream(sizeof_desc)
        local index = 0
        while true do

            --size of image_import_descriptor_t
            local tmp_data = ba:peek_bytes(sizeof_desc)
            tmp_ba:set_data( tmp_data, #tmp_data )

            tmp_ba:read_bytes(12) --skip 3 int
            local name = tmp_ba:read_uint32()
            local first_thunk = tmp_ba:read_uint32()

            local descriptor = image_import_descriptor_t.new()
            self:append( field_image_import_descriptor(index, descriptor) )

            if 0 == name and 0 == first_thunk then
                break
            end

            table.insert( g_pe.image_import_descriptors, descriptor )
            table.insert( g_pe.image_import_descriptor_int, descriptor )
            table.insert( g_pe.image_import_descriptor_iat, descriptor )
            table.insert( g_pe.image_import_descriptor_dll, descriptor )
            table.insert( g_pe.import_dlls, descriptor.dll_name )

            index = index + 1
        end

        table.sort(g_pe.image_import_descriptor_int, function(a, b) return a.original_first_thunk < b.original_first_thunk end)
        table.sort(g_pe.image_import_descriptor_iat, function(a, b) return a.first_thunk < b.first_thunk end)
        table.sort(g_pe.image_import_descriptor_dll, function(a, b) return a.name < b.name end)
    end)
    return f
end

local function field_image_base_relocation(index, image_base_relocation)
    local f = field.list(string.format("[%d]image_base_relocation", index), nil, function(self, ba)
        local f_virtual_address = self:append( field.uint32("virtual_address", false, fh.num_desc_x, fh.mkbrief_x("RVA")) )
        local f_size_of_block = self:append( field.uint32("size_of_block", false, nil, fh.mkbrief_v("SIZE")) )

        local data_len = f_size_of_block.value - 8
        --self:append( field.string("data", data_len) )
        self:append( field.list("entris", data_len, function(self, ba)
            local pos = ba:position()
            local remain = data_len - (ba:position() - pos)
            local nentry = remain / 2
            for i=1, nentry do
                self:append( field.uint16(string.format("[%d]type_offset", i-1), false, fh.num_desc_x))
            end

        end, function(self)
            return string.format("%s count:%d len:%d", self.name, data_len/2, self.len)
        end) )

        image_base_relocation.virtual_address = f_virtual_address.value
        image_base_relocation.size_of_block = f_size_of_block.value
    end)
    return f
end

local function field_image_directory_base_reloc()
    local ncount = 0
    local f = field.list("image_base_relocation_table", nil, function(self, ba)

        local index = 0
        while true do

            local u64 = ba:peek_uint64()
            if 0 == u64 then
                break
            end

            local relocation = image_base_relocation_t.new()
            self:append( field_image_base_relocation(index, relocation) )
            table.insert( g_pe.image_base_relocations, relocation)

            index = index + 1
        end
        ncount = index
    end, function(self)
        return string.format("%s count:%d len:%d", self.name, ncount, self.len)
    end)
    return f
end

local function field_import_name_table(pe, idesc, desc)
    local nentry = 0

    local f = field.list(string.format("int_entris[%d]", idesc), nil, function(self, ba)
        local f_iat = field.uint32
        if pe.is_x64 then
            f_iat = field.uint64
        end

        local index = 0
        while true do
            local filt = self:append( f_iat(string.format("int_entry[%d]", index), false, desc_rva_fpos) )
            if 0 == filt.value then break end

            index = index + 1

            table.insert(pe.dict_int[desc.id], filt.value)
        end
        nentry = index

        --bi.log(string.format("field_import_name_table[%d] rva:0x%X nilt:%d", idesc, desc.original_first_thunk, nentry) )
    end, function(self)
        return string.format("%s count:%d len:%d", self.name, nentry, self.len)
    end)
    return f
end

local function field_import_name_table_entries()

    local f = field.list("import_name_table", nil, function(self, ba)
        
        for idesc, desc in ipairs(g_pe.image_import_descriptor_int) do
            local rva = desc.original_first_thunk
            local offset = virtual_addr_to_offset(g_pe, rva)
            g_pe.dict_int[desc.id] = {}
            self:append( field_import_name_table(g_pe, idesc-1, desc) )
        end
    end)
    return f
end

local function cb_field_import_dll_name(descriptor)

    local cb = function()
        local f = field.callback("dll_name", function(self, ba)
            local pos = ba:position()

            local pos_end = ba:search( terminal0, 1 )
            local name_len = pos_end - pos + 1
            if name_len % 2 ~= 0 then
                name_len = name_len + 1
            end

            local name = ba:read_bytes(name_len)
            self.dll_name = name
            return name, name_len  
            --self:append( field.string(string.format("dll[%d] len:%d", i-1, name_len), name_len, fh.str_desc ) )
        end, function(self)
            return string.format("import_dll[%d] len:%d %s", descriptor.id, self.len, self.dll_name)
        end)
        return f
    end
    return cb
end

--_IMAGE_DEBUG_DIRECTORY
local function field_image_directory_debug()

    local debug_directory = g_pe.image_optional_header.image_data_directoris[IMAGE_DIRECTORY_ENTRY.DEBUG+1]
    local sizeof_debug_struct = 28
    local ndebug = debug_directory.size / sizeof_debug_struct
    local f = field.list(string.format("image_directory_debugs count:%d", ndebug), nil, function(self, ba)
        for i=1, ndebug do
            self:append(field.list(string.format("image_directory_debug[%d]", i-1), nil, function(self, ba)
                self:append( field.uint32("characteristics", false, fh.num_desc_x) )
                self:append( field.uint32("time_data_stamp", false, fh.desc_sec2date) )
                self:append( field.uint16("major_version") )
                self:append( field.uint16("minor_version") )
                self:append( field.uint32("type", false, fh.mkdesc(IMAGE_DEBUG_TYPE_STR)) )
                self:append( field.uint32("size_of_data") )
                self:append( field.uint32("address_of_raw_data", false, fh.num_desc_x) )
                self:append( field.uint32("pointer_of_raw_data", false, fh.num_desc_x) )
            end))
        end
    end)
	return f
end

--IMAGE_LOAD_CONFIG_CODE_INTEGRITY
local function field_image_load_config_code_integrity()
    local f = field.list("image_load_config_code_integrity", nil, function(self, ba)
        -- Flags to indicate if CI information is available, etc.
        self:append( field.uint16("flags") )
        -- 0xFFFF means not available
        self:append( field.uint16("catalog") )
        self:append( field.uint32("catalog_offset") )
        self:append( field.uint32("reserved") )
    end)
    return f
end

--_IMAGE_LOAD_CONFIG_DIRECTORY64 
local function field_image_directory_load_config()
    local f = field.list("image_directory_load_config", nil, function(self, ba)

        local field_long = field.uint32
        if g_pe.is_x64 then 
            field_long = field.uint64 
        end

        self:append( field.uint32("size") )
        self:append( field.uint32("time_date_stamp", false, fh.desc_sec2date) )
        self:append( field.uint16("major_version") )
        self:append( field.uint16("minor_version") )
        self:append( field.uint32("global_flags_clear") )
        self:append( field.uint32("global_flags_set") )
        self:append( field.uint32("critical_section_default_timeout") )

        self:append( field_long( "de_commit_free_block_threshold", false, fh.num_desc_x) )
        self:append( field_long( "de_commit_total_free_threshold", false, fh.num_desc_x) )
        self:append( field_long( "lock_prefix_table", false, fh.num_desc_x) )
        self:append( field_long( "maximum_allocation_size", false, fh.num_desc_x) )
        self:append( field_long( "virtual_memory_threshold", false, fh.num_desc_x) )

        if g_pe.is_x64 then
            self:append( field_long( "process_affinity_mask", false, fh.num_desc_x) )
            self:append( field.uint32( "process_heap_flags" ) )
        else
            self:append( field.uint32( "process_heap_flags" ) )
            self:append( field.uint32( "process_affinity_mask" ) )
        end

        self:append( field.uint16( "csd_version" ) )
        self:append( field.uint16( "dependent_load_flags" ) )

        self:append( field_long( "edit_list", false, fh.num_desc_x) )
        self:append( field_long( "security_cookie", false, fh.num_desc_x) )
        self:append( field_long( "se_handler_table", false, fh.num_desc_x) )
        self:append( field_long( "se_handler_count", false, fh.num_desc_x) )
        self:append( field_long( "guard_cf_check_function_pointer", false, fh.num_desc_x) )
        self:append( field_long( "guard_cf_dispatch_function_pointer", false, fh.num_desc_x) )
        self:append( field_long( "guard_cf_function_table", false, fh.num_desc_x) )
        self:append( field_long( "guard_cf_function_count", false, fh.num_desc_x) )

        self:append( field.uint32( "guard_flags" ) )

        self:append( field_image_load_config_code_integrity() )

        self:append( field_long( "guard_address_taken_iat_entry_table", false, fh.num_desc_x) )
        self:append( field_long( "guard_address_taken_iat_entry_count", false, fh.num_desc_x) )
        self:append( field_long( "guard_long_jump_target_table", false, fh.num_desc_x) )
        self:append( field_long( "guard_long_jump_target_count", false, fh.num_desc_x) )
        self:append( field_long( "dynamic_value_reloc_table", false, fh.num_desc_x) )
        self:append( field_long( "ch_pe_metadata_pointer", false, fh.num_desc_x) )
        self:append( field_long( "guard_rf_failure_routine", false, fh.num_desc_x) )
        self:append( field_long( "guard_rf_failure_routine_function_pointer", false, fh.num_desc_x) )

        self:append( field.uint32( "dynamic_value_reloc_table_offset" ) )
        self:append( field.uint16( "dynamic_value_reloc_table_section" ) )
        self:append( field.uint16( "reserved2" ) )

        self:append( field_long( "guard_rf_verify_stack_pointer_function_pointer", false, fh.num_desc_x) )

        self:append( field.uint32( "hot_patch_table_offset" ) )
        self:append( field.uint32( "reserved3" ) )

        self:append( field_long( "enclave_configuration_pointer", false, fh.num_desc_x) )
        self:append( field_long( "volatile_metadata_pointer", false, fh.num_desc_x) )
    end)
    return f
end


local function field_import_address_table_entris(pe, idesc, desc)
    local nentry = 0

    local f = field.list(string.format("iat_entris[%d]", idesc), nil, function(self, ba)
        local f_ilt = field.uint32
        if pe.is_x64 then
            f_ilt = field.uint64
        end

        local index = 0
        while true do
            local fiat = self:append( f_ilt(string.format("iat_entry[%d]", index), false, desc_rva_fpos) )
            if 0 == fiat.value then break end

            index = index + 1

            table.insert(pe.dict_iat[desc.id], fiat.value)
        end
        nentry = index

        --bi.log(string.format("field_import_address_table_entris[%d] rva:0x%X nilt:%d", idesc, desc.first_thunk, nentry) )
    end, function(self)
        return string.format("%s count:%d len:%d (%s)", self.name, nentry, self.len, desc.dll_name)
    end)
    return f
end

local function cb_field_import_func_name(dll_id, ifunc)
    local field_func_name = function()
        local dll_name = g_pe.import_dlls[dll_id+1]
        local f = field.list(string.format("import func[%d %s][%d]", dll_id, dll_name, ifunc), nil, function(self, ba)
            local f_index = self:append( field.uint16("index", false, fh.num_desc_vx, fh.mkbrief_x("ID")) )

            local pos = ba:position()
            local p0 = ba:search(terminal0, 1)
            local name_len = p0 - pos + 1
            if name_len % 2 ~= 0 then
                name_len = name_len + 1
            end
            local f_name = self:append( field.string("name", name_len, fh.str_desc, fh.str_brief_v ) )
            --bi.log( string.format("func[%d] len:%d %s", ifunc, name_len, f_name:get_str()) )

            local info = import_func_info_t.new()
            info.ordinal = f_index.value
            info.func_name = f_name:get_str()
            table.insert(g_pe.import_funcs[dll_id+1], info)

        end)
        return f
    end
    return field_func_name
end

--IMAGE_DIRECTORY_ENTRY_IAT
local function field_image_directory_import_address_table()
    local ndesc = #g_pe.image_import_descriptors
    if ndesc == 0 then return end

    local f = field.list("image_directory_import_address_table", nil, function(self, ba)
        for idesc, desc in ipairs(g_pe.image_import_descriptor_iat) do
            local rva = desc.first_thunk
            local offset = virtual_addr_to_offset( g_pe, rva )
            g_pe.dict_iat[desc.id] = {}

            local nskip = offset - ba:position()
            if nskip > 0 then
                self:append( field.string("skip", nskip) )
            end

            self:append( field_import_address_table_entris(g_pe, idesc-1, desc) )
        end

        --function name
        for id, arr in pairs(g_pe.dict_iat) do
            for i, rva in ipairs(arr) do
                local of = offset_field_t.new()
                of.offset = virtual_addr_to_offset(g_pe, rva)
                of.field = cb_field_import_func_name(id, i-1)
                table.insert( g_pe.offset_fields, of)
            end
        end
        table.sort( g_pe.offset_fields, function(a, b) return a.offset < b.offset end )

    end)
    return f
end

local dict_field_section = {
    [IMAGE_DIRECTORY_ENTRY.EXPORT]        = field_image_directory_export,
    [IMAGE_DIRECTORY_ENTRY.IMPORT]        = field_image_directory_import,
    [IMAGE_DIRECTORY_ENTRY.RESOURCE]      = nil,
    [IMAGE_DIRECTORY_ENTRY.EXCEPTION]     = nil,
    [IMAGE_DIRECTORY_ENTRY.SECURITY]      = nil,
    [IMAGE_DIRECTORY_ENTRY.BASERELOC]     = field_image_directory_base_reloc,
    [IMAGE_DIRECTORY_ENTRY.DEBUG]         = field_image_directory_debug,
    [IMAGE_DIRECTORY_ENTRY.ARCHITECTURE]  = nil,
    [IMAGE_DIRECTORY_ENTRY.GLOBALPTR]     = nil,
    [IMAGE_DIRECTORY_ENTRY.TLS]           = nil,
    [IMAGE_DIRECTORY_ENTRY.LOAD_CONFIG]   = field_image_directory_load_config,
    [IMAGE_DIRECTORY_ENTRY.BOUND_IMPORT]  = nil,
    [IMAGE_DIRECTORY_ENTRY.IAT]           = field_image_directory_import_address_table,
--    [IMAGE_DIRECTORY_ENTRY.IAT]           = nil,
    [IMAGE_DIRECTORY_ENTRY.DELAY_IMPORT]  = nil,
    [IMAGE_DIRECTORY_ENTRY.COM_DESCRIPTOR]= nil,
    [IMAGE_DIRECTORY_ENTRY.RESERVED]      = nil,
}

local function field_image_section(isec, sec)
    local len = sec.size_of_raw_data

    local f = field.list(string.format("image_section[%d %-8s]", isec, sec.name), len, function(self, ba)
        local pos = ba:position()
        local epos = pos + len

        while true do
            local pos2 = ba:position()
            bi.set_progress_value(pos2)

            --find directory entry
            local dir_id = nil
            local tmp_of = nil
            for _, of in ipairs(g_pe.offset_fields) do
                local offset = of.offset
                if offset >= pos2 and offset < epos then
                    tmp_of = of
                    break
                end
            end

            if nil == tmp_of then
                break
            end

            local nskip = tmp_of.offset - pos2
            if nskip > 0 then
                self:append( field.string("data", nskip) )
            end

            self:append( tmp_of.field() )
        end

        local remain = len - (ba:position() - pos)
        if remain > 0 then
            remain = len - (ba:position() - pos)
            self:append( field.string("data", remain) )
        end
    end)
    return f
end

local function is_x64_pe( fname )
    --TODO read file header, nt header
    local file = io.open(fname, "rb")
    if not file then return -1 end
    --bi.log(string.format("is_x64_pe %s", fname))

    local data = file:read( 2048 )
    file:close()
    if nil == data then
        return -1
    end

    local len = #data
    local ba = byte_stream(len)
    ba:set_data( data, len )

    local sig_mz = ba:peek_uint16()
    if sig_mz ~= DICT_CONSTS.IMAGE_DOS_SIGNATURE then
        return -2
    end

    local dos_header_len = 60 --sizeof(dos_header) - lfanew 
    ba:read_bytes(dos_header_len)
    local lfanew = ba:read_uint32()

    local nskip = lfanew - ba:position()
    ba:read_bytes(nskip)

    --file header
    local sig_pe = ba:read_uint32() --PE signature: 0x4550
    if sig_pe ~= DICT_CONSTS.IMAGE_PE_SIGNATURE then
        return -3
    end

    local file_header_len = 20
    ba:read_bytes(file_header_len)

    local magic = ba:read_uint16()
    local is_x64 = false
    if magic == DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR32_MAGIC then
    elseif magic == DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR64_MAGIC then
        is_x64 = true
    end

    --bi.log( string.format("is_x64_pe: lfanew:%d pos:%d pe:0x%X magic:0x%X %s %s", lfanew, ba:position(), sig_pe, magic, tostring(is_x64), fname) )
    return is_x64
end

--for get import name table, import address table
local function pre_read_image_import_descriptor(ba)
    local old_pos = ba:position()

    local id = IMAGE_DIRECTORY_ENTRY.IMPORT+1
    local import_directory = g_pe.image_optional_header.image_data_directoris[id]

    local offset = virtual_addr_to_offset(g_pe, import_directory.virtual_address)
    local nskip = offset - old_pos
    ba:skip_bytes(nskip)

    local f_import = field_image_directory_import()
    f_import:read(ba)

    local nback = ba:position() - old_pos
    ba:back_pos(nback)

    --INT
    local of = offset_field_t.new()
    of.offset = virtual_addr_to_offset(g_pe, g_pe.image_import_descriptor_int[1].original_first_thunk)
    of.field = field_import_name_table_entries
    table.insert( g_pe.offset_fields, of )

    --IAT
--    local of = offset_field_t.new()
--    of.offset = virtual_addr_to_offset(g_pe, g_pe.image_import_descriptor_iat[1].first_thunk)
--    of.field = field_image_directory_import_address_table
--    table.insert( g_pe.offset_fields, of)

    --NAME
    for _, desc in ipairs(g_pe.image_import_descriptor_dll) do
        local of = offset_field_t.new()
        of.offset = virtual_addr_to_offset(g_pe, desc.name)
        of.field = cb_field_import_dll_name(desc)
        table.insert( g_pe.offset_fields, of)

        table.insert( g_pe.import_funcs, {} )
    end

    --directory
    for _, directory in ipairs(g_pe.sorted_directoris) do
        local of = offset_field_t.new()
        of.offset = virtual_addr_to_offset(g_pe, directory.virtual_address)

        local field_unknown_directory = function(directory)
            local cb = function()
                local entry_name = IMAGE_DIRECTORY_ENTRY_STR[directory.id]
                local f = field.string(string.format("TODO parse[%d]: %s", directory.id, entry_name), directory.size)
                bi.log(string.format("TODO parse[%d]: %s", directory.id, entry_name))
                return f
            end
            return cb
        end

        of.field = dict_field_section[directory.id] or field_unknown_directory(directory)
        table.insert( g_pe.offset_fields, of)
    end

    table.sort( g_pe.offset_fields, function(a, b) return a.offset < b.offset end )
end

local function decode_pe( ba, len, args )
	g_pe = pe_t.new()

    --is_x64_pe( "/tmp/BinInspector.exe" )
    g_pe.fname = args.fname
    g_pe.fpath = helper.get_file_path(args.fname)
	g_pe.fsize = len

    bi.set_progress_max(len)

    local f_pe = field.list("pe", len, function(self, ba)
		local sync = ba:peek_uint16()
		if sync ~= DICT_CONSTS.IMAGE_DOS_SIGNATURE then 
			--error format
			return
		end

        self:append( field_image_dos_header() )

        local nskip = g_pe.image_dos_header.lfanew - ba:position()
        self:append( field.string("skip", nskip) )

--        self:append( field_dos_stub() )
        self:append( field_image_nt_header() )
        self:append( field_image_section_headers() )

        pre_read_image_import_descriptor(ba)

        nskip = g_pe.image_section_headers[1].pointer_to_raw_data - ba:position()
        self:append( field.string("skip", nskip) )

        --sections
        local nsec = g_pe.image_file_header.number_of_sections
        local isec = 0
        for i, sec in ipairs(g_pe.image_section_headers) do
            isec = i - 1

            if sec.size_of_raw_data > 0 then
                self:append( field_image_section(isec, sec) )
            end
        end

        --parse import directory
    end)

    return f_pe
end

local function clear()
end

local function build_summary_import_dll()
    local tw = bi.create_summary_table("DependDLL")

    local tw_header = { "index", "name", "exist", "arch", "path" }
    local tw_ncol = #tw_header
    tw:set_column_count(tw_ncol)

    for i=1, tw_ncol do
        tw:set_header(i-1, tw_header[i] )
    end

    local color_error = "#FF0000"
    for i, dll in ipairs(g_pe.import_dlls) do
        tw:append_empty_row()

        local path = find_dll_path(g_pe, dll)
        local exist_sign = "✗"
        local v_arch = nil
        if nil ~= path then
            local is_x64 = is_x64_pe(path)
            if true == is_x64 then
                v_arch = DICT_CONSTS_STR[DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR64_MAGIC]
            elseif false == is_x64 then
                v_arch = DICT_CONSTS_STR[DICT_CONSTS.IMAGE_NT_OPTIONAL_HDR32_MAGIC]
            else
                path = string.format("not pe file:[%s]", path)
            end

            if g_pe.is_x64 == is_x64 then
                exist_sign = "✓"
            end
        end

        tw:set_last_row_column( 0, i-1 )
        local item_dll = tw:set_last_row_column( 1, dll )
        local item_exist = tw:set_last_row_column( 2, exist_sign or "")
        local item_arch = tw:set_last_row_column( 3, v_arch or "")
        tw:set_last_row_column( 4, path or "" )

        if exist_sign == "✗" then
            item_dll:set_fg_color(color_error)
            item_exist:set_fg_color(color_error)
        end

        if v_arch and v_arch ~= DICT_CONSTS_STR[g_pe.image_optional_header.magic] then
            item_arch:set_fg_color(color_error )
        end
    end
end

local function build_summary_import_func()
    local ndll = #g_pe.import_dlls
    if ndll <= 0 then return end

    local tree = bi.create_summary_tree("ImportFunc")

    for i, dll in ipairs(g_pe.import_dlls) do

        local str = string.format("[%d] %s", i-1, dll)
        local node = bi.create_tree_item( str )

        --funcs
        for j, info in ipairs(g_pe.import_funcs[i]) do
            local func_name = bi.cxx_demangle(info.func_name)
            local node_func = bi.create_tree_item(string.format("[%d] ordinal:%4d %s", j-1, info.ordinal, func_name))
            node:addChild(node_func)
        end

        tree:addChild(node)
    end

end

local function build_summary_export_func()
    local nfunc = #g_pe.export_funcs
    if nfunc <= 0 then return end

    local tw = bi.create_summary_table("ExportFunc")

    local tw_header = { "index", "ordinal", "func_offset", "name_offset", "name" }
    local tw_ncol = #tw_header
    tw:set_column_count(tw_ncol)

    for i=1, tw_ncol do
        tw:set_header(i-1, tw_header[i] )
    end
    
    local ef = g_pe.export_funcs
    for i=1, nfunc do
        tw:append_empty_row()
        local info = ef[i]

        tw:set_last_row_column( 0, i-1 )
        tw:set_last_row_column( 1, string.format("0x%06X", info.address_of_ordinal) )
        tw:set_last_row_column( 2, string.format(" 0x%08X", virtual_addr_to_offset(g_pe, info.address_of_function) ))
        tw:set_last_row_column( 3, string.format(" 0x%08X", virtual_addr_to_offset(g_pe, info.address_of_name) ))
        tw:set_last_row_column( 4, info.func_name )
    end
end

local function build_summary()
	if nil == g_pe then return end

    local fhdr = g_pe.image_file_header
    local opt_hdr = g_pe.image_optional_header

    local flag = fhdr.characteristics
    local ftype = "??"

    if 0 ~= (flag & IMAGE_FILE.DLL) then
        ftype = "dll"
    elseif 0 ~= (flag & IMAGE_FILE.EXECUTABLE_IMAGE) then
        ftype = "exe"
    end

    local os_ver = string.format("%d.%d", opt_hdr.major_operating_system_version, opt_hdr.minor_operating_system_version)
    local sub_ver = string.format("%d.%d", opt_hdr.major_subsystem_version, opt_hdr.minor_subsystem_version)


    bi.append_summary("ftype", ftype)
    bi.append_summary("signature",  DICT_CONSTS_STR[g_pe.signature] or "??" )
    bi.append_summary("arch", string.lower(DICT_CONSTS_STR[opt_hdr.magic] or "??"))
    bi.append_summary("machine", string.lower(IMAGE_FILE_MACHINE_STR[fhdr.machine] or "??"))
    bi.append_summary("OS version", string.format("%s (%s)", OS_VER_STR[os_ver] or "??", os_ver ))
	bi.append_summary("subsystem", SUBSYSTEM_STR[opt_hdr.subsystem] or "??")

    bi.append_summary("entry_point", string.format("0x%08X", opt_hdr.address_of_entry_point))
    bi.append_summary("image_base", string.format("0x%08X", opt_hdr.image_base))
    bi.append_summary("section_alignment", string.format("0x%08X (%d)", opt_hdr.section_alignment, opt_hdr.section_alignment))
    bi.append_summary("file_alignment", string.format("0x%08X (%d)",opt_hdr.file_alignment, opt_hdr.file_alignment))
    bi.append_summary("size_of_headers", string.format("0x%08X (%d)", opt_hdr.size_of_headers, opt_hdr.size_of_headers))

    bi.append_summary("import_dll", #g_pe.image_import_descriptor_dll )
    bi.append_summary("create_date", helper.ms2date(fhdr.time_date_stamp*1000) )

    build_summary_import_dll()
    build_summary_import_func()
    build_summary_export_func()
end

local codec = {
	authors = { {name="fei", mail="bin_inspector@163.com"} },
    file_desc = "pe files",
    file_ext = "exe dll",
    decode = decode_pe,
    clear = clear,
    build_summary = build_summary,

    is_x64_pe = is_x64_pe,
}

return codec
