# Defer.jl
I went looking for the community's current position on finalizers and resource cleanup, and I found a couple of github issues where the
topic has been discussed. I've also looked in to how a few packages that I use handle the problem. The state seems to be that there are
many options each has its own drawbacks, and different packages handle the problem differently. Some of the choices that I've seen:

 - Enforce `do` syntax
 - Provide an exported function and expect the user to call it
 - Add a new method to a function imported from Base and expect users to call it
 - Add finalizers to objects in their constructors
 - Add atexit hooks
 - Reference counting

A future language feature, `with`, might provide for finalizers to be called sooner. Alternately `defer` may also be added to allow the user
to schedule finalizers at resource construction time. I don't see PRs for either of these solutions.

It's not only inconvenient that there's no simple way to mark resources that need to be freed, but different systems in different packages
make it difficult to make sure that all of the resources from all of the packages are freed in the correct order and in a timely matter.

I wrote a quick package to demonstrate something similar to golang's defer. Sample source is in this repository.
Without any help from the compiler, you have to declare each "scope" yourself with `scope() do ... end`. If you don't want to wrap your code
in a do block, then you can `push_scope!()` at the top and `pop_scope!()` when it's finished. Within a scope, you can register a thunk to be
executed when the scope terminates with `defer(thunk)` or `@defer` expression. There's also a `@!` macro that's meant to work like the
proposed `f(...)!` syntax (i.e. it closes it's argument when the enclosing scope terminates).

Advantages of this approach:

 - The do syntax works, but is optional.
 - Resources are always cleaned up in the reverse order of construction.
 - Package authors just need to extend `Base.close` (or some other function we all agree on).
 - There is no need for everybody to implement the
 `open(f::Function, x...) = fd = open(x...); try f(fd) finally close(fd) end`
 pattern for every kind of resource that might meed cleanup.
 - Packages users just have to remember to call close or use `@!`.
 - You can defer any kind of code you want, not just closing.
 - The user controls when resources are cleaned up.
 - It's not dependent on the garbage collector.
 - If the language will ever support golang style defer, then packages using this method will need minor, if any, changes.

Disadvantages:

 - There's probably some overhead for creating scopes. I don't know what this does to the quality of the compiled code.
 - The user has to do some work to get the resources cleaned up.
 - It's possible to leak resources that have already been cleaned up, for example you can get a closed file handle with something like
 `scope() do; @! open("/tmp/junk.txt") end`.
 - It's somewhat unique, and people may find it unfamiliar.
 - Right now it's just yet another way to solve the problem, and it's inconsistent and somewhat incompatible with all of the the others.
