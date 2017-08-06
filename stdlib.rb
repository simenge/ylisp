__add__ = ->(*args) { args.reduce :+ }
__sub__ = ->(*args) { args.reduce :- }
__div__ = ->(*args) { args.reduce :/}
__mul__ = ->(*args) { args.reduce :* }
__mod__ = ->(*args) { args.reduce :% }
__lt__ = ->(*args) { args.reduce :< }
__gt__ = ->(*args) { args.reduce :> }
eq_p = ->(*args) do
  if args.size == 1
    raise ArgumentError, "eq? requires 2+ arguments"
  elsif args[0] == args[1]
    if args.size == 2
      true
    else
      eq_p.call *args[1..-1]
    end
  end
end
join = ->(*args) do
  args.map { |x| x.to_s }.join ""
end
puts = method :puts
