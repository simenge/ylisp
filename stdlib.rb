module YLisp
  module STDLIB
    EXPORTS = %i[__add__ __sub__ __div__ __mod__ __gt__ __lt__ eq_p
                join puts]
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
    def __mod__(*args)
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
      i = 0
      while i < args.size
        return false if args[i] != args[i+=1]
      end
    end
    def join(*args)
      args.map { |x| x.to_s }.join ""
    end
    puts = method :puts
  end
end
