
--type name: 123 (dict_value)
local function mkdesc( dict )
    local f = function(self)
        local str = dict[self.value] or "??"

        if self.is_bits then
            return string.format("[%2d bits] %s: %d (%s)", self.len, self.name, self.value, tostring(str))
        end
        return string.format("%s %s: %d (%s)", self.type, self.name, self.value, str) 
    end
    return f
end

--type name: 0xXXX (dict_value)
local function mkdesc_x( dict )
    local f = function(self)
        local str = dict[self.value] or "??"

        if self.is_bits then
            return string.format("[%2d bits] %s: 0x%X (%s)", self.len, self.name, self.value, tostring(str))
        end
        return string.format("%s %s: 0x%X (%s)", self.type, self.name, self.value, str) 
    end
    return f
end


local function str_desc(self)
    return string.format("%s: %s", self.name, self.value)
end

local function str_brief(self)
    return string.format("%s: %s ", self.name, self:get_data())
end

local function str_brief_v(self)
    return string.format("%s ", self:get_data())
end

--name:dict_value
local function mkbrief(name, dict)
    local f = function(self)
        name = name or self.name
        local sname = ""
        if name ~= "" then
            sname = string.format("%s:", name)
        end
        if dict then
            local str = dict[self.value] or "??"
            return string.format("%s%s ", sname, tostring(str))
        end
        return string.format("%s%s ", sname, tostring(self.value))
    end
    return f
end

--name:123(dict_value)
local function mkbrief_v( name, dict )
    local f = function(self)
        name = name or self.name
        local sname = ""
        if name ~= "" then
            sname = string.format("%s:", name)
        end
        if dict then
            local str = dict[self.value] or "??"
            return string.format("%s%s(%s) ", sname, tostring(self.value), tostring(str))
        end
        return string.format("%s%s ", sname, tostring(self.value))
    end
    return f
end

--name:0x123(dict_value)
local function mkbrief_x( name, dict )
    local f = function(self)
        name = name or self.name
        local sname = ""
        if name ~= "" then
            sname = string.format("%s:", name)
        end
        if dict then
            local str = dict[self.value] or "??"
            return string.format("%s0x%X(%s) ", sname, self.value, tostring(str))
        end
        return string.format("%s0x%X ", sname, self.value)
    end
    return f
end



local function child_brief(self)
    return self:get_child_brief()
end

local t = {
    str_desc = str_desc,
	str_brief = str_brief,
	str_brief_v = str_brief_v,

    mkdesc = mkdesc,
    mkdesc_x = mkdesc_x,

    mkbrief = mkbrief,
    mkbrief_v = mkbrief_v,
    mkbrief_x = mkbrief_x,

    child_brief = child_brief,
}
return t
