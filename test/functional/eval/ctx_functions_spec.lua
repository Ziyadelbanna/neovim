local helpers = require('test.functional.helpers')(after_each)

local call = helpers.call
local clear = helpers.clear
local command = helpers.command
local eq = helpers.eq
local eval = helpers.eval
local expect_err = helpers.expect_err
local feed = helpers.feed
local map = helpers.map
local nvim = helpers.nvim
local parse_context = helpers.parse_context
local redir_exec = helpers.redir_exec
local source = helpers.source
local trim = helpers.trim
local write_file = helpers.write_file

describe('context functions', function()
  local fname1 = 'Xtest-functional-eval-ctx1'
  local fname2 = 'Xtest-functional-eval-ctx2'
  local outofbounds =
    'Vim:E475: Invalid value for argument index: out of bounds'

  before_each(function()
    clear()
    write_file(fname1, "1\n2\n3")
    write_file(fname2, "a\nb\nc")
  end)

  after_each(function()
    os.remove(fname1)
    os.remove(fname2)
  end)

  describe('ctxpush/ctxpop', function()
    it('saves and restores registers properly', function()
      local regs = {'1', '2', '3', 'a'}
      local vals = {'1', '2', '3', 'hjkl'}
      feed('i1<cr>2<cr>3<c-[>ddddddqahjklq')
      eq(vals, map(function(r) return trim(call('getreg', r)) end, regs))
      call('ctxpush')
      call('ctxpush', {'regs'})

      map(function(r) call('setreg', r, {}) end, regs)
      eq({'', '', '', ''},
         map(function(r) return trim(call('getreg', r)) end, regs))

      call('ctxpop')
      eq(vals, map(function(r) return trim(call('getreg', r)) end, regs))

      map(function(r) call('setreg', r, {}) end, regs)
      eq({'', '', '', ''},
         map(function(r) return trim(call('getreg', r)) end, regs))

      call('ctxpop')
      eq(vals, map(function(r) return trim(call('getreg', r)) end, regs))
    end)

    it('saves and restores jumplist properly', function()
      command('edit '..fname1)
      feed('G')
      feed('gg')
      command('edit '..fname2)
      local jumplist = call('getjumplist')
      call('ctxpush')
      call('ctxpush', {'jumps'})

      command('clearjumps')
      eq({{}, 0}, call('getjumplist'))

      call('ctxpop')
      eq(jumplist, call('getjumplist'))

      command('clearjumps')
      eq({{}, 0}, call('getjumplist'))

      call('ctxpop')
      eq(jumplist, call('getjumplist'))
    end)

    it('saves and restores buffer list properly', function()
      command('edit '..fname1)
      command('edit '..fname2)
      command('edit TEST')
      local buflist = call('map', call('getbufinfo'), 'v:val.name')
      call('ctxpush')
      call('ctxpush', {'buflist'})

      command('%bwipeout')
      eq({''}, call('map', call('getbufinfo'), 'v:val.name'))

      call('ctxpop')
      eq({'', unpack(buflist)}, call('map', call('getbufinfo'), 'v:val.name'))

      command('%bwipeout')
      eq({''}, call('map', call('getbufinfo'), 'v:val.name'))

      call('ctxpop')
      eq({'', unpack(buflist)}, call('map', call('getbufinfo'), 'v:val.name'))
    end)

    it('saves and restores global variables properly', function()
      nvim('set_var', 'one', 1)
      nvim('set_var', 'Two', 2)
      nvim('set_var', 'THREE', 3)
      eq({1, 2 ,3}, eval('[g:one, g:Two, g:THREE]'))
      call('ctxpush')
      call('ctxpush', {'gvars'})

      nvim('del_var', 'one')
      nvim('del_var', 'Two')
      nvim('del_var', 'THREE')
      expect_err('E121: Undefined variable: g:one', eval, 'g:one')
      expect_err('E121: Undefined variable: g:Two', eval, 'g:Two')
      expect_err('E121: Undefined variable: g:THREE', eval, 'g:THREE')

      call('ctxpop')
      eq({1, 2 ,3}, eval('[g:one, g:Two, g:THREE]'))

      nvim('del_var', 'one')
      nvim('del_var', 'Two')
      nvim('del_var', 'THREE')
      expect_err('E121: Undefined variable: g:one', eval, 'g:one')
      expect_err('E121: Undefined variable: g:Two', eval, 'g:Two')
      expect_err('E121: Undefined variable: g:THREE', eval, 'g:THREE')

      call('ctxpop')
      eq({1, 2 ,3}, eval('[g:one, g:Two, g:THREE]'))
    end)

    it('saves and restores script functions properly', function()
      source([[
      function s:greet(name)
        echom 'Hello, '.a:name.'!'
      endfunction

      function s:greet_all(name, ...)
        echom 'Hello, '.a:name.'!'
        for more in a:000
          echom 'Hello, '.more.'!'
        endfor
      endfunction

      function Greet(name)
        call call('s:greet', [a:name])
      endfunction

      function GreetAll(name, ...)
        call call('s:greet_all', extend([a:name], a:000))
      endfunction

      function SaveSFuncs()
        call ctxpush(['sfuncs'])
      endfunction

      function DeleteSFuncs()
        delfunction s:greet
        delfunction s:greet_all
      endfunction

      function RestoreFuncs()
        call ctxpop()
      endfunction
      ]])

      eq('\nHello, World!', redir_exec([[call Greet('World')]]))
      eq('\nHello, World!'..
         '\nHello, One!'..
         '\nHello, Two!'..
         '\nHello, Three!',
         redir_exec([[call GreetAll('World', 'One', 'Two', 'Three')]]))

      call('SaveSFuncs')
      call('DeleteSFuncs')

      eq('\nError detected while processing function Greet:'..
         '\nline    1:'..
         '\nE117: Unknown function: s:greet',
         redir_exec([[call Greet('World')]]))
      eq('\nError detected while processing function GreetAll:'..
         '\nline    1:'..
         '\nE117: Unknown function: s:greet_all',
         redir_exec([[call GreetAll('World', 'One', 'Two', 'Three')]]))

      call('RestoreFuncs')

      eq('\nHello, World!', redir_exec([[call Greet('World')]]))
      eq('\nHello, World!'..
         '\nHello, One!'..
         '\nHello, Two!'..
         '\nHello, Three!',
         redir_exec([[call GreetAll('World', 'One', 'Two', 'Three')]]))
    end)

    it('saves and restores functions properly', function()
      source([[
      function Greet(name)
        echom 'Hello, '.a:name.'!'
      endfunction

      function GreetAll(name, ...)
        echom 'Hello, '.a:name.'!'
        for more in a:000
          echom 'Hello, '.more.'!'
        endfor
      endfunction
      ]])

      eq('\nHello, World!', redir_exec([[call Greet('World')]]))
      eq('\nHello, World!'..
         '\nHello, One!'..
         '\nHello, Two!'..
         '\nHello, Three!',
         redir_exec([[call GreetAll('World', 'One', 'Two', 'Three')]]))

      call('ctxpush', {'funcs'})
      command('delfunction Greet')
      command('delfunction GreetAll')

      expect_err('Vim:E117: Unknown function: Greet', call, 'Greet', 'World')
      expect_err('Vim:E117: Unknown function: Greet', call, 'GreetAll',
                 'World', 'One', 'Two', 'Three')

      call('ctxpop')

      eq('\nHello, World!', redir_exec([[call Greet('World')]]))
      eq('\nHello, World!'..
         '\nHello, One!'..
         '\nHello, Two!'..
         '\nHello, Three!',
         redir_exec([[call GreetAll('World', 'One', 'Two', 'Three')]]))
    end)

    it('errors out when context stack is empty', function()
      local err = 'Vim:Context stack is empty'
      expect_err(err, call, 'ctxpop')
      expect_err(err, call, 'ctxpop')
      call('ctxpush')
      call('ctxpush')
      call('ctxpop')
      call('ctxpop')
      expect_err(err, call, 'ctxpop')
    end)
  end)

  describe('ctxsize()', function()
    it('returns context stack size', function()
      eq(0, call('ctxsize'))
      call('ctxpush')
      eq(1, call('ctxsize'))
      call('ctxpush')
      eq(2, call('ctxsize'))
      call('ctxpush')
      eq(3, call('ctxsize'))
      call('ctxpop')
      eq(2, call('ctxsize'))
      call('ctxpop')
      eq(1, call('ctxsize'))
      call('ctxpop')
      eq(0, call('ctxsize'))
    end)
  end)

  describe('ctxget()', function()
    it('errors out when index is out of bounds', function()
      expect_err(outofbounds, call, 'ctxget')
      call('ctxpush')
      expect_err(outofbounds, call, 'ctxget', 1)
      call('ctxpop')
      expect_err(outofbounds, call, 'ctxget', 0)
    end)

    it('returns context dictionary at index in context stack', function()
      feed('i1<cr>2<cr>3<c-[>ddddddqahjklq')
      command('edit! '..fname1)
      feed('G')
      feed('gg')
      command('edit '..fname2)
      nvim('set_var', 'one', 1)
      nvim('set_var', 'Two', 2)
      nvim('set_var', 'THREE', 3)

      local with_regs = {
        ['regs'] = {
          {['rt'] = 1, ['rc'] = {'1'}, ['n'] = 49, ['ru'] = true},
          {['rt'] = 1, ['rc'] = {'2'}, ['n'] = 50},
          {['rt'] = 1, ['rc'] = {'3'}, ['n'] = 51},
          {['rc'] = {'hjkl'}, ['n'] = 97},
        }
      }

      local with_jumps = {
        ['jumps'] = eval(([[
        filter(map(getjumplist()[0], 'filter(
          { "f": expand("#".v:val.bufnr.":p"), "l": v:val.lnum },
          { k, v -> k != "l" || v != 1 })'), '!empty(v:val.f)')
        ]]):gsub('\n', ''))
      }

      local with_buflist = {
        ['buflist'] = eval([[
        filter(map(getbufinfo(), '{ "f": v:val.name }'), '!empty(v:val.f)')
        ]])
      }

      local with_gvars = {
        ['gvars'] = {{'one', 1}, {'Two', 2}, {'THREE', 3}}
      }

      local with_all = {
        ['regs'] = with_regs['regs'],
        ['jumps'] = with_jumps['jumps'],
        ['buflist'] = with_buflist['buflist'],
        ['gvars'] = with_gvars['gvars'],
      }

      call('ctxpush')
      eq(with_all, parse_context(call('ctxget')))
      eq(with_all, parse_context(call('ctxget', 0)))

      call('ctxpush', {'gvars'})
      eq(with_gvars, parse_context(call('ctxget')))
      eq(with_gvars, parse_context(call('ctxget', 0)))
      eq(with_all, parse_context(call('ctxget', 1)))

      call('ctxpush', {'buflist'})
      eq(with_buflist, parse_context(call('ctxget')))
      eq(with_buflist, parse_context(call('ctxget', 0)))
      eq(with_gvars, parse_context(call('ctxget', 1)))
      eq(with_all, parse_context(call('ctxget', 2)))

      call('ctxpush', {'jumps'})
      eq(with_jumps, parse_context(call('ctxget')))
      eq(with_jumps, parse_context(call('ctxget', 0)))
      eq(with_buflist, parse_context(call('ctxget', 1)))
      eq(with_gvars, parse_context(call('ctxget', 2)))
      eq(with_all, parse_context(call('ctxget', 3)))

      call('ctxpush', {'regs'})
      eq(with_regs, parse_context(call('ctxget')))
      eq(with_regs, parse_context(call('ctxget', 0)))
      eq(with_jumps, parse_context(call('ctxget', 1)))
      eq(with_buflist, parse_context(call('ctxget', 2)))
      eq(with_gvars, parse_context(call('ctxget', 3)))
      eq(with_all, parse_context(call('ctxget', 4)))

      call('ctxpop')
      eq(with_jumps, parse_context(call('ctxget')))
      eq(with_jumps, parse_context(call('ctxget', 0)))
      eq(with_buflist, parse_context(call('ctxget', 1)))
      eq(with_gvars, parse_context(call('ctxget', 2)))
      eq(with_all, parse_context(call('ctxget', 3)))

      call('ctxpop')
      eq(with_buflist, parse_context(call('ctxget')))
      eq(with_buflist, parse_context(call('ctxget', 0)))
      eq(with_gvars, parse_context(call('ctxget', 1)))
      eq(with_all, parse_context(call('ctxget', 2)))

      call('ctxpop')
      eq(with_gvars, parse_context(call('ctxget')))
      eq(with_gvars, parse_context(call('ctxget', 0)))
      eq(with_all, parse_context(call('ctxget', 1)))

      call('ctxpop')
      eq(with_all, parse_context(call('ctxget')))
      eq(with_all, parse_context(call('ctxget', 0)))
    end)
  end)

  describe('ctxset()', function()
    it('errors out when index is out of bounds', function()
      expect_err(outofbounds, call, 'ctxset', {dummy = 1})
      call('ctxpush')
      expect_err(outofbounds, call, 'ctxset', {dummy = 1}, 1)
      call('ctxpop')
      expect_err(outofbounds, call, 'ctxset', {dummy = 1}, 0)
    end)

    it('sets context dictionary at index in context stack', function()
      nvim('set_var', 'one', 1)
      nvim('set_var', 'Two', 2)
      nvim('set_var', 'THREE', 3)
      call('ctxpush')
      local ctx1 = call('ctxget')
      nvim('set_var', 'one', 'a')
      nvim('set_var', 'Two', 'b')
      nvim('set_var', 'THREE', 'c')
      call('ctxpush')
      call('ctxpush')
      local ctx2 = call('ctxget')

      eq({'a', 'b' ,'c'}, eval('[g:one, g:Two, g:THREE]'))
      call('ctxset', ctx1)
      call('ctxset', ctx2, 2)
      call('ctxpop')
      eq({1, 2 ,3}, eval('[g:one, g:Two, g:THREE]'))
      call('ctxpop')
      eq({'a', 'b' ,'c'}, eval('[g:one, g:Two, g:THREE]'))
      nvim('set_var', 'one', 1.5)
      eq({1.5, 'b' ,'c'}, eval('[g:one, g:Two, g:THREE]'))
      call('ctxpop')
      eq({'a', 'b' ,'c'}, eval('[g:one, g:Two, g:THREE]'))
    end)
  end)
end)
