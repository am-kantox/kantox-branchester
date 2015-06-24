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
    DEFAULT_LOG_COUNT = 1_000
    DEFAULT_BRANCH_AGE = 30
    HEAD = 'head'
    ORIGIN = 'origin'
    REMOTES = 'remotes'
    TAGS = 'tags'
    PREFIX = 'bch-' # prefix for new origin

    class Error < ::StandardError ; end

    class Yo
      include ::Kungfuig

      attr_reader :git_config, :branches, :current

      def initialize dir = nil
        @githome = dir || Dir.pwd
        (@logger = ::Logger.new STDOUT).level = ::Logger::WARN
        @mx = Mutex.new
        @now = Time.now

        @logger.info "Preparing config and log..."
        @cfg_file, @log_file = prepare_files
        config @cfg_file

        @git_config = Hashie::Mash.new(
          retro: options.config!.retro || DEFAULT_LOG_COUNT,
          age: options.config!.age || DEFAULT_BRANCH_AGE,
          keep: options.config!.keep || []
        )

        @data = []
        @current = nil
        @remote = nil
        @branches = nil
      end

      # thread unsafe
      def init
        g = Git.open(@githome, :log => @logger)
        @current = g.lib.branch_current
        @remote = g.remote
        remotes = g.branches.remote.map(&:name).map { |b| [b, nil] }.to_h # full list

        # FIXME clone ⇒ fetch ⇒ deal ??? Could it be a case that we don’t have all branches here?
        # remote_prefix = "#{PREFIX}-remote"
        # g.add_remote remote_prefix, remote, fetch: true

        # FIXME at least g.fetch ??

        branches = Git::Log.new(g, @git_config.retro).inject(remotes) do |memo, gl|
          b = branch?(desc = g.describe(gl.sha, contains: true, all: true))
          memo[b.name] ||= {
            data: b,
            desc: desc,
            last: gl.sha,
            date: gl.date,
            committer: gl.committer,
            info: g.lib.show(gl.sha),
            age: ((@now - gl.date) / (60*60*24)).floor + 1
          }
          # FIXME we probably can break here, if commits are sorted by date. Are they?
          break memo unless memo.values.any? &:nil?
          memo
        end.reject do |name, info|
          (!@git_config.keep.include?(name) &&  # not defined to keep explicitly
          (
            info.nil? ||                        # HEAD -> origin/master
            info[:age].nil? ||                  # older than last @git_config.retro commits
            info[:age] > @git_config.age        # older than max age as by @git_config.age
          )).tap do |tf|
            @logger.warn (tf ? "- REJECTED #{name} branch (#{info && info[:age]})" : "* SELECTED #{name} branch")
          end
        end
      end
      private :init

      def check threads = THREADS
        unless @branches
          @logger.warn "Gathering all repo info [go have a ristretto]..."
          @branches = init
        end

        unless @branches.size.zero?
          slices = @branches.size.divmod threads
          puts "\n\e[01mWill try to merge \e[01;38;05;68m#{@branches.size}\e[0m\e[01m branches:\e[0m"
          puts "=" * @branches.size
          @branches.each_slice(slices.first + (slices.last.zero? ? 0 : 1)).map do |branches|
            Thread.new do
              result = check_bulk @githome,
                                  @current,
                                  branches
              @mx.synchronize { @data << result }
            end
          end.each &:join
          puts
          puts "=" * @branches.size
          @data = @data.reduce(&:merge)

          File.write @log_file, @data.to_yaml
          File.write @cfg_file, options.to_yaml
        else
          @logger.warn "Everything is up-to-date. Too lazy check settings?"
        end

        [@data, self]
      end

      def check_bulk local, current, branches
        # `(name, b)` below are:
        #     "superclass-for-kantox-errors"=> {
        #         :data=>{"name"=>"superclass-for-kantox-errors", "full"=>"remotes/origin/superclass-for-kantox-errors", "revision"=>nil, "remote"=>true, "tag"=>false},
        #         :desc=>"remotes/origin/superclass-for-kantox-errors",
        #         :last=>"c11af7c71cad3e090407d40bfdcffce00a8e2adc",
        #         :date=>2015-06-10 08:51:59 +0200,
        #         :committer=>#<Git::Author:0x0000000385fa68 @date=2015-06-10 08:51:59 +0200, @email="aleksei.matiushkin@gmail.com", @name="Aleksei Matiushkin">,
        #         :info=> "LONG_STRING_GARBAGE"
        #         :age=>14.087258708528935}
        #     }
        branches.inject({}) do |memo, (name, b)|
          temp = Dir.mktmpdir
          begin
            remote_prefix = "#{PREFIX}-#{@remote.name}"
            g = Git.clone local, 'branchester', path: temp
            g.add_remote remote_prefix, @remote.url, fetch: true # FIXME FUCK HOW NOT TO FETCH EVERYTHING?? merge ⇒ revert/stash/rebase --abort ???

            memo[name] =  { branch: b }.merge begin
                                                case msg = g.branches[@current].merge(g.branches["#{remote_prefix}/#{name}"])
                                                when /'origin\/master'/ then { status: :success, reason: :onmaster, message: msg }
                                                when /up-to-date/ then { status: :success, reason: :uptodate, message: msg }
                                                else { status: :success, reason: :merged, message: msg }
                                                end
                                              rescue Git::GitExecuteError => e
                                                { status: :error, message: e.message.split($/)[1..-1] }
                                              end
            print '*'
          ensure
            FileUtils.rm_rf temp
          end
          memo
        end
      end
      private :check_bulk

      # Prepares config and log directories / files.
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

      # Returns extended branch naming
      def branch? id, use_origin = ORIGIN
        id, revision = id.split('~', 2)
        type, origin, name =  case id
                              when /\A#{REMOTES}\//
                                id.split('/', 3)
                              when /\A#{TAGS}\//
                                [nil, id.split('/', 2)]
                              else [false, '', id]
                              end
        Hashie::Mash.new(
          name: name || HEAD,
          full: "#{REMOTES}/#{use_origin}/#{name}",
          revision: revision,
          remote: type.is_a?(String),
          tag: type.nil?
        )
      end

      private :prepare_files, :branch?
    end

    def self.yo threads = THREADS
      Yo.new.check(threads).tap do |res, yo|
        fails = res.select { |_, v| v[:status] == :error }
        status = fails.empty? ? "Everything merged successfully" : "Some branches failed to merge automatically"
        puts "\n\e[01m#{status} into #{yo.current}\e[0m\n\n"
        fails.each do |k, v|
          puts "#{k} ==>\n\t"
          puts v[:message].strip.join("\n\t").gsub(/(CONFLICT)(.*?)(\S+)$/, "\e[01;38;05;196m\\1\e[0m\\2\e[01;38;05;68m\\3\e[0m")
          puts
        end
      end
    end
  end
end
