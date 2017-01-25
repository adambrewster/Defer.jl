module Defer

export scope, defer, @defer, @!

const current_scope = Ref{Nullable{Array}}(Nullable{Array}())

function scope(f)
  old_scope = current_scope[]
  current_scope[] = Nullable([])
  try
    f()
  finally
    this_scope = get(current_scope[])
    current_scope[] = old_scope
    for fin in this_scope
      fin()
    end
    empty!(this_scope)
  end
end

function defer(fin)
  if isnull(current_scope[]) error("defer can only be used within a scope") end
  push!(get(current_scope[]), fin)
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
