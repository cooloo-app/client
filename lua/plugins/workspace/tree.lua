-- Presentation only: nicknames never replace provider IDs.
local M={}
function M.build(rooms, collapsed)
  local root={children={}}
  for _,room in ipairs(rooms) do
    local name=room.name and room.name~='' and room.name or room.id
    local parts={}
    if name:sub(1,1)==':' or name:sub(-1)==':' or name:find('::',1,true) then
      parts[1]=name
    else for part in name:gmatch('[^:]+') do parts[#parts+1]=part end end
    local node=root
    for _,part in ipairs(parts) do
      node.children[part]=node.children[part] or {label=part,children={},rooms={}}
      node=node.children[part]
    end
    node.rooms[#node.rooms+1]=room
  end
  local rows={}
  local function walk(parent, depth, path)
    local names={}; for name in pairs(parent.children) do names[#names+1]=name end
    table.sort(names)
    for _,name in ipairs(names) do
      local n=parent.children[name]
      local key=path..#name..':'..name
      table.sort(n.rooms,function(a,b) return a.id<b.id end)
      local branch=next(n.children)~=nil or #n.rooms>1
      local single=#n.rooms==1 and n.rooms[1] or nil
      rows[#rows+1]={label=name,key=key,depth=depth,branch=branch,room=single,
        expanded=not collapsed[key]}
      if not collapsed[key] then
        if #n.rooms>1 then
          for _,r in ipairs(n.rooms) do
            rows[#rows+1]={label=r.name..' ['..r.id..']',key='id:'..r.id,depth=depth+1,room=r}
          end
        end
        walk(n,depth+1,key)
      end
    end
  end
  walk(root,0,'')
  return rows
end
return M
