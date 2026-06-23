require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

[true, false].each do |use_shmactor|
  task_type = use_shmactor ? "shmactor" : "ractor"

  desc "Run the test suite using #{task_type}s"
  task "spec:#{task_type}" do
    unless system "SHMACTOR=#{use_shmactor} bundle exec rspec"
      exit $?.exitstatus
    end
  end
end

desc "Collate coverage from all test suite runs"
task "spec:collate_coverage" do
  require "simplecov"

  SimpleCov.root __dir__

  resultsets = Dir["coverage/*/.resultset.json"]

  puts
  SimpleCov.collate resultsets do
    enable_coverage :branch
    minimum_coverage line: 100, branch: 100
  end
  puts
end

task default: "suite:all:parallel"

spec_tasks = ["spec:ractor", "spec:shmactor"]

depends_on_spec_tasks = ["spec:collate_coverage"]
non_spec_tasks = [:rubocop]

task "suite:all:parallel" do
  require "pty"

  class ParallelSuiteTaskRunner
    class << self
      def run!(spec_tasks:, depends_on_spec_tasks:, non_spec_tasks:)
        command = new(spec_tasks:, depends_on_spec_tasks:, non_spec_tasks:)
        command.run!
      end
    end

    attr_accessor :stdio_mutex, :failed_mutex,
                  :writing_threads, :task_threads, :spec_task_threads,
                  :spec_tasks, :depends_on_spec_tasks, :non_spec_tasks,
                  :exit_code

    def initialize(spec_tasks:, depends_on_spec_tasks:, non_spec_tasks:)
      self.stdio_mutex = Thread::Mutex.new
      self.failed_mutex = Thread::Mutex.new

      self.writing_threads = []
      self.task_threads = []
      self.spec_task_threads = []

      self.exit_code = 0

      self.spec_tasks = spec_tasks
      self.depends_on_spec_tasks = depends_on_spec_tasks
      self.non_spec_tasks = non_spec_tasks
    end

    def run!
      self.spec_task_threads += run_tasks(spec_tasks)
      run_tasks(non_spec_tasks, kill_if_fails: false)

      spec_task_threads.each(&:join)

      run_tasks(depends_on_spec_tasks)

      task_threads.each(&:join)
      writing_threads.each(&:join)

      unless exit_code.zero?
        exit exit_code
      end
    end

    def run_tasks(tasks, kill_if_fails: true)
      tasks.map do |task|
        run_task("bundle exec rake #{task}", kill_if_fails:)
      end
    end

    def run_task(task, kill_if_fails: true)
      task_thread = Thread.new do
        PTY.spawn(task) do |stdouterr, stdin, pid|
          stdin.close

          writing_thread = write_async(stdouterr, task:)
          exit_status = Process::Status.wait(pid)

          unless exit_status.success?
            failed_mutex.synchronize do
              self.exit_code = exit_status.exitstatus

              if kill_if_fails
                (writing_threads - [writing_thread]).each(&:kill)
                (task_threads - [Thread.current, task_thread]).each(&:kill)

                writing_thread.join

                exit exit_code
              end

              stdio_mutex.synchronize do
                info = begin
                  "\n#{stdouterr.read}"
                rescue IOError
                  ""
                end
                puts "Could not #{task}\n#{info}"
              end
            end
          end

          writing_thread.join
        end
      end

      task_threads << task_thread

      task_thread
    end

    def write_async(io_out, task:)
      writing_thread = Thread.new do
        stdio_mutex.synchronize do
          loop do
            ch = io_out.getc
            break unless ch

            putc ch
          end
        rescue IOError, Errno::EIO
          io_out.close
        end
      end

      writing_threads << writing_thread

      writing_thread
    end
  end

  ParallelSuiteTaskRunner.run!(spec_tasks:, depends_on_spec_tasks:, non_spec_tasks:)
end
