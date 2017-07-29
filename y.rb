require "unparser"
require "parser"
require "sxp"
require "./stdlib.rb"

module YLisp
  def s(type, *children)
    Parser::AST::Node.new(type, children)
  end

  class ParseError < Exception; end
  def perror(msg, cond = true)
    if cond
      raise ParseError, msg
    end
  end

  class Compiler
    OPERATORS = {
      :+ => :op_add,
      :- => :op_sub,
      :* => :op_mul,
      :/ => :op_div,
      :% => :op_mod,
      :> => :op_gt,
      :< => :op_lt
    }

    def compile_str(s)
      compile [:begin, SXP.read(s)]
    end

    def compile(e)
      to_ruby __compile(e)
    end

    def __compile(e)
      if !e.is_a? Array
        return handle_literal e
      end
      if e == []
        return s(:array)
      end
      e = handle_pipes e
      if e.first == :begin
        s(:begin, *e[1..-1].map { |x| __compile x })
      elsif e.first == :def
        perror("def should be of the form (def (name args) body)", e.size < 3)
        perror("def should be of the form (def (name args) body)", !e[1].is_a?(Array))
        name = sanitize_identifier e[1].first
        args = handle_args e[1][1..-1]
        body = e[2..-1].map { |x| __compile x }
        s(:lvasgn, name, s(:block, s(:send, nil, :lambda), s(:args, *args), s(:begin, *body)))
      elsif e.first == :"->" or e.first == :lambda
        handle_lambda e
      elsif e.first == :"quasiquote"
        handle_quasiquote e[1..-1]
      elsif e.first == :if
        perror("if takes the form (if cond then optional-else)", !(e.size == 3 || e.size == 4))
        if e.size != 4
          __else = nil
        else
          __else = __compile(e[3])
        end
        __then = __compile(e[2])
        s(:if, __compile(e[1]), __then, __else)
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
      else
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

    def handle_lambda(e)
      perror("-> takes the form (-> (args) body)", e.size < 3)
      args = handle_args e[1]
      x=s(:block, s(:send, nil, :lambda), args, __compile([:begin, *e[2..-1]]))
      x
    end

    def literal?(x)
      x.is_a?(Numeric) or x.is_a?(String) or x.is_a?(Hash)
    end

    def handle_args(a)
      args = []
      i = 0
      rest_arg, kwarg, blarg = false,  false, false
      while i<a.size
        arg = a[i]
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
        elsif name[-1] == ":" # keyword arg
          if literal?(a[i+1])
            args << s(:kwoptarg, name[0..-2].to_sym, handle_literal(a[i+1]))
            i += 1
          else
            args << s(:kwarg, name[0..-2].to_sym)
          end
        elsif literal?(a[i+1])
          args << s(:optarg, arg, handle_literal(a[i+1]))
          i += 1
        else
          perror("arg must be identifier", !arg.is_a?(Symbol))
          args << s(:arg, arg)
        end
        i += 1
      end
      s(:args, *args)
    end

    def empty_lambda(body)
      s(:send, s(:block, s(:send, nil, :lambda), s(:args), s(:begin, body)), :call)
    end

    def wrap_in_fn(body)
      empty_lambda body
    end

    def req_stdlib
      #s(:send, nil, :require, s(:str, "./stdlib.rb"))
      Parser::Ruby23.parse(File.read("./stdlib.rb"))
    end

    def compile_in_fn(s)
      to_ruby(empty_lambda(s(:begin, req_stdlib, __compile(SXP.read(s)))))
    end

    def handle_literal(x)
      case x
      when Integer
        s(:int, x)
      when Float
        s(:float, x)
      when String
        s(:str, x)
      when Symbol
        parse_ruby_ident x
      else
        if [true, false, nil].include?(x)
          s(x.to_s.to_sym)
        else
          perror("unidentified literal #{x}")
        end
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
    def handle_pipe(x)
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
          handle_pipe([res, :|, *rest])
        else
          res
        end
      else
        x
      end
    end

    # handle pipes recursively
    def handle_pipes(x)
      if x.is_a?(Array)
        handle_pipe x.map { |i| handle_pipes(i) }
      else
        x
      end
    end

    def handle_quasiquote(e)
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


    def sanitize_identifier(x)
      x = x.to_s.gsub("?", "_p").gsub("-", "_")
      x.to_sym
    end

    def to_ruby(x)
      Unparser.unparse x
    end
  end
end

def test
  include YLisp
  c = Compiler.new
  #RubyVM::InstructionSequence.compile_option = {tailcall_optimization: true, trace_instruction: false}
  c.compile_in_fn("(begin
    (def (inc-by x) (+ x 1))
    (inc-by 1)
    ('a' | gsub 'a' 'b' | gsub 'b' ('a' | upcase))
    (if (eq? 1 1 (+ 0 (- 2 1))) (puts (+ 1 2 3)))
    (-> (a 1 *b **c d: e: 1 &d) a)
  )")
end
