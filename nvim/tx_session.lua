-- tx_session: keeps a per-tmux-pane session file up to date so `tx` can restore
-- this nvim (buffers, splits, tabs, cursor) after a reboot. Managed by ~/.local/bin/tx.
local M = {}
local timer = nil

local function session_file()
  local f = vim.g.tx_session_file
  if type(f) == "string" and f ~= "" then return f end
  return nil
end

function M.save(path)
  path = path or session_file()
  if not path then return 0 end
  vim.g.tx_session_file = path
  local so = vim.o.sessionoptions
  vim.o.sessionoptions = "buffers,curdir,folds,help,tabpages,winsize" -- no "terminal": never re-run commands
  local ok = pcall(vim.cmd, "silent! mksession! " .. vim.fn.fnameescape(path))
  vim.o.sessionoptions = so
  return ok and 1 or 0
end
_G.TxSave = M.save

local function schedule_save()
  if not session_file() then return end
  if timer then timer:stop() else timer = vim.uv.new_timer() end
  timer:start(3000, 0, vim.schedule_wrap(function() M.save() end))
end

function M.setup()
  local pane = vim.env.TMUX_PANE
  if not pane or not vim.env.TMUX then return end
  for _, a in ipairs(vim.v.argv) do
    if a:find("%.git/") then return end -- nvim as git's editor
  end

  -- learn our session file (state dir + pane id) and advertise our RPC socket to tmux
  vim.system({ "tmux", "display", "-p", "-t", pane, "#{@tx_state}\t#{@revive_id}" }, { text = true }, function(r)
    local dir, rid = (r.stdout or ""):match("^(.-)\t(.-)%s*$")
    vim.schedule(function()
      if dir and dir ~= "" and rid and rid ~= "" and not session_file() then
        vim.g.tx_session_file = dir .. "/nvim/" .. rid .. ".vim"
      end
    end)
  end)
  vim.schedule(function()
    if vim.v.servername ~= "" then
      vim.system({ "tmux", "set", "-p", "-t", pane, "@nvim_sock", vim.v.servername })
    end
  end)

  local g = vim.api.nvim_create_augroup("tx_session", { clear = true })
  vim.api.nvim_create_autocmd(
    { "BufEnter", "BufWritePost", "WinNew", "WinClosed", "TabNew", "TabClosed", "VimResized", "CursorHold", "FocusLost" },
    { group = g, callback = schedule_save }
  )
  vim.api.nvim_create_autocmd("VimLeavePre", { group = g, callback = function() M.save() end })
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = g,
    callback = function()
      -- drop sidebar/explorer buffers that don't survive a session reload
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("neo%-tree") or name:match("NvimTree") then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end
    end,
  })
end

return M
