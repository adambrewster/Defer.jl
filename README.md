# Defer.jl
Defer.jl provides simplified resource cleanup in julia.  When julia programs interface with external resources (often 
wrapping external libraries), they must often arrange for those resources to be freed, closed, cleaned up, or otherwise 
disposed of after use.  This package provides a golang inspired `@defer` macro to make it easier for users to free resources
at the correct time.

This package is meant as a pathfinder for an eventual language feature that will take its place.  In the meantime, it's usable
in its current form.  By adopting this convention now you will be ready for the future and also help shape the language by
determining which forms are most useful and which corner cases cause friction.

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
@scope g() = use(@! A("a"))
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
        @defer throw("Deferred exception")
        throw("Exception")
    end
catch e
    @show e
    nothing
end
```
prints
```
e = CompositeException(Any["Exception","Deferred exception"])
```

# Future Work
This package is offered as an example of how deferred resource clean-up may work in julia.
Package authors may experiment to see if the feature is useful, and the maintainers of the
language may follow its example and lessons learned in implementing a similar feature in julia.

Additional work and questions to be resolved to adopt such a feature include the following:

 - *Which function should be used to dispose of resources?*
I chose to use `close` for this purpose because it already exists in Base and any other
extension of the function is unlikely to conflict with this usage.  Extending `finalize`
interferes with that function's usage to call any finalizers scheduled on the object.
Other options (e.g. `dispose`, `destroy`, `cleanup`, etc) may be suitable but are commonly
used in other packages so that their use in this package would conflict, but the community
could adopt one such function, and export it from Base.

 - *When should deferred actions be executed?*
This package requires the user to specify when deferred actions are to be run by declaring scopes.
A built-in language feature would likely adopt a rule such as at the end of the currently executing
function or let-block.  In particular, deferred actions should not be executed when lines from the
REPL of IJulia cells terminate or when a module is initialized.

 - *Should module initialization be a special case?*
I have suggested the `__init__` function always be run a scope which will exist for life of the
module.  Alternately, there could be a corresponding `__uninit__` function which could be used
to similar effect.

- *Should a package author schedule for destruction resources which will be returned to the user?*
The current practice of scheduling resources for destruction in their constructor (e.g. by calling
`finalizer` or similar) is convenient when called directly from the REPL as the user can usually
not worry about resource clean-up.  For performance sensitive code, however, the option to handle resource
cleanup manually may be necessary.  It would be useful for the community to adopt a single
convention for package authors to follow in addressing these two competing desires.
