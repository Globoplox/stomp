require "./spec_helper"
include Stomp

def simple_connect_frame
<<-STOMP
CONNECT
accept-version:1.2

\0
STOMP
end

describe Stomp do
  it "decode simple frame without a body" do
    Frame.decode(IO::Memory.new simple_connect_frame).should eq(Frame.new Commands::CONNECT, { "accept-version" => "1.2" }, "")
  end
end
