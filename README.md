# Defer.jl
Defer.jl provides simplified resource cleanup in julia.  When julia programs interface with external resources (often 
wrapping external libraries), they must often arrange for those resources to be freed, closed, cleaned up, or otherwise 
disposed of after use.  This package provides a golang inspired `@defer` macro to make it easier for users to free resources
at the correct time.

## Basic Usage
The most basic usage is to create a scope and execute code within it.  Within a scope you can schedule code for execution when the scope terminates.
```
@scope begin
    @defer println("world")
    println("hello")
end
```
prints
```
hello
world
```

`@!` is a shortcut for deferring a call to close.
```
type A
    a::String
end
Base.close(a::A) = println("Closing $a")
use(a::A) = println("Using $a")
@scope begin
    a = @! A("a")
    use(a)
end
```
prints
```
Using A("a")
Closing A("a")
```

## Module Development
Module authors should use `defer` to schedule cleanup of resources allocated in the `__init__()` function.  (A global 
top-level scope is always exists.)  The user may execute all pending `defer`ed actions by calling `pop_scope!(1)`.  The 
module can then be reinitialized by the user calling `__init__()`.

Modules should *not* use `defer` (or `finalizer`) to schedule cleanup of resources allocated by the user.  Instead, add a 
method to `Base.close`, so that your user may schedule cleanup of the resource easily by adding `@!` where your constructor
is called.

```
module Example
include("libfoo.jl")

# Some global context that our library uses
const foo_context = Ref{fooContext_t}(C_NULL)

# Initialize the library when the module is (re-)loaded
function __init__()
  fooCreateContext(foo_context)
  # don't use atexit, defer the action instead
  @defer fooDestroyContext(foo_context[])
end

# An object in the library that will be made available to julia users
immutable Foo
  ptr::fooThing_t
end

# Create the object in the wrapper constructor
function Foo(x...)
  thing = Ref{fooThing_t}
  fooCreateThing(foo_context[], thing, x...)
  # don't schedule thing to be destroyed!
  Foo(thing[])
end

# Extend the close function so the user can call @! Foo(...) to create an object and control when it will be destroyed.
Base.close(foo::Foo) = fooDestroyThing(foo_context[], foo.ptr)
end
```

## More Usage

Sometimes `scope() do ... end` is inconvenient, so there's also a `@scope` macro.
```
function f()
    a = @! A("a")
    use(a)
end
@scope f()
```
is equivalent to the above.

When applied to a method definition, `@scope` wraps the body in a scope.
```julia
@scope g() use(@! A("a"))
g()
```
is also equivalent.

`@scope` can also be applied to a `let` statement to wrap the statement in a scope
and automatically schedule all of the `let`ed variables to be closed.
```julia
@scope let f = open("/dev/null", "w")
  println(f, "Hello, nobody!")
end
```

Exceptions from the scope or its deferred actions propagate to the caller.  If there are multiple exceptions, they're wrapped in a
`CompositeException`.
```
try
    scope() do
        @defer throw("Defered exception")
        throw("Exception")
    end
catch e
    @show e
    nothing
end
```
prints
```
e = CompositeException(Any["Exception","Defered exception"])
```
