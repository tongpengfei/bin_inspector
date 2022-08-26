local t = {
--[[
	"test_field",
	"test_tree",
	"test_h264",
	"test_byte_stream",
	"test_bit_stream",
--]]
    "test_helper",
}

for _, v in ipairs(t) do
	bi.log(string.format("====== [testcase %s] ======", v))
	require(v)
end
