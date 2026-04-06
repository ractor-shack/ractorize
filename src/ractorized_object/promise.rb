class RactorizedObject < Ractor
  class Promise
    attr_accessor :port_or_ractor

    def initialize(port_or_ractor)
      self.port_or_ractor = port_or_ractor
    end

    def value
      if port_or_ractor.is_a?(Ractor)
        port_or_ractor.value
      else
        puts "ractor is #{Ractor.current} #{Ractor.current.object_id}"
        port_or_ractor.receive
      end
    end
  end
end
