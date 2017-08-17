**YLisp** is a Lisp that plays well with Ruby, like Hy with Python. At least,
that's the intention. Right now, it's extreme alpha software and has many
bugs. But hey! The following works:

    (module A)
    (export get inc)
    (set! i 0)
    (def (inc by:) (set! i (+ i by)))
    (def (get) i)

Compile that to Ruby, and then:

    include A
    puts get # => 0
    inc by: 2
    puts get # => 2

So does the following:

    (puts ("a" | gsub "a" "b" | upcase)) ; => "B"

    (def (greeter my-name)
      (Kernel.print "What's your name? ")
      (set! name (STDIN.readline))
      (if (eq? my-name (at-range name 0 -2))
        (puts (join "Hey, my name is " name " too!"))
        (puts (join "Hi, " name ", mine is " my-name "."))))
    (greeter "Simen")
    > What's your name? Simen
    > Hey, my name is Simen too!

There's also a pretty good S-expression parser in there that preserves location
information on tokens, but still allows you to use them as regular Ruby Arrays,
Symbols, Strings, Fixnums, Hashes etc. (via delegators). I may polish that one
up and actually release it as a gem sometime.

This is currently a toy project - hence the name.<sup>1</sup> So treat it as such.
But it is in active development, and maybe it will reach a releasable state at some point this year.

If you want to try it out for yourself, you can clone the directory,
install the "unparser" gem, then run
`ruby test_compiler.rb` which launches a custom IRB session. From there, you can
compile things using the comp function (which also stores its result in $comp),
use the C constant (and instance of the compiler) and call the compile_in_fn
function, or use the `parse(str)` function.

The actual Ruby codegen is handled by whitequark's Unparser gem (pls implement
proper support for noop nodes--otherwise an outstanding library).

I wouldn't recommend using this right now--if private github directories were
free, this would be one right now. But it might be something I'm comfortable
putting my name on in the future.

### Notes
1. The name references four things: the Y combinator, the inevitable question "Why another Lisp?" and
it's a sly nod to both \_why and to Hy. There is a Common Lisp compiler called YLisp, I believe,
but it's currently vaporware. May need a better name in the future.
