module ErbSafety
  JAVASCRIPT_TAG_NAME = /\A(define\z|context\z|eval\z|track\-click\z|bind(\-|\z)|on)/mi
  ERB_RAW_INTERPOLATE = /\<\%\=\=\s*(.*?)\s*\-?\%\>/mi
  ERB_INTERPOLATE = /\<\%\=\s*(.*?)\s*\-?\%\>/mi
  ESCAPE_JAVASCRIPT_CALL = /\Aj|escape_javascript[\(\s]/mi
  HTML_SAFE_CALL = /raw[\s\(]|\.html_safe/mi
  TO_JSON_CALL = /\.to_json(\.html_safe)?\z/mi
  RAW_JSON_CALL = /\Araw\s.*\.to_json\z/mi
  TO_INT_CALL = /\.to_i\z/mi
  ERB_JAVASCRIPT_BLOCK = /\<\%\=\s*javascript_tag.*do\s*\-?\%\>/mi
  ERB_BLOCK = /\<\%(if\s.*|unless\s.*|while\s.*|when\s.*|.*do)\s*\-?\%\>/mi
  ERB_END = /\<\%\-?\s*end\s*\-?\%\>/mi

  class Token
    attr_reader :type, :data, :parts
    def initialize(type, data)
      @type = type
      @parts = [data]
    end

    def add(data)
      @parts << data
      data
    end

    def tag?
      @type == :tag
    end

    def attribute?
      @type == :attribute
    end

    def script_tag?
      @type == :tag && tag_name == "script"
    end

    def attribute(name)
      @parts.each do |part|
        return part.to_s if part.is_a?(Token) && part.attribute_name == name
      end
      nil
    end

    def erb_block?
      @type == :erb && ERB_BLOCK === @parts[0]
    end

    def erb_end?
      @type == :erb && ERB_END === @parts[0]
    end

    def script_erb?
      erb_block? && ERB_JAVASCRIPT_BLOCK === @parts[0]
    end

    def tag_name
      $1.downcase if /\<\s*([^\s\>]*)/mi =~ @parts[0]
    end

    def attribute_name
      $1.downcase if /\s*([^\s\=]*)/mi =~ @parts[0]
    end

    def javascript_attribute?
      attribute? && JAVASCRIPT_TAG_NAME === attribute_name
    end

    def erb_tag?
      @type == :erb
    end

    def erb_output?
      erb_tag? && ERB_INTERPOLATE === @parts[0]
    end

    def erb_raw_output?
      erb_tag? && ERB_RAW_INTERPOLATE === @parts[0]
    end

    def erb_code
      return unless erb_tag?
      $1 if ERB_RAW_INTERPOLATE =~ @parts[0] || ERB_INTERPOLATE =~ @parts[0]
    end

    def unsafe_erb?(safe_methods = [])
      return false unless code = erb_code

      names = Regexp.union(*safe_methods)
      return false if /\A(#{names})(\(|\s|\z)/mi === code
      return false if ESCAPE_JAVASCRIPT_CALL === code
      return false if TO_JSON_CALL === code
      return false if RAW_JSON_CALL === code
      return false if TO_INT_CALL === code

      true
    end

    def html_unsafe_calls?(unsafe_methods = [])
      return true if erb_raw_output?
      return false unless code = erb_code

      names = unsafe_methods.map{|m| Regexp.escape(m)}.join("|")
      return true if /\A(#{names})(\(|\s|\z)/mi === code
      return true if HTML_SAFE_CALL === code

      false
    end

    def inspect
      "#<#{@type} #{@parts.join.inspect}>"
    end

    def to_s
      @parts.join
    end
  end

  class Script
    attr_reader :tag, :parts
    def initialize(tag)
      @tag = tag
      @parts = []
    end

    def add(data)
      @parts << data
      data
    end

    def inspect
      "#<script #{@tag} #{@parts.join.inspect}>"
    end

    def to_s
      "#{@tag}#{@parts.join}"
    end
  end

  class Tokenizer
    attr_reader :tokens

    def initialize(data)
      @data = data
      @tokens = []
      @next = @data
      @context = :text
    end

    def last
      @tokens.last
    end

    def token
      return if @next.nil? || @next.empty?
      send("token_#{@context}")
    end

    def tokenize_part(type, match)
      t = Token.new(type, advance(match))
      @tokens << t
      t
    end

    def advance(match)
      t = @next[0..(match.size-1)]
      @next = @next[match.size..-1]
      t
    end

    def append(match)
      last.add(advance(match))
    end

    def token_text
      i = @next.index('<')
      if i.nil?
        tokenize_part(:text, @next[0..-1])
      elsif i > 0
        tokenize_part(:text, @next[0..(i-1)])
      else
        @context = :html
        token_html
      end
    end

    # document level elements
    HTML_TAG_WITHOUT_ATTRIBUTES = /\A(\<\s*(\/?\s*[a-z0-9\:]+|[a-z0-9\:]+|[a-z0-9\:]+\s*\/)\s*\>)/i
    HTML_COMMENT_TAG = /\A(\<!--.*?--\>)/mi
    HTML_TAG_START = /\A(\<(!DOCTYPE|[a-z0-9\:]+)[\s\n]*)/mi
    ERB_TAG = /\A(\<\%.*?\%\>)/mi

    def token_html
      if HTML_TAG_WITHOUT_ATTRIBUTES =~ @next
        t = tokenize_part(:tag, $1)
        if t.script_tag?
          @context = :script_tag
          @script = Script.new(@tokens.pop)
          @tokens << @script
        else
          @context = :text
        end
        t
      elsif ERB_TAG =~ @next
        t = tokenize_part(:erb, $1)
        if last.script_erb?
          @context = :script_erb
          @script = Script.new(@tokens.pop)
          @erb_stack = 1
        else
          @context = :text
        end
        t
      elsif HTML_COMMENT_TAG =~ @next
        @context = :text
        tokenize_part(:comment, $1)
      elsif HTML_TAG_START =~ @next
        @context = :attribute
        tokenize_part(:tag, $1)
      else
        raise "malformed html: #{@next[0..30].inspect}"
      end
    end

    # tag level elements
    WHITESPACES = /\A([\s\n]+)/
    HTML_ATTRIBUTE_START = /\A([a-z0-9\:\-]+\s*(\=)?)/mi
    SIMPLE_STRING = /\A(\"([^\<\"]*?)\"|\'([^\<\']*?)\')/mi
    STRING_START = /\A([\"\'])/mi
    HTML_TAG_END = /\A(\/?\s*\>)/mi

    def type_attribute(token)
      token.parts.each do |part|
        return part.to_s if part.is_a?(Token) && part.attribute_name == "type"
      end
      nil
    end

    def token_attribute
      if WHITESPACES =~ @next
        append($1)
      elsif ERB_TAG =~ @next
        append($1)
      elsif HTML_ATTRIBUTE_START =~ @next
        t = advance($1)
        @attribute = Token.new(:attribute, t)
        last.add @attribute
      elsif SIMPLE_STRING =~ @next
        t = advance($1)
        @attribute.add t
      elsif STRING_START =~ @next
        str = advance($1)
        @context = :string
        @string_start = str
        @attribute.add str
      elsif HTML_TAG_END =~ @next
        t = append($1)
        type = last.attribute('type')
        if last.script_tag? && (type.nil? || /text\/javascript|text\/template/ =~ type)
          @context = :script_tag
          @script = Script.new(@tokens.pop)
          @tokens << @script
        else
          @context = :text
        end
        t
      else
        @tokens.each { |t| puts t.inspect }
        raise "malformed html: #{@next.inspect}"
      end
    end

    SCRIPT_TAG_END = /\A(\<\s*\/\s*script[^\>]*\>)/mi
    SCRIPT_TEXT = /\A([^\<]+)/mi
    LESS_THAN = /\A(\<)/mi

    def token_script_tag
      if SCRIPT_TAG_END =~ @next
        @context = :text
        @script.add advance($1)
      elsif ERB_TAG =~ @next
        t = Token.new(:erb, advance($1))
        @script.add t
        t
      elsif SCRIPT_TEXT =~ @next
        @script.add advance($1)
      elsif LESS_THAN =~ @next
        @script.add advance($1)
      else
        raise "malformed html: #{@next.inspect}"
      end
    end

    def token_script_erb
      if ERB_TAG =~ @next
        t = Token.new(:erb, advance($1))
        @script.add t
        if t.erb_block?
          @erb_stack += 1
        elsif t.erb_end?
          @erb_stack -= 1
          if @erb_stack == 0
            @tokens << @script
            @context = :text
          end
        end
        t
      elsif SCRIPT_TEXT =~ @next
        @script.add advance($1)
      elsif LESS_THAN =~ @next
        @script.add advance($1)
      else
        raise "malformed html: #{@next.inspect}"
      end
    end

    def token_string
      t_STRING_END = /\A(#{@string_start})/mi
      t_ESCAPED_STRING_END = /\A(\\#{@string_start})/mi
      t_NON_SPECIAL_CHARS = /\A([^\<\\#{@string_start}]*)/mi

      if t_STRING_END =~ @next
        @context = :attribute
        @attribute.add advance($1)
      elsif ERB_TAG =~ @next
        t = Token.new(:erb, advance($1))
        @attribute.add t
      elsif t_ESCAPED_STRING_END =~ @next
        @attribute.add advance($1)
      elsif LESS_THAN =~ @next
        @attribute.add advance($1)
      elsif t_NON_SPECIAL_CHARS =~ @next
        @attribute.add advance($1)
      else
        raise "malformed html: #{@next.inspect}"
      end
    end
  end
end

