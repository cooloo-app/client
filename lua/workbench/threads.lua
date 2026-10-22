-- Client-only text convention. No protocol, editor, filesystem or network access.
local M = {}
function M.uuid(id)
  return type(id)=='string' and #id==32 and id:match('^[0-9a-f]+$')~=nil
    and id:sub(13,13)=='4' and id:sub(17,17):match('[89ab]')~=nil
end
function M.parse(text)
  local id,body=text:match('^@thread/1 msg:([0-9a-f]+)\n\n(.*)$')
  if not id then id,body=text:match('^@thread/1 msg:([0-9a-f]+)\r\n\r\n(.*)$') end
  if M.uuid(id) then return id,body end
  return nil,text
end
function M.header(id,body) return '@thread/1 msg:'..id..'\n\n'..body end
local function strip(text) return (text:gsub('^%s+',''):gsub('%s+$','')) end
function M.prepare(text)
  -- Parse before trimming: an empty reply must not lose its header delimiter.
  local root,body=M.parse((text:gsub('^%s+','')))
  if root then
    body=strip(body)
    if body=='' then return nil,'消息正文不能为空' end
    return M.header(root,body),root
  end
  text=strip(text)
  if text=='' then return nil,'消息正文不能为空' end
  return text
end
function M.index()
  local self={messages={},replies={},revision=0,ready=true}
  function self:add(m)
    if not m.id or self.messages[m.id] then return end
    self.messages[m.id]=m;self.revision=self.revision+1
    local root=M.parse(m.text)
    if root then
      self.replies[root]=self.replies[root] or {}
      self.replies[root][m.id]=m
    end
  end
  function self:root(m)
    if not m or not M.uuid(m.id) then return nil,'该来源尚不支持稳定消息引用' end
    local ref=M.parse(m.text)
    if not ref then return self.messages[m.id] or m end
    local root=self.messages[ref]
    if not root then return nil,'原消息未加载/不可用' end
    if ref==m.id or M.parse(root.text) or root.context~=m.context then
      return nil,'无法归组：无效线程引用'
    end
    return root
  end
  function self:count(root,delivery)
    local ids={}
    for id,m in pairs(self.replies[root.id] or {}) do
      if self:root(m)==root then ids[id]=true end
    end
    if delivery and delivery.state~='rejected' and delivery.message_id
      and M.parse(delivery.text or '')==root.id then ids[delivery.message_id]=true end
    local n=0;for _ in pairs(ids) do n=n+1 end
    return n,ids
  end
  return self
end
-- Select relevant cached roots/replies without a full-cache scan on every frame.
function M.project(messages,index)
  if not index then
    index=M.index()
    for _,m in ipairs(messages) do index:add(m) end
  end
  local visible,emitted,out={},{},{}
  for _,m in ipairs(messages) do visible[m.id]=true end
  local function emit(m,reply,problem)
    if emitted[m.id] then return end
    emitted[m.id]=true
    out[#out+1]={message=m,reply=reply,problem=problem}
  end
  local function group(root)
    root=index.messages[root.id] or root
    emit(root)
    local replies={}
    for _,m in pairs(index.replies[root.id] or {}) do
      if index:root(m)==root then replies[#replies+1]=m end
    end
    table.sort(replies,function(a,b)
      if (a.ts or 0)~=(b.ts or 0) then return (a.ts or 0)<(b.ts or 0) end
      return a.id<b.id
    end)
    for _,m in ipairs(replies) do emit(m,true) end
  end
  for _,m in ipairs(messages) do
    local ref=M.parse(m.text)
    local root,err=index:root(m)
    if not ref then group(m)
    elseif root then
      -- A visible root keeps its original position; an off-window root is
      -- materialized at the first visible reply instead of silently hidden.
      if not visible[root.id] then group(root) end
    else emit(m,false,err) end
  end
  return out,index
end
function M.at(ranges,line1,line2)
  for _,r in ipairs(ranges or {}) do
    if line1>=r.first_line and line2<=r.last_line then return r end
  end
end
return M
