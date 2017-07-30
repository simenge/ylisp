module YLisp
  module Node
    class Node < Array
      attr_accessor :env
    end

    class Env
      def initialize(parent = nil)
        @env = {}
        @parent = parent
      end

      def [](name)
        if @env.has_key? name
          @env[name]
        elsif @parent
          @parent.get name
        else
          raise KeyError
        end
      end

      def []=(name, value)
        @env[name] = value
      end
    end

    def establish_envs(e, env=Env.new)
      case e
      when Array
        return handle_array(e, env)
      else
        e
      end
    end

    class Function
      def initialize(name, args, body, env)
        @name, @args, @body, @env = name, args, body, env
      end
      attr_accessor :name, :args, :body, :env
    end

    class Module
      def initialize(name, parent)
        @name, @parent = name, parent
        @exports = []
      end
      attr_accessor :name, :exports, :parent
    end

    private
    def handle_array(e, env)
      a = Node.new e
      a.env = env
      if a[0] == :"->" or a[0] == :lambda
        a.env = Env.new env
      elsif a[0] == :def
        a.env = Env.new env
        perror("def should be of the form (def (name args) body)", e.size < 3)
        perror("def should be of the form (def (name args) body)", !e[1].is_a?(Array) || e[1].empty?)
        name = e[1].first
        body = handle_array(e[2..-1], a.env)
        env[name] = Function.new name, e[1][1..-1], body, env
        a
      else
        a.map { |x| establish_envs(x, a.env) }
      end
    end

  end
end
