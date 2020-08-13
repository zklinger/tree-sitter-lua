-- Load up our build parser.
-- TODO: Check if this changes within one session?...
vim.treesitter.require_language("lua", "./build/parser.so", true)

local read = function(f)
  local fp = assert(io.open(f))
  local contents = fp:read("all")
  fp:close()

  return contents
end

local get_parent_from_var = function(name)
  local colon_start = string.find(name, ":", 0, true)
  local dot_start = string.find(name, ".", 0, true)
  local bracket_start = string.find(name, "[", 0, true)

  local parent = nil
  if (not colon_start) and (not dot_start) and (not bracket_start) then
    parent = name
  elseif colon_start then
    parent = string.sub(name, 1, colon_start - 1)
    name = string.sub(name, colon_start + 1)
  elseif dot_start then
    parent = string.sub(name, 1, dot_start - 1)
    name = string.sub(name, dot_start + 1)
  elseif bracket_start then
    parent = string.sub(name, 1, bracket_start - 1)
    name = string.sub(name, bracket_start)
  end

  return parent, name
end


local ts_utils = require('nvim-treesitter.ts_utils')

local VAR_NAME_CAPTURE = 'var'
local PARAMETER_NAME_CAPTURE = 'parameter_name'
local PARAMETER_DESC_CAPTURE = 'parameter_description'

local docs = {}

-- TODO: Figure out how you can document this with no actual code for it.
--          This would let you stub things out very nicely.
---@class Parser

--- Gather the results of a query
---@param bufnr string|number
---@param tree Parser: Already parseed tree
function docs.gather_query_results(bufnr, tree, query_string)
  local root = tree:root()

  local query = vim.treesitter.parse_query("lua", query_string)

  local gathered_results = {}
  for _, match in query:iter_matches(root, bufnr, 0, -1) do
    print("MATCH:", vim.inspect(match))
    local temp = {}
    for match_id, node in pairs(match) do
      local capture_name = query.captures[match_id]
      local text = ts_utils.get_node_text(node, bufnr)[1]

      temp[capture_name] = text
    end

    table.insert(gathered_results, temp)
  end

  return gathered_results
end

function docs.get_query_results(bufnr, query_string)
  local parser = vim.treesitter.get_parser(bufnr, "lua")

  return docs.gather_query_results(bufnr, parser:parse(), query_string)
end

function docs.get_documentation(bufnr)
  local query_string = read("./query/lua/documentation.scm")
  local gathered_results = docs.get_query_results(bufnr, query_string)
  print("GATHERED: ", vim.inspect(gathered_results))

  local results = {}
  for _, match in ipairs(gathered_results) do
    print("MATCH: ", vim.inspect(match))
    local raw_name = match[VAR_NAME_CAPTURE]
    local paramater_name = match[PARAMETER_NAME_CAPTURE]
    local parameter_description = match[PARAMETER_DESC_CAPTURE]

    local parent, name = get_parent_from_var(raw_name)

    local res
    if parent then
      if results[parent] == nil then
        results[parent] = {}
      end

      if results[parent][name] == nil then
        results[parent][name] = {}
      end

      res = results[parent][name]
    else
      if results[name] == nil then
        results[name] = {}
      end

      res = results[name]
    end

    if res.params == nil then
      res.params = {}
    end

    table.insert(res.params, {
      original_parent = parent,
      name = paramater_name,
      desc = parameter_description
    })
  end

  return results
end

docs.get_exports = function(bufnr)
  local return_string = read("./query/lua/module_returns.scm")
  return docs.get_query_results(bufnr, return_string)
end

docs.get_exported_documentation = function(lua_string)
  local documented_items = docs.get_documentation(lua_string)
  local exported_items = docs.get_exports(lua_string)

  local transformed_items = {}
  for _, transform in ipairs(exported_items) do
    if documented_items[transform.defined] then
      transformed_items[transform.exported] = documented_items[transform.defined]

      documented_items[transform.defined] = nil
    end
  end

  for k, v in pairs(documented_items) do
    transformed_items[k] = v
  end

  return transformed_items
end

function docs.test()
  local bufnr = vim.api.nvim_get_current_buf()

  -- local parser = vim.treesitter.get_parser(bufnr, "lua")
  -- print(vim.inspect(docs.get_exports(bufnr)))

  local return_string = read("./query/lua/_test.scm")
  -- print(vim.inspect(docs.get_query_results(bufnr, return_string)))
  print(vim.inspect(docs.get_documentation(bufnr)))

  -- print(vim.inspect(ts_utils.get_node_text(parser:parse():root())))
end

--[[

local contents = read("/home/tj/tmp/small.lua")
print(vim.inspect({docs.get_exported_documentation(contents)}))

-- TODO: Would be nice to be able to use the lua string thing we had before
docs.get_query_results = function(lua_string, query_string)
  local lua_lines = vim.split(lua_string, "\n")
  local parser = vim.treesitter.create_str_parser('lua')

  local tree = parser:parse_str(lua_string)

  return docs.gather_query_results(tree, query_string)
end

--]]

vim.cmd [[nnoremap asdf :lua package.loaded['docs'] = nil; require('docs').test()<CR>]]

return docs