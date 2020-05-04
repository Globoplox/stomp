require "./spec_helper"
include Stomp

def not_escaped_header
end

def escaped_header
end


def simple_send_frame
end

def complex_send_frame
end


def test_codec_equivalence(encoded, expected)
    decoded = Frame.decode IO::Memory.new encoded
    decoded.should eq expected
    reencoded = decoded.encode(IO::Memory.new, with_content_length: false).rewind.gets_to_end
    reencoded.should eq encoded
end

describe Stomp do

  it "encode and decode simple frame without a body" do
    encoded = <<-STOMP
      CONNECT
      accept-version:1.2

      \0
      STOMP
    expected = Frame.new Commands::CONNECT, { "accept-version" => "1.2" }
    test_codec_equivalence encoded, expected
  end
  
  it "encode and decode simple frame with a body" do
    encoded = <<-STOMP
      SEND
      accept-version:1.2
      
      hello this is patrick

      !\0
      STOMP
    expected = Frame.new Commands::SEND, { "accept-version" => "1.2" }, "hello this is patrick\n\n!"
    test_codec_equivalence encoded, expected
  end
  
  it "encode and decode a frame with a complex body" do
    encoded = <<-STOMP
      SEND
      accept-version:1.2
      content-length:52

      hello this is patrick\0 and this is after a nil byte.\0
      STOMP
    expected = Frame.new Commands::SEND,
                         { "accept-version" => "1.2", "content-length": "52" },
                         "hello this is patrick\0 and this is after a nil byte."
    test_codec_equivalence encoded, expected
  end
  
  it "do not escape headers for connect frames" do
    encoded = <<-STOMP
      CONNECT
      accept-version:1.2
      some-header:I really like doing annoying stuff\\rlike\\cthis

      \0
      STOMP
    expected = Frame.new Commands::CONNECT,
                         { "accept-version" => "1.2" ,
                           "some-header" => "I really like doing annoying stuff\\rlike\\cthis" }
    test_codec_equivalence encoded, expected
  end
  
  it "do escape headers for other frames" do
    encoded = <<-STOMP
      SEND
      accept-version:1.2
      some-header:I really like doing annoying stuff\\rlike\\cthis

      \0
      STOMP
    expected = Frame.new Commands::SEND,
                         { "accept-version" => "1.2" ,
                           "some-header" => "I really like doing annoying stuff\rlike:this" }
    test_codec_equivalence encoded, expected
  end
  
end
