# STOMP is a small text push/sub protocol.
# This lib intend to provide utilities to sustains my need for its and that's all.

module Stomp

  enum Commands
    CONNECT
    STOMP
    SEND
    SUBSCRIBE
    UNSUBSCRIBE
    BEGIN
    COMMIT
    ABORT
    ACK
    NACK
    DISCONNECT
    MESSAGE
    RECEIPT
    CONNECTED
    ERROR
  end

  # Represent a frame 
  class Frame

    BEAT = "\n"
    
    def self.is_beat(src)
      src == "\n" || src == "\r\n"
    end
    
    NOT_ESCAPED_FRAMES = [Commands::CONNECT, Commands::CONNECTED]
    property command : Commands
    property headers : Hash(String, String)
    property body : String

    def ==(other)
      other.command == @command && other.headers == @headers && other.body == @body 
    end

    def initialize(@command, @headers = {} of String => String, @body = "")
    end
    
    # TODO
    def self.escape_header(src)
      src.gsub(/(\r|\n|:|\\)/, {"\r": "\\r", "\n": "\\n", ":": "\\c", "\\": "\\\\"})
    end

    def encode(with_return = false, with_content_length = true): String
      encode(IO::Memory.new, with_return, with_content_length).rewind.gets_to_end
    end
    
    def encode(output : IO, with_return = false, with_content_length = true): IO
      @headers["content-length"] = body.size.to_s if with_content_length 
      eol = with_return ? "\r\n" : "\n"
      output << @command.to_s
      output << eol
      @headers.each do |name, value|
        output << name
        output << ':'
        if NOT_ESCAPED_FRAMES.includes? @command
          output << value
        else
          output << Frame.escape_header value
        end
        output << eol
      end
      output << eol
      output << @body
      output << '\0'
      output
    end

    def self.decode(io : IO): Frame
      Decoder.new(io).decode.check.frame
    end

    def self.decode(s : String): Frame
      Decoder.new(IO::Memory.new s).decode.check.frame
    end

    private class Decoder

      @state = :command
      @command = ""
      @header = ""
      @value = ""
      @body = ""
      @headers = {} of String => String
      @index = 0
      @must_escape_header = true
      
      def initialize(@src : IO) end

      class ParseError < Exception
        getter byte
        getter state
        def initialize(@char : Char, @state : Symbol, @index : Int32)
          super "Unexpected byte #{@char.bytes} '#{@char}' during parsing of #{@state} at position #{@index}"
        end
      end

      def error(char)
        raise ParseError.new(char, @state, @index) 
      end

      def begin_header_or_body
        @state = :header_or_body
        @must_escape_header = !(Frame::NOT_ESCAPED_FRAMES.map &.to_s).includes? @command
      end

      def header_name(char)
        @state = :header_name
        @header += char
      end

      def end_header(next_state)
        @state = next_state
        # When a header is repeated, only first value must be kept.
        @headers[@header] = @value unless @headers.has_key? @header
        @header = ""
        @value = ""
      end

      def check
        if @body.includes? '\0'
          raise "Missing 'content-length' header. Body contain \\0, therefore it must include a 'content-length' header." unless @headers.has_key? "content-length"  
          raise "Header 'content-length' value is incorrect: found #{@headers["content-length"]}, expected #{@body.size}." if @headers["content-length"] != @body.size.to_s
        end
        self
      end
      
      def continue_header(char)
        @value += char
        @state = :header_value
      end

       def frame
         Frame.new Commands.parse(@command), @headers, @body
       end
      
      def decode : Decoder
        @src.each_char do |char|
          case @state
          when :command
            case
            when ('A'..'Z').includes? char then @command += char
            when char == '\r' then @state = :eol_then_header_or_body
            when char == '\n' then begin_header_or_body
            else error char
            end  
          when :eol_then_header_or_body
            case char
            when '\n' then begin_header_or_body
            else error char
            end
          when :header_or_body
            case
            when ('a'..'z').includes? char then header_name char
            when ('A'..'Z').includes? char then header_name char
            when char == '-' then header_name char
            when char == '\r' then @state = :eol_then_body 
            when char == '\n' then @state = :body 
            else error char
            end  
          when :eol_then_body
            case char
            when '\n' then @state = :body
            else error char
            end
          when :header_name
            case
            when ('a'..'z').includes? char then @header += char
            when ('A'..'Z').includes? char then @header += char
            when char == '-' then @header += char
            when char == ':' then @state = :header_value
            else error char
            end  
          when :header_value
            case
            when char == '\\' && @must_escape_header then @state = :header_value_escape
            when !char.control? then @value += char
            when char == '\r' then end_header :eol_then_header_or_body
            when char == '\n' then end_header :header_or_body
            else error char
            end
          when :header_value_escape
            case char
            when 'r' then continue_header '\r'
            when 'n' then continue_header '\n'
            when 'c' then continue_header ':'
            when '\\' then continue_header '\\'
            else error char
            end
          when :body
            case char
            when '\0' then @state = :body_or_null
            else @body += char
            end
          when :body_or_null
            case char
            when '\n' then @state = :body_or_eof
            else
              @body += '\0'              
              @body += char
              @state = :body
            end
          when :body_or_eof
            case char
            when '\0' then
              @body += "\0\n"
              @state = :body_or_null
            else @body += char; @state = :body
            end
          else raise "Unexpected decoder state: #{@state}."
          end
          @index += 1
        end
        raise "Unexpected end of file: expected body or EOF sequence '\\0\\n'. State at end of input is '#{@state}'" if @state != :body_or_eof && @state != :body_or_null
        self
      end
    end    
  end
end
