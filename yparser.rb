module YLisp
  module YParser
    require "bigdecimal"
    require "delegate"

    # Tokens are delegator objects. They are virtually indistinguishable from,
    # and can in almost any circumstance be treated as, plain Ruby objects:
    # a Fixnum Token is, for all intents and purposes, a Fixnum. The only
    # distintinction is that Tokens have access to the file, line and col
    # attributes, as well as the __getobj__ and __setobj__(v) methods for
    # extracting or changing the underlying object being delegated to.
    class Token < SimpleDelegator
      %i[is_a? instance_of? class ==].each { |m| undef_method m }
      def initialize(obj, file, line, col)
        super obj
        @file, @line, @col = file, line, col
      end
      attr_accessor :file, :line, :col
    end

    # Helper functions to make it more convenient to create Tokens
    # This one creates an array token
    def A(file, line, col, *rest)
      Token.new rest, file, line, col
    end

    # And this creates a regular token
    def T(file, line, col, obj)
      Token.new obj, file, line, col
    end

    class ParseError < RuntimeError
      def initialize(file, line, col, msg)
        @file, @line, @col, @msg = file, line, col, msg
      end
      attr_reader :file, :line, :col, :msg
    end

    class ParseError2
      def initialize(file, line, col, msg)
        @file, @line, @col, @msg = file, line, col, msg
      end
      def exception
        ParseError.new @file, @line, @col, @msg
      end
    end

    class NoMatch < ParseError2; end


    class YParser
      include YLisp::YParser
      Literals = {true: true, false: false, nil: nil}

      # Initialize a YParser with a string, an optional file name, and an
      # optional list of literal symbols to translate into Ruby values. By
      # default, the list of literals is YParser::Literals, i.e., the standard
      # ruby names for the booleans and nil.
      def initialize(str, file: "(main)", literals: Literals)
        @str = str
        @i = 0
        @file = file
        @line = 1
        @col = 1
        @literals = literals
      end

      # Ruby provides these really convenient methods that will parse and verify
      # numeric strings for you, and convert them to the correct type or raise
      # an exception if the string fails to conform to that number type's
      # (Ruby literal) syntax. Using them saves us a lot of work *and* allows us
      # to be fully compatible with Ruby's numeric literals. For example, all of
      # these are valid Ruby number literals:
      # 1_000_000 # => Fixnum
      # .1 => Used to work, now deprecated in Ruby but we will support it
      # 1.1+2i => Complex
      # 1/23 => This must be written as Rational(1,23) but is correctlty parsed
      # 2**65 => Bignum
      # 2.1**1289 => Infinity
      # Ruby supports auto-upgrading from Fixnum to Bignum on overflow for Integers,
      # but not for floating-point numbers. We do however have access to the BigDecimal
      # library, which does exactly that, allowing us to support BigDecimal literals
      # as well.
      # BigDecimal("2.1**1289") =>  #<BigDecimal:3208740,'0.21E1',18(18)>
      # YLisp also supports these literal types
      # .1 # => 0.1
      # 2^-1 # => Rational(1,2)
      #
      # If x is not a valid numeric literal, number? will return nil. Otherwise,
      # it will return a native Ruby Numeric type of the correct value.
      def number?(x)
        return false unless /\d+/ =~ x
        # the .0 syntax was deprecated but still works with the Float() function
        x = "0"+x if x[0] == "."
        # We will also support exponentiation in literals
        if x.include? "^"
          num, exp = x.split "^"
          x, y = __number(num), __number(exp)
          return x**y if x && y
        else
          __number x
        end
      end

      def __number(x)
        %i[Integer Float Rational Complex].each do |numeric|
          begin
            value = method(numeric).call( x )
            return BigDecimal(x) if value == Float::INFINITY
            return value
          rescue ArgumentError
          end
        end
        nil
      end

      def peek
        @str[@i]
      end

      def eat
        chr = @str[@i]
        @i += 1
        if chr == "\n"
          @line += 1
          @col = 1
        else
          @col += 1
        end
        chr
      end

      def uneat
        chr = peek
        if chr == "\n"
          @line -= 1
          @col = 1
        else
          @col -= 1
        end
        @i -= 1
      end

      def eof?
        @i >= @str.size
      end

      def ws?
        !eof? && "\t\r\n ".include?(peek)
      end

      def comment?
        peek == ";"
      end

      def eat_ws
        until eof? || !ws?
          eat
        end
      end

      def eat_comment
        return if peek != ";"
        until eof? || peek == "\n"
          eat
        end
      end

      def eat_ws_and_comments
        while ws? || comment?
          eat_comment
          eat_ws
        end
      end

      # Recognize special characters
      def special?
        "([{}])';".include? peek
      end

      def save
        [@file, @line, @col]
      end

      # This naive term reader will only gobble up consecutive characters of
      # any kind until it either meets end of file, a special character, or
      # whitespace. Later, we will decide what to do with it.
      def naive_term
        eat_ws_and_comments
        file, line, col = save
        buffer = ""
        until eof? || special? || ws?
          buffer += eat
        end
        handle_naive_term buffer, file, line, col
      end

      def error(file, line, col, msg, condition)
        raise(::ParseError2.new(file, line, col, msg)) if condition
      end

      # Now we decide what to do with this undistinguished blob of chars.
      def handle_naive_term(term, file, line, col)
        # First check to see if it's a number
        value = number? term
        return Token.new value, file, line, col if value
        # Ok, so it must be a symbol, a keyword, a literal or an identifier.
        if @literals.has_key?(s=term.to_sym) # special keyword
          T(file, line, col, @literals[s])
        elsif term[0] == ":" # Symbol
          error file, line, col, ": is not a valid symbol", term.size == 1
          A(file, line, col, :quote, term[1..-1].to_sym)
        elsif term[-1] == ":" # Keyword
          A(file, line, col, :keyword, term.to_sym)
        else # identifier
          T(file, line, col, term.to_sym)
        end
      end

      # This method parses a generic collection given a set of delimiters,
      # and then hands off the result to a block for processing.
      def generic_collection(starter:, ender:, name:, &proc)
        eat_ws_and_comments
        file, line, col = save
        if peek == starter
          eat
          buffer = []
          loop do
            eat_ws_and_comments
            error file, line, col, "unclosed #{name}, expected #{ender}", eof?
            if peek == ender
              eat
              break
            end
            buffer << term
          end
        else
          return nil
        end
        T(file, line, col, proc.call(A(file, line, col, *buffer)))
      end

      # This is the basic method which consumes one Lisp term, recursively.
      def term
        eat_ws_and_comments
        if peek == "'" # quoted
          return quote_term
        elsif peek == "`" # quasiquote
          return quasi_term
        elsif peek == ","
          return unquote_term
        elsif str = string_term
          return str
        end
        # We begin by trying the various collections
        [:list_term, :array_term, :hash_term].each do |coll|
          coll = method coll
          value = coll.call
          return value unless value.nil?
        end
        # Then it must be a basic term
        naive_term
      end

      def quasi_term
        eat
        [:quasiquote, term]
      end

      def unquote_term
        eat
        error *save, "unexpected eof, expected unquoted term", eof?
        if peek == "@"
          eat
          error *save, "unexpected eof, expected unquote-splicing", eof?
          [:unquote_splicing, term]
        else
          [:unquote, term]
        end
      end

      def string_term
        if peek == "\"" # string
          saved = save
          eat
          buffer = ""
          loop do
            error(*save, "unexpected end of file, expected \"", eof?)
            char = peek
            if char == "\\"
              buffer += handle_escape
            elsif char == "\""
              eat
              break
            else
              buffer += eat
            end
          end
          T(*saved, buffer)
        else
          return nil
        end
      end

      def quote_term
        eat
        saved = save
        t = term
        A(*saved, :quote, t)
      end

      def handle_escape
        eat
        error(*save, "unexpected eof, expected escaped character", eof?)
        value = case (char = peek)
        when "t"
          "\t"
        when "n"
          "\n"
        when "r"
          "\r"
        else
          char
        end
        eat
        value
      end

      def list_term
        generic_collection(starter: "(", ender: ")", name: "list") do |list|
          list
        end
      end

      def array_term
        generic_collection(starter: "[", ender: "]", name: "array") do |list|
          [:array] + list
        end
      end

      def hash_term
        generic_collection(starter: "{", ender: "}", name: "hash") do |list|
          # Keywords are allowed in here, so we must process them correctly
          # First make sure we actually have a valid hash. An alternative would
          # be to fill unmatched keys with nils, but we're not doing that by design.
          # A Lisp hash has the form {a: 1 :b 2 c 3} etc
          error(list.file, list.line, list.col,
                "Hash must have even number of elements", list.size.odd?)
          i = 0
          size = list.size
          buffer = []
          while i < size
            key = list[i]
            if k = keyword?(key)
              buffer << k
            else
              buffer << key
            end
            buffer << list[i+1]
            i += 2
          end
          list.__setobj__ Hash[*buffer]
          list
        end
      end


      # Keywords and symbols are treated equally in hash literals. That means that
      # {:a 1} and {a: 1} should both produce the Ruby Hash {:a => 1}
      def keyword?(key)
        if key.is_a?(Array) && key.size == 2
          if key.first == :quote # symbol
            if key[1].is_a? Symbol
              return key[1]
            else
              return nil
            end
          elsif key.first == :keyword
            return key[1].to_s[0..-2].to_sym
          end
        else
          nil
        end
      end

      # This method will continually parse Lisp terms until the end of
      # the string is reached. The terms will be returned as a list,
      # which by default begins with the "begin" keyword, as in Scheme,
      # allowing us to parse a file without wrapping everything in a
      # (begin ....) statement.
      def parse(buffer = :begin)
        buffer = [buffer]
        saved = save
        eat_ws_and_comments
        until eof?
          t = term
          break if t == :""
          buffer += [t]
        end
        buffer = flatten_begin buffer
        A(*saved, *buffer)
      end

      def flatten_begin(e)
        return e unless e.is_a?(Array)
        if e[0] == :begin && e[1].is_a?(Array) && e[1][0] == :begin
          flatten_begin e[1]
        else
          e
        end
      end

    end

    def test
      test_parse "1"
      test_parse "{a: 1 :b 2 3 4}"
      test_parse "(a [1 2 3 b])"
    end

    def test_parse(s)
      puts "Parsing: #{s}"
      puts "=> #{YParser.new(s).term}"
    end

    module_function

    # Parse a sequence of Lisp terms and return them wrapped in an array
    # of the form [:begin, term1, term2, ...]
    #
    # The resulting Array and each of its elements will actually be instances
    # of the YLisp::YParser::Token class. This is a delegator class, which means
    # that the objects respond in every practical sense as if they were ordinary
    # Ruby objects... Arrays, Fixnums, Symbols, etc., but they also provide the
    # following handy methods: Token#file gives the filename the token originates from,
    # Token#line and Token#col give the starting line and column numbers for that
    # token.
    #
    # Examples:
    #
    #   include YLisp
    #   YParser.parse_string "1 1 1" # => [:begin, 1, 1, 1]
    #   YParser.parse_string "(set! hash {a: 1 b: (+ 1 1)})"
    #   # => [:begin, [:set!, :hash, {:a=>1, :b=>[:+, 1, 1]}]]
    #
    #   x = YLisp::YParser.parse_string "[{a: 2} 1]", file: "my_file"
    #   # => [:begin, [:array, {:a=>2}, 1]]
    #   puts x[1][2].col # => 9
    #   puts x[1][2].file # => "my_file"
    #
    #   p = YParser.new "'(a b c)"
    #   puts p.term # => [:quote, [:a, :b, :c]]
    #   puts YParser.new("'a").term # => [:quote, :a]
    #
    #   YLisp::YParser.parse_string "(define a \"a\\n\")"
    #   # => [:begin, [:define, :a, "a\n"]]
    #
    #   YLisp::YParser.parse_string "[:a a]"
    #   # => [:begin, [:array, [:quote, :a], :a]]
    #
    #   x = YLisp::YParser.parse_string("1")[1]
    #   puts x+1 # => 2
    #
    #   # This is a lie. x is not actually a Fixnum but a Token, but you can
    #   # treat it exactly like a Fixnum in any practical scenario.
    #   puts x.is_a? Fixnum # => true
    #
    #   The YParser currently supports Symbols, Arrays, Hashes, Strings,
    #   identifiers, keywords, and quoted terms. TODO: quasiquote stuff.
    def parse_string(s, file: "string")
      YLisp::YParser::YParser.new(s, file: file).parse
    end

    def parse_term(s, file: "string")
      YLisp::YParser::YParser.new(s, file: file).term
    end

    YNil = parse_term "nil"
    YTrue = parse_term "true"
    YFalse = parse_term "false"

  end
end
