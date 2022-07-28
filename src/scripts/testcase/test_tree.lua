local mt = bi.main_tree()

local function test_tree()
    local node = bi.create_tree_item("lua node")
    mt:addChild(node)

    local node2 = bi.tree_add_child(mt, "lua node2")

    bi.log("hello lua2 ")
end

local function is_array(t)
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

local function build_tree( tree_node, data )
    local tp = type(data)
    if tp ~= "table" then
        local node = bi.create_tree_item(data)
        tree_node:addChild(node)
    elseif is_array(data) then
        for i, v in ipairs(data) do
            build_tree( tree_node, v )
        end
    else
        for k, v in pairs(data) do
            if type(v) == "table" then
                local node = bi.create_tree_item(k)
                tree_node:addChild(node)

                build_tree( node, v )
            else
                local node = bi.create_tree_item( string.format("%s: %s", k, tostring(v)) )
                tree_node:addChild(node)
            end
        end
    end
end

local data = {
    player = {
        prop = { name="tpf", hp=100, gender="male" },
        skills = {"fire_ball", "ice_arraw"},
    },

    monster = {
        prop = { name="dragon", hp=100, mp=50, damage=10 },
    }
}

--test_tree()
build_tree( mt, data )
mt:expandAll()
