local res_path = bi.get_res_path()
local path = res_path .. "scripts/testcase"
local files = list_dir(path)
if nil == files then
	error(string.format("list_dir returns nil, path:%s", path))
end

for i, file in ipairs(files) do
	bi.log(string.format( "%d => %s", i, file))
end

require("中文")
