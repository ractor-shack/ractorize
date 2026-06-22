require "timeout"

RSpec.configure do |config|
  def ractors_and_ports
    ractors = []
    ports = []

    ObjectSpace.each_object do
      case it
      when Ractor
        ractors << it
      when Ractor::Port
        ports << it
      end
    end

    [ractors, ports]
  end

  def ractor_and_port_counts
    total_ractor_count = 0
    total_ractor_port_count = 0
    open_ractor_count = 0
    open_ractor_port_count = 0

    ractors, ports = ractors_and_ports

    ractors.each do
      total_ractor_count += 1
      open_ractor_count += 1 unless it.default_port.closed?
    end
    ports.each do
      total_ractor_port_count += 1
      open_ractor_port_count += 1 unless it.closed?
    end

    [total_ractor_count, open_ractor_count, total_ractor_port_count, open_ractor_port_count]
  end

  # Seems like we can't use config.around do |example| I assume because the specs memoize stuff
  # preventing garbage collection and it's still not unreferenced until example goes away
  config.before(:suite) do
    # rubocop:disable Style/GlobalVars
    $original_ractor_count,
    $original_open_ractor_count,
    $original_ractor_port_count,
    $original_open_ractor_port_count = ractor_and_port_counts
    # rubocop:enable Style/GlobalVars
  end

  config.after(:suite) do
    ractor_count,
    open_ractor_count,
    ractor_port_count,
    open_ractor_port_count = nil

    Timeout.timeout(10) do
      loop do
        ractor_count,
        open_ractor_count,
        ractor_port_count,
        open_ractor_port_count = ractor_and_port_counts

        # rubocop:disable Style/GlobalVars
        if ractor_count == $original_ractor_count &&
           ractor_port_count == $original_ractor_port_count
          break
        end
        # rubocop:enable Style/GlobalVars

        GC.start

        sleep 0.1

        1_000_000.times.map { Object.new }
      end
    end
  rescue Timeout::Error
    puts ractor_count
    puts open_ractor_count
    puts ractor_port_count
    puts open_ractor_port_count

    ractors_and_ports.flatten.each do
      puts "<#{it.object_id}> #{it.inspect}"
    end

    pp ractor_and_port_counts
    pp ractors_and_ports

    # rubocop:disable Style/GlobalVars
    leaked_ractors = ractor_count - $original_ractor_count

    raise "Leaked ractors: #{leaked_ractors}" if leaked_ractors > 0

    leaked_ports = ractor_port_count - $original_ractor_port_count

    raise "Leaked ports: #{leaked_ports}" if leaked_ports > 0
    # rubocop:enable Style/GlobalVars
  end
end
