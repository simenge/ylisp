module YLisp
  module STDLIB
    EXPORTS = %i[__add__ __sub__ __mul__ __div__ __mod__ __lt__ __gt__
      eq_p join at puts ruby_eval at_range]

    def __add__(*args)
      args.reduce :+
    end
    def __sub__(*args)
      args.reduce :-
    end
    def __div__(*args)
      args.reduce :/
    end
    def __mul__(*args)
      args.reduce :*
    end
    def mod(*args)
      args.reduce :%
    end
    def __lt__(*args)
      args.reduce :<
    end
    def __gt__(*args)
      args.reduce :>
    end
    def eq_p(*args)
      if args.size == 1
        raise ArgumentError, "eq? requires 2+ arguments"
      end
      loop do
        return true if args == []
        x, y = args.shift, args.shift
        return false unless x == y
      end
    end
    def join(*args)
      args.map { |x| x.to_s }.join ""
    end
    def puts(*a)
      Kernel.puts *a
    end
    def at(list, n)
      list[n]
    end
    def at_range(list, n, m)
      list[n..m]
    end
    def ruby_eval(e)
      eval e
    end
  end
end
