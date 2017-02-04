module Defer

export push_scope!, pop_scope!, scope, scope_nogc, @scope, defer, @defer, @!

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
      throw(CompositeException(exceptions))
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

macro scope(code)
  quote
    sc = push_scope!()
    ex = Nullable{Any}()
    try
      $(esc(code))
    catch e
      ex = Nullable{Any}(e)
    finally
      pop_scope!(sc, ex)
    end
  end
end

function defer(fin, sc::Integer=0)
  push!(scopes[sc > 0 ? sc : length(scopes) + sc], fin)
  nothing
end

macro defer(code)
  quote
    defer(()->$(esc(code)))
  end
end

macro !(value)
  quote
    v = $(esc(value))
    @defer close(v)
    v
  end
end
end
