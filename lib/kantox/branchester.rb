require_relative 'branchester/version'
require 'logger'
require 'git'

class << Dir
  MX = Mutex.new
  alias_method :thread_unsafe_chdir, :chdir
  def chdir other, &cb
    if block_given?
      MX.synchronize { thread_unsafe_chdir other, &cb }
    else
      thread_unsafe_chdir other, &cb
    end
  end
end

module Kantox
  module Branchester
    THREADS = 4
    PREFIX = 'bch-' # prefix for new origin

    class Error < ::StandardError ; end

    class Yo
      def initialize dir = nil
        @githome = dir || Dir.pwd
        @logger = ::Logger.new STDOUT
        @logger.level = ::Logger::INFO
        @mx = Mutex.new
        @result = []
      end

      def check threads = THREADS
        g = Git.open(@githome, :log => @logger)
        slices = (remotes = g.branches.remote).size.divmod threads
        remotes.each_slice(slices.first + (slices.last.zero? ? 0 : 1)).map do |branches|
          Thread.new do
            result = check_branches @githome,
                                    g.config['remote.origin.url'],
                                    g.lib.branch_current,
                                    branches #.map { |b| "#{b.remote.name}/#{b.name}" } # (&:full) #
            @mx.synchronize { @result << result }
          end
        end.each &:join
        @result
      end

      def check_branches local, remote, branch, branches
        branches.inject({}) do |memo, b|
          @logger.info "[#{Thread.current}] ⇒ checking branch: #{b.name}"
          temp = Dir.mktmpdir
          begin
            g = Git.clone local, 'clone', path: temp
            g.add_remote "#{PREFIX}-#{b.remote.name}", remote, fetch: true
            memo[b.name] =  begin
                              case msg = g.branches[branch].merge(g.branches["#{PREFIX}-#{b.remote.name}/#{b.name}"])
                              when /'origin\/master'/ then { success: { onmaster: msg } }
                              when /up-to-date/ then { success: { uptodate: msg } }
                              else { success: { merged: msg } }
                              end
                            rescue Git::GitExecuteError => e
                              { error: e.message.split($/)[1..-1] }
                            end
          ensure
            FileUtils.rm_rf temp
          end
          memo
        end
      end
    end

    def self.yo threads = THREADS
      result = Yo.new.check threads
      require 'pry'
      binding.pry
      File.write '/tmp/result.txt', "#{result}"
    end
  end
end
