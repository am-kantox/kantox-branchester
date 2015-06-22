require_relative 'branchester/version'
require 'logger'
require 'kungfuig'
require 'fileutils'
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
    DEFAULT_BRANCH_AGE = 7
    PREFIX = 'bch-' # prefix for new origin

    class Error < ::StandardError ; end

    class Yo
      include ::Kungfuig

      def initialize dir = nil
        @githome = dir || Dir.pwd
        @logger = ::Logger.new STDOUT
        @logger.level = ::Logger::WARN
        @mx = Mutex.new
        @result = []
        @cfg_file, @log_file = prepare_files

        config @cfg_file
      end

      def check threads = THREADS
        g = Git.open(@githome, :log => @logger)
        remotes = g.branches.remote
        if options.config!.skip.is_a?(Array) && !options.config!.skip.empty?
          rejected = remotes.select { |b| options.config!.skip.include? b.name }
          rejected_as_string = rejected.join("\n\t")
          puts "Will not proceed following branches:\n\t#{rejected_as_string}"
          remotes -= rejected
          puts "Total branches to proceed: #{remotes.size}:\n"
        end

        unless remotes.size.zero?
          slices = remotes.size.divmod threads
          remotes.each_slice(slices.first + (slices.last.zero? ? 0 : 1)).map do |branches|
            Thread.new do
              result = check_branches @githome,
                                      g.config['remote.origin.url'],
                                      g.lib.branch_current,
                                      branches #.map { |b| "#{b.remote.name}/#{b.name}" } # (&:full) #
              @mx.synchronize { @result << result }
            end
          end.each &:join
          @result = @result.reduce(&:merge)

          File.write @log_file, @result.to_yaml
          File.write @cfg_file, options.to_yaml
        else
          @logger.warn "Everything is up-to-date. Too lazy check settings?"
        end

        [ @result, @options ]
      end

      def check_branches local, remote, branch, branches
        branches.inject({}) do |memo, b|
          temp = Dir.mktmpdir
          begin
            g = Git.clone local, 'clone', path: temp
            g.add_remote "#{PREFIX}-#{b.remote.name}", remote, fetch: true
            case branch_state b.name, g.log.to_a.first
            when :obsolete
              @logger.info "[#{Thread.current}] ⇒ skipping branch: #{b.name} ⇒ :obsolete (age: #{options.branches[b.name].age} days)"
              print '-' if @logger.level > Logger::INFO
              (options.config!.skip ||= []) << b.name
              next memo
            when :boi
              @logger.info "[#{Thread.current}] ⇒ processing branch: #{b.name}"
              print '*' if @logger.level > Logger::INFO
            else raise 'Lame programmer error'
            end
            memo[b.name] =  begin
                              case msg = g.branches[branch].merge(g.branches["#{PREFIX}-#{b.remote.name}/#{b.name}"])
                              when /'origin\/master'/ then { success: { branch: b, onmaster: msg } }
                              when /up-to-date/ then { success: { branch: b, uptodate: msg } }
                              else { success: { branch: b, merged: msg } }
                              end
                            rescue Git::GitExecuteError => e
                              { branch: b, error: e.message.split($/)[1..-1] }
                            end
          ensure
            FileUtils.rm_rf temp
          end
          memo
        end
      end

      def prepare_files
        cfgdir = File.join @githome, 'config'
        Dir.mkdir(cfgdir) unless File.exist?(cfgdir)
        cfg_file = File.directory?(cfgdir) ?
          File.join(cfgdir, 'branchester.yml') :
          @logger.warn("Can not store configuration, because “#{cfgdir}” is not a directory.")
        FileUtils.touch(cfg_file)

        logdir = File.join @githome, 'branchester'
        Dir.mkdir(logdir) unless File.exist?(logdir)
        log_file = File.directory?(logdir) ?
          File.join(logdir, "#{Time.now.strftime('%Y-%m-%d--%H-%M')}.bch") :
          @logger.warn("Can not store log, because “#{logdir}” is not a directory.")

        [cfg_file, log_file]
      end

      def branch_state branch, logstamp
        options.branches ||= Hashie::Mash.new
        options.branches[branch] = Hashie::Mash.new(
          checked: Time.now,
          modified: logstamp.committer.date,
          blame: logstamp.committer.email,
          message: logstamp.message,
          sha: logstamp.sha
        ).merge(age: (options.branches[branch].checked - options.branches[branch].modified).round / (60*60*24) )

        if options.branches[branch].age > (options.config!.age || DEFAULT_BRANCH_AGE)
          :obsolete
        else
          :boi
        end
      end
      private :prepare_files, :branch_state
    end

    def self.yo threads = THREADS
      Yo.new.check(threads).tap do |res, opt|
        puts "\n\n\e[01mSome branches failed to merge automatically:\e[0m\n"
        puts res.select { |_, v| v[:error] }.map { |(k, v)| [k, v[:error].join("\n\t")].join("\n\t") }.join("\n\n").gsub(/(CONFLICT)(.*?)(\S+)$/, "\e[01;38;05;196m\\1\e[0m\\2\e[01;38;05;68m\\3\e[0m")
      end
    end
  end
end
