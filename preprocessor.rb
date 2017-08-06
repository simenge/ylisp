module YLisp
  module Preprocessor
    require "thread"
    class Gensym
      def initialize(prefix = "__gensym", counter = 1234)
        @counter, @prefix = counter, prefix
        @lock = Mutex.new
      end

      def gensym
        @lock.synchronize do
          counter = @counter
          @counter += 1
          (@prefix + counter.to_s).to_sym
        end
      end
    end

    Generator = Gensym.new

    class Env
      def initialize(parent = nil)
        @hash = {}
        @parent = parent
        @sym = Generator.gensym
        @genbind = false
      end

      attr_accessor :sym, :genbind

      def get(val)
        if @hash.has_key? val
          [@hash[val], self]
        elsif @parent
          @parent.get val
        else
          nil
        end
      end

      def set(var, val=true)
        @hash[var]=val
      end

      def to_s
        "Env(#{@hash} parent: #{@parent})"
      end
    end

    # (set! <var> <val>) should modify an existing binding in an enclosing
    # scope, if one exists. This requires some trickery.
    def process(e, env = Env.new)
      if e == [] || !e.is_a?(Array)
        return e
      end
      if e.first == :set!
        handle_set e, env
      elsif e.first == :lambda || e.first == :"->"
        lam = process_lambda e, Env.new(env)
        if env.genbind
          genbind env, lam
        else
          lam
        end
      elsif e.first == :def
        if e[1].is_a? Array
          env.set e[1].first
        else
          env.set e[1]
        end
        e
      else
        e.map { |x| process x, env }
      end
    end

    def handle_set(e, env)
      name, value = e[1], e[2]
      var, scope = env.get name
      if var && scope != env
        env.set name
        scope.genbind = true
        up_set name, value, scope
      else
        env.set name
        e
      end
    end

    def process_lambda(e, env)
      e[1].each { |arg| env.set arg }
      e[2..-1] = e[2..-1].map { |x| process x, env }
      e
    end

    def genbind(env, rest)
      [:begin, [:set!, env.sym, [:binding]], rest]
    end

    def up_set(var, val, env)
      [:ruby_eval, [:join, var, "=", val], env.sym]
    end

    def test
      require "pp"
      pp process([:begin, [:set!, :x, 1], [:lambda, [], [:set!, :x, 2]]])
      pp process([:begin, [:set!, :x, 1], [:lambda, [:y], 1]])
    end

  end
end
