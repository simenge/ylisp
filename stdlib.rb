op_add = ->(*args) { args.reduce :+ }
op_sub = ->(*args) { args.reduce :- }
op_div = ->(*args) { args.reduce :/}
op_mul = ->(*args) { args.reduce :* }
op_mod = ->(*args) { args.reduce :% }
op_lt = ->(*args) { args.reduce :< }
op_gt = ->(*args) { args.reduce :> }
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
puts = method :puts
