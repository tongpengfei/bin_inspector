local helper = require("helper")

bi.log( string.format("PATH: [%s]", os.getenv( "PATH" ) ) )
bi.log( string.format("HOME: [%s]", os.getenv( "HOME" ) ) )
bi.log( string.format("TEMP: [%s]", os.getenv( "TEMP" ) ) )

local arr_path = {
    "./a/b/c.txt",
    "/a/b/c.txt",
    "/a/b/",
    "/a/b/c.d.e.txt",
    "c.txt",
}
for _, path in ipairs(arr_path) do
    bi.log( string.format( "path: [%s] => [%s]", path, helper.get_file_path(path) ) )
end
