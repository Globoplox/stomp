require "http/web_socket"
require "uuid"
require "./stomp"
require "./frames"

# todo make it works with socket and not just websockets
# todo support transaction ?????
class Stomp::Client < HTTP::WebSocket

  module Ack
    AUTO = "auto"
    CLIENT = "client"
    INDIVIDUAL = "client-individual"
  end
  
  # Todo do logger stuff
  #Log = Stomp::Log.for "client"
  @state = :disconnected

  private class Subscription
    getter callback : (Frame ->)?
    getter frame : Frame
    getter ack : String
    getter destination : String
    getter id : UUID

    def initialize(@destination, @ack, @callback, headers)
      @id = UUID.random
      @frame = Frame.new Commands::SUBSCRIBE, headers.merge({"destination" => destination, "id" => id.to_s, "ack" => ack})
    end

    def unsubscribe_frame
      Frame.new Commands::UNSUBSCRIBE, {"id" => id.to_s}
    end
  end
  
  @subscriptions = {} of UUID => Subscription
  
  getter server_version : String? = nil
  getter client_in_heartbeat = 0
  getter client_out_heartbeat = 0
  getter in_heartbeat = 0
  getter out_heartbeat = 0
  property heartbeat_tolerance = 1.2
  @last_client_beat = Time.monotonic
  @last_server_beat = Time.monotonic
  
  @on_connected: (Frame ->)? = nil
  def on_connected(&@on_connected: Frame ->) end
  @on_error: (Frame ->)? = nil
  def on_error(&@on_error: Frame ->) end

  # Start a blocking heartbeat loop
  protected def heartbeat(in in_span, out out_span)
    if in_span || out_span
      puts "Starting heartbeat"
      puts "Client must beat every #{out_span.milliseconds}" if out_span
      puts "Server must beat every #{in_span.milliseconds}" if in_span
      loop do
        sleep (out_span ? out_span : in_span).milliseconds
        beat if out_span && Time.monotonic - @last_client_beat > out_span.milliseconds
        if in_span && Time.monotonic - @last_server_beat > (in_span * @heartbeat_tolerance).milliseconds
          puts "server missed heartbeat: #{Time.monotonic - @last_server_beat} since last activity"
          close 500
        end
        break if closed?
      end
    end
  end
  
  protected def handle_frame(frame)
    case {@state, frame.command}
    when {:disconnected, Commands::ERROR}
      @on_error.try &.call frame
      close 400, frame.body
    when {_, Commands::MESSAGE}
      # ack/nack/receipt ?
      # here we ignore unexpected message, maybe we want to apply default handler, or auto nack if necessary ? 
      @subscriptions[UUID.new frame.headers["subscription"]]?.try &.callback.try &.call frame
    when {_, Commands::ERROR}
      @on_error.try &.call frame
    when {:disconnected, Commands::CONNECTED}
      @server_version = frame.headers["version"]
      server_out_heartbeat, server_in_heartbeat = frame.headers["heart-beat"].split(",").map &.to_i
      @out_heartbeat = Math.max(@client_out_heartbeat, server_in_heartbeat) unless @client_out_heartbeat == 0 || server_in_heartbeat == 0
      @in_heartbeat = Math.max(@client_in_heartbeat, server_out_heartbeat) unless @client_in_heartbeat == 0 || server_out_heartbeat == 0
      spawn heartbeat @in_heartbeat, @out_heartbeat
      @state = :connected
      @on_connected.try &.call frame
    else raise "Unexpected state/command: #{@state}, #{frame.command}"
    end
  end

  # Send a heartbeat
  protected def beat
    @last_client_beat = Time.monotonic
    send Frame::BEAT
  end

  # Send a frame
  protected def send_frame(frame : Frame)
    @last_client_beat = Time.monotonic
    puts frame.encode.lines.map { |l| "> " + l }.join "\n"
    puts "---------------"
    send(frame.encode)
  end

  # Init listeners
  protected def init
    on_close do
      @state = :closed
    end
    on_message do |message|
      @last_server_beat = Time.monotonic
      puts message.lines.map { |l| "< " + l }.join "\n"
      puts "---------------"
      handle_frame Frame.decode message unless Frame.is_beat message
    rescue error
      puts error
    end
  end
  
  def unsubscribe(sub)
    @subscriptions.delete sub.id
    send_frame sub.unsubscribe_frame
  end  
  
  def subscribe(destination, ack = Ack::AUTO, headers = {} of String => String, &handler : Frame ->)
    sub = Subscription.new destination, ack, handler, headers
    @subscriptions[sub.id] = sub
    send_frame sub.frame
    sub
  end
  
  def send(destination, body, headers = {} of String => String)
    send_frame Frame.new Commands::SEND, headers.merge({"destination" => destination}), body
  end

  def connect(
    accept_version = "1.2",
    virtual_host = nil,
    use_connect_frame = true,
    username = nil,
    password = nil,
    in_heartbeat @client_in_heartbeat = 10000,
    out_heartbeat @client_out_heartbeat = 5000,
    &@on_connected
  )
    connect(accept_version, virtual_host, use_connect_frame, username, password, in_heartbeat, out_heartbeat)
  end
  
  def connect(
    accept_version = "1.2",
    virtual_host = nil,
    use_connect_frame = true,
    username = nil,
    password = nil,
    in_heartbeat @client_in_heartbeat = 10000,
    out_heartbeat @client_out_heartbeat = 5000
  )
    init
    frame = Frame.new use_connect_frame ? Commands::CONNECT : Commands::STOMP
    frame.headers["accept-version"] = accept_version
    frame.headers["host"] = virtual_host unless virtual_host.nil?
    frame.headers["login"] = username unless username.nil?
    frame.headers["passcode"] = password unless password.nil?
    frame.headers["heart-beat"] = "#{client_out_heartbeat},#{client_in_heartbeat}"
    send_frame frame
    run
  end

end

cli = Stomp::Client.new("localhost", "/ws", 15674)
cli.on_error do |frame|
  puts "Oh no an error !"
  pp frame
end
cli.on_close do |msg|
  puts "I GOT CLOSED ?!! #{msg}"
end
cli.on_connected do
  puts "Oh I'm connected, yummy !"
  sub = cli.subscribe "/queue/foo" do |frame|
    puts "I got a message: '#{frame.body}'"
  end
  sleep 2.seconds
  cli.send "/queue/foo", "u r dumb"
  sleep 2.seconds
  cli.unsubscribe sub
  sleep 2.seconds
  cli.send "/queue/foo", "no u"
end
cli.connect username: "cc", password: "toto"
