require_relative "../y.rb"
require_relative "../yparser.rb"
require "irb"
require "pp"
require_relative "../preprocessor"

include YLisp
include Preprocessor
C = Compiler.new
P = YParser::YParser

$debug = ""
def debug x
  $debug += "#{x}\n"
end

TEST = %{
  (module Adder)
  (export get inc)
  (set! counter 0)
  (def (inc by:) (set! counter (+ counter by)))
  (def (get) counter)
  }

def test
  include YLisp
  c = Compiler.new
  #RubyVM::InstructionSequence.compile_option = {tailcall_optimization: true, trace_instruction: false}
  c.compile_in_fn(TEST)
end

def parse(s)
  pp $par = P.new(s).parse
end

def pre(s)
  pp $pre = process(parse(s))
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

def comp(s)
  puts $comp = Compiler.new.compile_in_fn(s)
end

def test_mod
  body = %{
    (module A)
    (export get inc)
    (set! i 0)
    (def (inc by:) (set! i (+ i by)))
    (def (get) i)
  }
  comp body
end

def test_greet
  body = %{
    (def (greeter my-name)
      (Kernel.print "What's your name? ")
      (set! name (STDIN.readline))
      (if (eq? my-name (at-range name 0 -2))
        (puts (join "Hey, my name is " name " too!"))
        (puts (join "Hi, " name ", mine is " my-name "."))))
    (greeter "Simen")
  }
  comp body
end

p = YParser::YParser
puts "Compiling: #{TEST}"
val = test
puts val
puts "Evaluating result..."
eval val

# Setup irb
IRB.setup nil
IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
require 'irb/ext/multi-irb'
IRB.irb nil, self
