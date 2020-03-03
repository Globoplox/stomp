# TODO: Write documentation for `Stomp`
module Stomp
  VERSION = "0.1.0"

  # TODO: Put your code here

  enum Commands
    CONNECT
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

  class Frame
    property command : Commands
    property headers : Hash(String, String)
    property body : String

    def ==(other)
      other.command == @command && other.headers == @headers && other.body == @body 
    end

    def initialize(@command, @headers = {} of String => String, @body = "")
    end

    def self.escape_header(src)
    end
    
    def encode(output : IO, with_return = false, with_content_length = true): IO
      @headers["content-length"] = body.length if with_content_length 
      eol = with_return ? "\r\n" : "\n"
      output << @commend.to_s
      output << eol
      @headers.each do |name, value|
        output << name
        output << ':'
        output << Frame.escape_heaer value
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

    private class Decoder

      @state = :command
      @command = ""
      @header = ""
      @value = ""
      @body = ""
      @headers = {} of String => String
      @index = 0
      
      def initialize(@src : IO) end

      class ParseError < Exception
        getter byte
        getter state
        def initialize(@char : Char, @state : Symbol, @index : Int32)
          super "Unexpected byte #{@char.bytes} during parsing of #{@state} at position #{@index}"
        end
      end

      def error(char)
        raise ParseError.new(char, @state, @index) 
      end

      def begin_header_or_body
        @state = :header_or_body
        @header = ""
        @value = ""
      end

      def header_name(char)
        @state = :header_name
        @header += char
      end

      def end_header(next_state)
        @state = next_state
        # When a header is repeated, only first value must be kept.
        @headers[@header] = unescape_header @value unless @headers.has_key? @header
      end

      def check
        if @body.includes? '\0'
          raise "Missing 'content-length' header. Body contain \\0, therefore it must include a 'content-length' header." unless @headers.has_key? "content-length"  
          raise "Header 'content-length' value is incorrect: found #{@headers["content-length"]}, expected #{@body.size}." unless @headers["content-length"] != @body.size.to_s
        end
        self
      end

      # TODO
      def unescape_header(src)
        src
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
            when !char.control? then @value += char
            when char == '\r' then end_header :eol_then_header_or_body
            when char == '\n' then end_header :header_or_body
            else error char
            end  
          when :body
            case char
            when '\0' then @state = :body_or_eof
            else @body += char
            end
          when :body_or_eof
            @body += '\0'
            case char
            when '\0' then @state = :body_or_eof
            else @body += char; @state = :body_or_eof
            end
          else raise "Unexpected decoder state: #{@state}."
          end
          @index += 1
        end
        raise "Unexpected end of file: expected body or EOF character." if @state != :body_or_eof
        self
      end
    end    
  end
end
