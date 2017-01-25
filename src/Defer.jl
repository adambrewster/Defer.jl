module Defer

export push_scope!, pop_scope!, scope, defer, @defer, @!

const scopes = Any[]

function push_scope!()
  push!(scopes, Any[])
  length(scopes)
end

function pop_scope!(i::Int)
  if i == length(scopes)
    pop_scope!()
  else
    warn("Popping scope $(length(scopes)), expected $i")
    while length(scopes) >= i
      pop_scope!()
    end
  end
end

function pop_scope!(e::Nullable{Any}=Nullable{Any}())
  exceptions = isnull(e) ? Any[] : Any[get(e)]
  this_scope = pop!(scopes)
  for fin in this_scope
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
  push_scope!()
  ex = Nullable{Any}()
  try
    f()
  catch e
    ex = Nullable{Any}(e)
  finally
    pop_scope!(ex)
  end
end

function defer(fin)
  if isempty(scopes) error("defer can only be used within a scope") end
  push!(last(scopes), fin)
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
