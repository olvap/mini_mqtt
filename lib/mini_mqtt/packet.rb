class InvalidFlagsError < StandardError ; end

module MiniMqtt
  class Packet
    include BinHelper

    @@last_packet_id = 0

    def decode stream, flags = 0
      @stream = stream
      handle_flags flags
      read_variable_header
      read_payload
      self
    end

    def encode
      build_variable_header + build_payload
    end

    def flags
      0b000
    end

    private

      def new_packet_id
        @@last_packet_id += 1
        @@last_packet_id %= 65535
        1 + @@last_packet_id
      end

      def read_variable_header
      end

      def read_payload
      end

      def handle_flags flags
      end

      def build_variable_header
        ""
      end

      def build_payload
        ""
      end

  end

  module AckPacket
    attr_accessor :packet_id

    def initialize params = {}
      @packet_id = params[:packet_id]
    end

    def read_variable_header
      @packet_id = read_ushort @stream
    end

    def build_variable_header
      ushort @packet_id
    end
  end

  class ConnackPacket < Packet
    attr_reader :return_code

    ERRORS = { 1 => "unacceptable protocol version",
               2 => "identifier rejected",
               3 => "server unavailable",
               4 => "bad username or password",
               5 => "not authorized" }


    def read_variable_header
      @session_present = @stream.readbyte & 0x01
      @return_code = @stream.readbyte
    end

    def session_present?
      @session_present == 1
    end

    def accepted?
      @return_code == 0
    end

    def error_message
      ERRORS[@return_code]
    end

  end

  class PublishPacket < Packet
    attr_accessor :dup, :qos, :retain, :packet_id, :topic, :message

    def handle_flags flags
      @dup = flags & 0b1000 != 0
      @qos = (flags & 0b0110) >> 1
      @retain = flags & 0b0001 != 0
    end

    def read_variable_header
      @topic = read_mqtt_encoded_string @stream
      if @qos > 0
        @packet_id = read_ushort @stream
      end
    end

    def read_payload
      @message = @stream.read
    end

    def initialize params = {}
      @topic = params[:topic] || ""
      @message = params[:message] || ""
      @qos = params[:qos] || 0
      @dup = params[:dup] || false
      @retain = params[:retain] || false
      @packet_id = params[:packet_id]
    end

    def flags
      flags = 0
      flags |= 0b0001 if @retain
      flags |= qos << 1
      flags |= 0b1000 if @dup
      flags
    end

    def build_variable_header
      header = mqtt_utf8_encode @topic
      if @qos > 0
        @packet_id ||= new_packet_id
        header << ushort(@packet_id)
      end
      header
    end

    def build_payload
      @message
    end

  end

  class PubackPacket < Packet
    include AckPacket
  end

  class PubrecPacket < Packet
    include AckPacket
  end

  class PubrelPacket < Packet
    include AckPacket

    def flags
      0b0010
    end
  end

  class PubcompPacket < Packet
    include AckPacket
  end

  class SubscribePacket < Packet
    attr_accessor :packet_id, :topics

    def initialize params = {}
      @topics = params[:topics]
    end

    def flags
      0b0010
    end

    def build_variable_header
      @packet_id ||= new_packet_id
      ushort @packet_id
    end

    def build_payload
      @topics.map do |topic, qos|
        mqtt_utf8_encode(topic) + uchar(qos)
      end.join
    end
  end

  class SubackPacket < Packet
    attr_accessor :packet_id, :max_qos_accepted

    def read_variable_header
      @packet_id = read_ushort @stream
    end

    def read_payload
      @max_qos_accepted = @stream.read.unpack 'C*'
    end
  end

  class UnsubscribePacket < Packet
    attr_accessor :packet_id, :topics

    def flags
      0b0010
    end

    def initialize params = {}
      @topics = params[:topics]
    end

    def build_variable_header
      @packet_id ||= new_packet_id
      ushort @packet_id
    end

    def build_payload
      @topics.map do |topic|
        mqtt_utf8_encode(topic)
      end.join
    end
  end

  class UnsubackPacket < Packet
    include AckPacket
  end

  class PingreqPacket < Packet
  end

  class PingrespPacket < Packet
  end

  class DisconnectPacket < Packet
  end
end
