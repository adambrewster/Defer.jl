# Copyright 2017 Massachusetts Institute of Technology. See LICENSE file for details.

__precompile__(true)
module Defer

export push_scope!, pop_scope!, scope, scope_nogc, @scope, defer, @defer, defer_call, @!

const scopes = Any[Any[]]

function push_scope!()
  push!(scopes, Any[])
  length(scopes)
end

function pop_scope!(i::Int, e::Nullable{Any}=Nullable{Any}())
  if i == length(scopes)
    pop_scope!(e)
  else
    @assert i > 0
    warn("Popping scope $(length(scopes)), expected $i")
    if length(scopes) < i
      if !isnull(e)
        rethrow(get(e))
      end
    else
      while length(scopes) > i
        pop_scope!()
      end
      pop_scope!(e)
    end
  end
end

function pop_scope!(e::Nullable{Any}=Nullable{Any}())
  exceptions = isnull(e) ? Any[] : Any[get(e)]
  this_scope = pop!(scopes)
  if isempty(scopes)
    push!(scopes, Any[])
  end
  for fin in reverse(this_scope)
    try
      fin()
    catch e
      push!(exceptions, e)
    end
  end
  empty!(this_scope)
  if !isempty(exceptions)
    if length(exceptions) == 1
      rethrow(exceptions[1])
    else
      e = CompositeException()
      append!(e.exceptions, exceptions)
      throw(e)
    end
  end
  nothing
end

function scope(f)
  sc = push_scope!()
  ex = Nullable{Any}()
  try
    f()
  catch e
    ex = Nullable{Any}(e)
  finally
    pop_scope!(sc, ex)
  end
end

function scope_nogc(f)
  gc_enabled = gc_enable(false)
  sc = push_scope!()
  ex = Nullable{Any}()
  try
    f()
  catch e
    ex = Nullable{Any}(e)
  finally
    pop_scope!(sc, ex)
    if gc_enabled
      gc_enable(true)
    end
  end
end

_scope(code::Expr) = quote
  sc = push_scope!()
  ex = Nullable{Any}()
  try
    $code
  catch e
    ex = Nullable{Any}(e)
  finally
    pop_scope!(sc, ex)
  end
end

macro scope(code)
  if !isa(code, Expr) return esc(code) end
  if code.head == :let
    newcode = Expr(:let, esc(code.args[1]))
    append!(newcode.args, map(code.args[2:end]) do a
      @assert a.head == :(=)
      var = esc(a.args[1])
      val = esc(a.args[2])
      :($var = defer_call($val))
    end)
    return _scope(newcode)
  elseif code.head == :(=)
    return Expr(:(=), esc(code.args[1]), _scope(esc(code.args[2])))
  elseif code.head == :function
    return Expr(:function, esc(code.args[1]), _scope(esc(code.args[2])))
   else
    return _scope(esc(code))
  end
end

function defer(fin, sc::Integer=0)
  push!(scopes[sc > 0 ? sc : length(scopes) + sc], fin)
  nothing
end

function defer_call(x, f::Function=close, sc::Integer=0)
  defer(()->f(x), sc)
  x
end

macro defer(code)
  quote
    defer(()->$(esc(code)))
  end
end

macro !(value)
  quote
    defer_call($(esc(value)))
  end
end
end
