require "open3"
require "pp"

RSpec.describe Toodeloo do
  it "has a version number" do
    expect(Toodeloo::VERSION).not_to be nil
  end

  def command(program)
    [RbConfig.ruby, '-e', program.prepend('require "bundler/setup";require "toodeloo";')]
  end

  specify "run once" do
    prog = <<~'RUBY'
      cli = Toodeloo::Cli.new(logger: nil)
      cli.run(false) do
        puts "[running once]"
      end
    RUBY

    out, pid = Open3.capture2(*command(prog))

    expect(out).to eq("[running once]\n")
    expect(pid).to be_exited
    expect(pid).to be_success
  end

  specify "#stop! loop (will stop loop execution and than kill)" do
    prog = <<~'RUBY'
      i = 0
      cli = Toodeloo::Cli.new(logger: nil)
      cli.run(true) do
        puts "[running #{i}]"
        cli.stop! if i >= 2
        i += 1
      end
    RUBY

    out, pid = Open3.capture2(*command(prog))

    expect(out).to eq <<~OUT
      [running 0]
      [running 1]
      [running 2]
    OUT
    expect(pid).to be_exited
    expect(pid).to be_success
  end

  specify "#kill loop (will keep executing the loop until handlers have finished" do
    prog = <<~'RUBY'
      i = 0
      cli = Toodeloo::Cli.new(logger: nil)
      cli.run(true) do
        puts "[running #{i}]"
        cli.kill if i >= 2
        i += 1
      end
    RUBY

    out, pid = Open3.capture2(*command(prog))

    expect(out).to start_with <<~OUT
      [running 0]
      [running 1]
      [running 2]
      [running 3]
    OUT
    expect(pid).to be_exited
    expect(pid).to be_success
  end

   specify "sending INT signal will stop the process" do
    skip "Killing process from Kernel.spawn does not work."

    prog = 'cli = Toodeloo::Cli.new; cli.run(true) { puts "[running]" }'

    r, w = IO.pipe
    pid = Kernel.spawn(*command(prog), :out => w, :err => [:child, :out])
    w.close

    Thread.new {
      sleep(0.5)
      Process.kill("INT", pid)
    }

    pid, status = Process.waitpid2(pid)
    output = r.read
    r.close

    pp pid, status , output
  end
end
