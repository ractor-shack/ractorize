require "timeout"

RSpec.configure do |config|
  def ractor_and_port_counts
    total_ractor_count = 0
    total_ractor_port_count = 0
    open_ractor_count = 0
    open_ractor_port_count = 0

    ObjectSpace.each_object do
      case it
      when Ractor
        total_ractor_count += 1
        open_ractor_count += 1 unless it.default_port.closed?
      when Ractor::Port
        total_ractor_port_count += 1
        open_ractor_port_count += 1 unless it.closed?
      end
    end

    [total_ractor_count, open_ractor_count, total_ractor_port_count, open_ractor_port_count]
  end

  # Seems like we can't use config.around do |example| I assume because the specs memoize stuff
  # preventing garbage collection and it's still not unreferenced until example goes away
  config.before(:suite) do
    $original_ractor_count,
    $original_open_ractor_count,
    $original_ractor_port_count,
    $original_open_ractor_port_count = ractor_and_port_counts
  end

  config.after(:suite) do
    ractor_count,
    open_ractor_count,
    ractor_port_count,
    open_ractor_port_count = nil

    Timeout.timeout(3) do
      loop do
        ractor_count,
        open_ractor_count,
        ractor_port_count,
        open_ractor_port_count = ractor_and_port_counts

        if ractor_count == $original_ractor_count &&
           ractor_port_count == $original_ractor_port_count
          break
        end

        GC.start
      end
    end
  rescue Timeout::Error
    puts ractor_count
    puts open_ractor_count
    puts ractor_port_count
    puts open_ractor_port_count

    leaked_ractors = ractor_count - $original_ractor_count

    # raise "Leaked ractors: #{leaked_ractors}" if leaked_ractors > 0

    leaked_ports = ractor_port_count - $original_ractor_port_count

    # raise "Leaked ports: #{leaked_ports}" if leaked_ports > 0

    puts leaked_ractors
    puts leaked_ports
  end
end
