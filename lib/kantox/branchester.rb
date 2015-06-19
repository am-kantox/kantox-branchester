require 'kantox/branchester/version'
require 'logger'
require 'git'

module Kantox
  module Branchester
    THREADS = 4

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
        remotes = g.branches.remote.each_slice threads
        remotes.map do |branches|
          Thread.new do
            result = check_branches @githome, branches.dup
            @mx.synchronize { @result << result }
          end
        end.reduce &:join
        @result
      end

      def check_branches local, branches
        branches.inject({}) do |memo, b|
          Dir.mktmpdir do |temp|
            Dir.chdir temp
            g = Git.clone local
            memo[b] = g.merge b
          end
          memo
        end
      end
    end

    def self.yo threads = THREADS
      Yo.new.check threads
    end
  end
end
