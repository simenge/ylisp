require "unparser"
require "./stdlib.rb"
require "./preprocessor.rb"
require "./yparser.rb"

module YLisp
  include Preprocessor
  include YParser
  P = YParser::YParser
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end


  class ParseError < Exception; end
  def perror(msg, cond = true)
    if cond
      raise ParseError, msg
    end
  end

  class YModule
    def initialize(name, exports = [], env={})
      @name, @exports, @env = name, exports, env
    end
    attr_accessor :name, :exports, :env
  end


  class Compiler
    include Preprocessor
    OPERATORS = {
      "+" => "__add__",
      "-" => "__sub__",
      "*" => "__mul__",
      "/" => "__div__",
      "%" => "__mod__",
      ">" => "__gt__",
      "<" => "__lt__"
    }
    NOOP = Generator.gensym

    attr_accessor :module

    def initialize
      @modules = []
      @module = nil
    end

    def compile_function(name:, args:, body:)
      # This hairy bit represents the following Ruby:
      #
      #   define_method(name) do |<argspec>|
      #    name.call <argspec>
      #   end
      #
      # where <argspec> is the function's argument specification.
      #
      # The idea is that by doing it this way, we have access to the
      # parent scope, in which a local variable named the same as the
      # method is assigned to a Proc, and we will now be able to access that,
      # passing
      # on all arguments to the Proc. This way we can export methods for use
      # in Ruby or other Lisp modules while at the same time keeping our
      # Lisp-1 namespacing, in which functions and variables live side by side.
      @module.env[name] = s(:block,
          s(:send, nil, :define_method,
            s(:sym, name)),
            s(:args, *args),
            s(:send,
              s(:lvar, name), :call,
                *parse_args_call(args.children)))
    end

    # Translate argument spec AST into call AST
    def parse_args_call(a)
      a.map do |arg|
        next unless arg
        name = arg.children.first
        if arg.type == :arg
          s(:lvar, name)
        elsif arg.type == :restarg
          s(:splat, s(:lvar, name))
        elsif arg.type == :blockarg
          s(:block_pass, s(:lvar, name))
        elsif arg.type == :kwarg
          s(:pair, s(:sym, name), s(:lvar, name))
        elsif arg.type == :kwrestarg
          s(:kwsplat, s(:lvar, name))
        else
          s(:lvar, name)
        end
      end
    end

    def compile_module(mod = nil)
      mod ||= @module
      res = []
      @module.env.each do |key, value|
        if @module.exports.include? key
          res << value
        end
      end
      s(:begin, *res)
    end

    def compile_str(s)
      compile [:begin, *P.new(s).parse]
    end

    def compile_str_module(s)
      s = YLisp::YParser.parse_string s
      exprs = __compile(s)
      to_ruby wrap_in_fn(s(:begin, exprs, compile_module))
    end

    def compile(e)
      to_ruby __compile(e)
    end

    def __compile(e)
      e = process e
      if !e.is_a? Array
        debug "compiling literal #{e}"
        return compile_literal e
      end
      if e == []
        return s(:array)
      elsif e.first == :quote
        compile_quote e
      end
      e = compile_pipes e
      if e.first == :begin
        if e.first.is_a?(Array) && e.first.first == :begin
          # We have a module header
          return handle_mod_header e[1..-1]
        end
        s(:begin, *e[1..-1].map { |x| __compile x })
      elsif e.first == :module
        __module e
      elsif e.first == :export
        handle_exports e[1..-1]
        s(:nil)
      elsif e.first == :def
        compile_def e
      elsif e.first == :"->" or e.first == :lambda
        leave_toplevel { compile_lambda e }
      elsif e.first == :"quasiquote"
        compile_quasiquote e[1..-1]
      elsif e.first == :if
        perror("if takes the form (if cond then optional-else)", !(e.size == 3 || e.size == 4))
        if e.size != 4
          __else = nil
        else
          __else = __compile(e[3])
        end
        __then = __compile(e[2])
        s(:if, __compile(e[1]), __then, __else)
      elsif e.first == :set!
        compile_set e
      elsif OPERATORS.include?(e.first) && e.size == 3
        if e.first == :"="
          name = :"=="
        else
          name = e.first
        end
        return s(:send, __compile(e[1]), e.first,
          __compile(e[2]))
      elsif e.first == :send
        s(:send, __compile(e[1]), e[2], s(:args, *e[3..-1].map { |x| __compile x }))
      else # call
        name = e[0].to_s
        if ruby_ident? name
          func = parse_ruby_ident name
          args =e[1..-1].map { |x| __compile x }
          return s(:send, *(func.children + args))
        end
        func = __compile(e[0])
        if e.size == 1
          args = []
        else
          args = e[1..-1].map { |x| __compile x }
        end
        s(:send, func, :call, *args)
      end
    end

    def ruby_ident?(x)
      x.match /\.|::/
    end

    def compile_set(e)
      perror("set! expects two arguments", e.size != 3)
      name = sanitize_identifier e[1]
      perror("set! expects an identifier", !name.is_a?(Symbol))
      s(:lvasgn, name, __compile(e[2]))
    end

    def compile_lambda(e)
      perror("-> takes the form (-> (args) body)", e.size < 3)
      args = compile_args e[1]
      x=s(:block, s(:send, nil, :lambda), args, __compile([:begin, *e[2..-1]]))
      x
    end

    def literal?(x)
      x.is_a?(Numeric) or x.is_a?(String) or x.is_a?(Hash)
    end

    def compile_args(a)
      return s(:args) if a == []
      args = []
      i = 0
      rest_arg, kwarg, blarg = false,  false, false
      debug "compile_args: #{a.inspect}"
      while i<a.size
        arg = a[i]
        if arg.is_a? Array
          if arg.size == 2 && arg[0] == :keyword # kwarg
            perror("unexpected kwarg, already saw keyword splat", kwarg)
            name = arg[1]
            debug "kwarg: #{arg}"
            if literal?(a[i+1])
              args << s(:kwoptarg, name[0..-2].to_sym, compile_literal(a[i+1]))
              debug("i = #{i+= 1}")
            else
              args << s(:kwarg, name[0..-2].to_sym)
            end
            debug("i = #{i+= 1}")
          else
            perror("invalid argument #{arg}")
          end
        else
          name = arg.to_s
          debug "name: #{name}"
          name = arg.to_s
          if name.start_with?("**") #  kwarg
            perror("may only have one **arg per function", kwarg)
            perror("argument error", name.size < 3)
            args << s(:kwrestarg, name[2..-1].to_sym)
            kwarg = true
          elsif name.start_with?("*") # rest arg
            perror("may only have one *arg per function", rest_arg)
            perror("argument error", name.size < 2)
            args << s(:restarg, name[1..-1].to_s)
            rest_arg = true
          elsif name.start_with?("&") # block arg
            perror("may only have one block arg", blarg)
            perror("block arg must be last arg", i!=a.size-1)
            perror("argument error", name.size < 2)
            blarg = true
            args << s(:blockarg, name[1..-1].to_s)
          elsif literal?(a[i+1])
            debug("lit: #{a[i+1].inspect}")
            args << s(:optarg, arg, compile_literal(a[i+1]))
            debug("i = #{i+= 1}")
          else
            perror("arg must be identifier", !arg.is_a?(Symbol))
            args << s(:arg, arg)
          end
          debug("i = #{i+= 1}")
        end
      end
      s(:args, *args)
    end

    def empty_lambda(body, call: true)
      body.shift if body.first == :begin
      x = s(:block, s(:send, nil, :lambda), s(:args), s(:begin, *body))
      x = s(:send, x, :call) if call
      x
    end

    def wrap_in_fn(*body)
      to_ruby(empty_lambda(body))
    end

    def req_stdlib
      #s(:send, nil, :require, s(:str, "./stdlib.rb"))
      s(:send, nil, :require,
        s(:str, "./stdlib.rb"))
    end

    def load_stdlib
      s(:begin, req_stdlib, load_module(STDLIB))
    end

    def compile_in_fn(s, call: false)
       s= wrap_in_fn(:begin, load_stdlib, *__compile(YParser.parse_string(s)))
       s
    end

    def load_module(m, names = :all)
      methods = m.instance_methods
      unless names == :all
        methods.reject! { |x| !names.has_key?(x)}
      end
      buff = []
      methods.each do |name|
        buff << assign_method(name)
      end
      buff = s(:begin, include_mod(m), *buff)
    end

    def define_module(name, body, default = YModule.new(:Kernel, [], {}))
      add_module name
      sym = Generator.gensym
      parent = default
      # Create new module object
      mod = s(:lvasgn, sym,
              s(:send,
                s(:const, nil, :Module), :new))
      # Define module
      defm = s(:send,
            s(:const, nil, parent.name), :const_set,
              s(:sym, name),
              s(:lvar, sym))
      # Set list of exported functions
      exps = s(:casgn,
              s(:const, nil, name), :EXPORTS,
                s(:array))
      # Execute body
      body = s(:block,
              s(:send,
              s(:const, nil, name), :instance_eval),
              s(:args),
              s(:begin, *__compile([:begin, *body])))
      s(:begin, mod, defm, *body)
    end


    def include_mod(m)
      s(:send, nil, :include,
        s(:const, nil, m.name.to_sym))
    end

    def assign_method(name)
      s(:lvasgn, name,
        s(:send, nil, :method,
          s(:sym, name)))
    end

    def add_module(name)
      @modules << @module if @module
      # To Ruby methods, delegator objects ar mostly indistinguishable
      # from the objects they delegate to. But Ruby internals cares little
      # for such tricks, so in this instance, since name is assumed to be a
      # Token, we must extract the real object first.
      Kernel.const_set name.__getobj__, Module.new
      @module = YModule.new name, [], {}
      s(:nil)
    end

    def handle_mod_header(e)
      __module e.first
      if export_stmt? e[1]
        handle_exports e[1..-1]
      end
      __compile [:begin, *e[2..-1]]
    end

    def export_stmt?(s)
      s.is_a?(Array) && s.first == :export
    end

    def handle_exports(exps)
      @module.exports << exps
    end

    # This handles module headers
    def __module(e)
      perror("module requires 1 argument", e.size != 2)
      add_module e[1]

    end

    def compile_def(e)
      perror("def should be of the form (def (name args) body)", e.size < 3)
      perror("def should be of the form (def (name args) body)", !e[1].is_a?(Array))
      name = e[1].first
      args = compile_args e[1][1..-1]
      body = __compile [:begin, *e[2..-1]]
      #body = e[2..-1].map { |x| __compile x }
      fun_name = compile_literal sanitize_identifier(name, trail: false)
      res = compile_function(name: name, args: args, body: body)
      if @module
        res2 = def_module_function name: name, args: args, body: body
      else
        res2 = s(:nil)
      end
      name = sanitize_identifier name
      s(:begin, res2,
        s(:lvasgn, name, s(:block, s(:send, nil, :lambda), s(:args, *args),
          s(:begin, *body))))
    end

    def def_module_function(name:, args:, body:)
      mod = @module
      res = s(:block,
              s(:send,
              s(:const, nil, @module.name), :instance_eval),
              s(:args),
              s(:block,
                s(:send, nil, :define_method,
                s(:sym, name)),
                args,
                s(:begin, *body)))
    end

    def compile_literal(x)
      # Case statement doesn"t work for some reason with delegator objects,
      # evem when forwarding #===
      if x == :""
        s(:nop) # temporary hack
      elsif x.is_a? Integer
        s(:int, x)
      elsif x.is_a? Float
        s(:float, x)
      elsif x.is_a? String
        s(:str, x)
      elsif x.is_a? Symbol
        debug "got symbol #{x.inspect}"
        if ruby_ident? x
          parse_ruby_ident x
        else
          s(:lvar, x)
        end
      else
        if [YNil, YFalse, YTrue].include?(x)
          s(x.to_s.to_sym)
        else
          perror("unidentified literal #{x}")
        end
      end
    end

    def compile_quote(e)
      if e.size == 1
        s(:sym, e.first)
      else # TODO: handle other kinds
        e
      end
    end

    def split_pipes(x)
      buff = []
      res = []
      x.each do |item|
        if item == :|
          res << buff
          buff = []
        else
          buff << item
        end
      end
      res << buff
      res
    end

    # Handle the pipe operator |
    # A sequence like (a 1 | b 2 | c 3) should return
    # (send (send (a 1) b 2) c 3) which is equivalent to
    # a(1).b(2).c(3) in Ruby
    def compile_pipe(x)
      if x.include? :|
        x = split_pipes x
        receiver = x[0]
        receiver = receiver.first if receiver.size == 1
        name = x[1][0]
        args = x[1][1..-1]
        x = x[2..-1]
        res = [:send, receiver, name, *args]
        if x != []
          rest = []
          x.each_with_index do |i, idx|
            rest += i
            rest << :| unless idx == x.size-1
          end
          compile_pipe([res, :|, *rest])
        else
          res
        end
      else
        x
      end
    end

    # handle pipes recursively
    def compile_pipes(x)
      if x.is_a?(Array)
        compile_pipe x.map { |i| compile_pipes(i) }
      else
        x
      end
    end

    def compile_quasiquote(e)
      buffer = []
      e.each do |el|
        if el.is_a?(Array)
          if el.first == :unquote
            buffer << __compile(el[1])
          elsif el.first == :"unquote-splicing"
            buffer += __compile(el[1..-1])
          else
            buffer << [:quote, el]
          end
        else
          buffer << [:quote, el]
        end
      end
      [:array, *buffer]
    end

    def parse_ruby_ident(e)
      __parse_ruby_ident e.to_s.split /(\.|::)/
    end

    def __parse_ruby_ident(e)
      if e.first.match(/[A-Z]/)
        res = s(:const, nil, e.shift.to_sym)
      else
        res = s(:lvar, e.shift.to_sym)
      end
      until e.empty?
        op = e.shift
        if op == "."
          res = s(:send, res, e.shift.to_sym)
        else
          res = s(:const, res, e.shift.to_sym)
        end
      end
      res
    end


    def sanitize_identifier(x, trail: false)
      x = x.to_s
      if trail && %w(! ?).include?(x[-1])
        s = sanitize_identifier(x[0..-2].to_sym) + x[-1]
        return s
      end
      return :__sub__ if x == "-"
      if x.match /^\W_/
        perror("mangled identifier #{x}")
      end
      x = x.to_s.gsub("?", "_p").gsub("-", "_")
      OPERATORS.each do |key, val|
        x.gsub! key,  val
      end
      x.gsub! /[^a-z_]/, "_"
      x.to_sym
    end

    def to_ruby(x)
      Unparser.unparse x
    end
  end
end

### Testing
### Refactor or remove before release
include YLisp
C = Compiler.new

$debug = ""
def debug x
  $debug += "#{x}\n"
end

TEST = %{(begin
  (module A)
  (export f)
  (set u 1)
  (def (f x) (set u 2) (+ 1 x))
  (def (u!) (puts u))
  )}

def test
  include YLisp
  c = Compiler.new
  #RubyVM::InstructionSequence.compile_option = {tailcall_optimization: true, trace_instruction: false}
  c.compile_in_fn(TEST)
end

def test_parser
  include YLisp
  require "pp"
  begin
  pp P.new(TEST).parse
  rescue Exception => e
    msg, line, col = e.msg, e.line, e.col
  puts "parse error: #{msg} @ #{line}:#{col}"
  end
end

C=Compiler.new

def test_mod
  body = %{(begin
    (module A)
    (export a)
    (def (inc a) (+ a 1)))
  }
  c = Compiler.new
  x = c.__compile P.new(body).term
  x
end
