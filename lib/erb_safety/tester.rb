module ErbSafety

  class Error
    def initialize(token, erb, message)
      @token = token
      @erb = erb
      @message = message
    end

    def to_s
      <<-EOF
Found: #{@message}
  #{@token}
The unsafe interpolation is:
  #{@erb.parts.join.inspect}
EOF
  end

  class Tester

    def initialize(filename, options={})
      @filename = filename
      @javascript_safe_helpers = options.delete(:javascript_safe_helpers) || []
      @html_safe_helpers = options.delete(:html_safe_helpers) || []
      @errors = nil
    end

    def javascript_tag?(token)
      type = token.attribute('type')
      type.nil? || /text\/javascript/ =~ type
    end

    def data
      @data ||= File.read(@filename)
    end

    def tokenizer
      @tokenizer ||= begin
        t = Tokenizer.new(data)
        while token = t.token; end
        t
      end
    end

    def tokens
      @tokens ||= tokenizer.tokens
    end

    def errors
      return @errors unless @errors.nil?

      @errors = []

      tokens.each do |token|
        if (token.is_a?(Script) && javascript_tag?(token.tag)) || (token.is_a?(Token) && token.script_tag? && javascript_tag?(token))
          token.parts.each do |erb|
            next unless erb.is_a?(Token) && erb.unsafe_erb?(@html_safe_helpers)
            @errors << Error.new(token, erb, "unsafe ERB tag inside javascript tag")
          end
        else
          token.parts.each do |part|
            next unless part.is_a?(Token)
            part.parts.each do |erb|
              next unless erb.is_a?(Token)
              if part.javascript_attribute? && erb.unsafe_erb?(@safe_javascript_helpers)
                @errors << Error.new(token, erb, "unsafe ERB tag inside html attribute")
              elsif erb.html_unsafe_calls?(html_safe_helpers)
                @errors << Error.new(token, erb, "unsafe use of html_safe inside html attribute")
              end
            end
          end
        end

        @errors
      end
    end
  end
end
