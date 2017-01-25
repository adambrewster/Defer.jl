module Defer

export scope, defer, @defer, @!

const current_scope = Ref{Nullable{Array}}(Nullable{Array}())

function scope(f)
  old_scope = current_scope[]
  current_scope[] = Nullable([])
  ex = Nullable{CompositeException}()
  try
    f()
  catch e
    ex = Nullable(CompositeException([e]))
  finally
    this_scope = get(current_scope[])
    current_scope[] = old_scope
    for fin in this_scope
      try
        fin()
      catch e
        if isnull(ex)
          ex = Nullable(CompositeException())
        end
        push!(get(ex).exceptions, e)
      end
    end
    empty!(this_scope)
    if !isnull(ex)
      if length(get(ex)) == 1
        rethrow(get(ex).exceptions[1])
      else
        throw(get(ex))
      end
    end
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
