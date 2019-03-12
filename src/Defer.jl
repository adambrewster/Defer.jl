# Copyright 2017 Massachusetts Institute of Technology. See LICENSE file for details.

__precompile__(true)
module Defer
import Base.GC

export push_scope!, pop_scope!, scope, scope_nogc, @scope, defer, @defer, defer_call, @!

const scopes = Any[Any[]]
const ExceptionWrapper = Union{Some{Any}, Nothing}

function push_scope!()
  push!(scopes, Any[])
  length(scopes)
end

function pop_scope!(i::Int, e::ExceptionWrapper=nothing)
  if i == length(scopes)
    pop_scope!(e)
  else
    @assert i > 0
    warn("Popping scope $(length(scopes)), expected $i")
    if length(scopes) < i
      if e != nothing
        throw(something(e))
      end
    else
      while length(scopes) > i
        pop_scope!()
      end
      pop_scope!(e)
    end
  end
end

function pop_scope!(e::ExceptionWrapper=nothing)
  exceptions = e==nothing ? Any[] : Any[something(e)]
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
      throw(exceptions[1])
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
  ex = Ref{Union{Some{Any},Nothing}}(nothing)
  try
    f()
  catch e
    ex[] = Some(e)
  finally
    pop_scope!(sc, Some(e))
  end
end

function scope_nogc(f)
  gc_enabled = GC.enable(false)
  sc = push_scope!()
  ex = Ref{Union{Some{Any},Nothing}}(nothing)
  try
    f()
  catch e
    ex[] = Some(e)
  finally
    pop_scope!(sc, ex[])
    if gc_enabled
      GC.enable(true)
    end
  end
end

_scope(code::Expr) = quote
  sc = push_scope!()
  ex = Ref{Union{Some{Any},Nothing}}(nothing)
  try
    $code
  catch e
    ex[] = Some(e)
  finally
    pop_scope!(sc, ex[])
  end
end

macro scope(code)
  if !isa(code, Expr) return esc(code) end
  if code.head == :let
    flet(x::Expr) = :($(esc(x.args[1])) = defer_call($(esc(x.args[2]))))
    newcode = Expr(:let, code.args[1], esc(code.args[2]))
    if code.args[1].head == :(=)
      newcode.args[1] = flet(code.args[1])
    else
      for i in 1:length(code.args[1].args)
        @assert code.args[1].args[i].head == :(=)
        newcode.args[1].args[i] = flet(code.args[1].args[i])
      end
    end
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
