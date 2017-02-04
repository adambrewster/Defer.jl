using Base.Test, Defer

type E end
type F end

const closables = Set{Any}()
type Closable
  closed::Bool
  name::String
  Closable(name::String) = let a = new(false, name); push!(closables, a); a; end
end

Base.close(c::Closable) = (c.closed = true; nothing)

type Unclosable
  closed::Bool
  name::String
  Unclosable(name::String) = let a = new(false, name); push!(closables, a); a; end
end

Base.close(c::Unclosable) = (c.closed = true; throw(E()))

function verify_closed()
  setdiff!(closables, filter(x->x.closed, closables))
  if !isempty(closables)
    error(string("Unclosed objects: ", join(map(x->x.name, closables), ", ")))
  end
end

Closable("A")
@test_throws ErrorException verify_closed()
empty!(closables)

Unclosable("B")
@test_throws ErrorException verify_closed()
empty!(closables)

@scope begin
  @defer close(Closable("1"))
end
verify_closed()

@test_throws F @scope begin
  throw(F())
  @defer close(Closable("2"))
end
verify_closed()

@test_throws F @scope begin
  @defer close(Closable("3"))
  throw(F())
end
verify_closed()

@test_throws E @scope begin
  @defer close(Unclosable("4"))
end
verify_closed()

@test_throws F @scope begin
  throw(F())
  @defer close(Unclosable("5"))
end
verify_closed()

@test_throws CompositeException @scope begin
  @defer close(Unclosable("6"))
  throw(F())
end
verify_closed()

@test_throws CompositeException @scope begin
  @defer close(Unclosable("7"))
  @defer close(Unclosable("8"))
end
verify_closed()

@scope @! Closable("9")
verify_closed()