module SourceControl
  class Mercurial < AbstractAdapter

    attr_accessor :repository

    def initialize(options = {})
      options = options.dup
      @path = options.delete(:path) || "."
      @error_log = options.delete(:error_log)
      @interactive = options.delete(:interactive)
      @repository = options.delete(:repository)
      @branch = options.delete(:branch)
      raise "don't know how to handle '#{options.keys.first}'" if options.length > 0
    end

    def checkout(revision = nil, stdout = $stdout, checkout_path = path)
      raise 'Repository location is not specified' unless @repository

      raise "#{checkout_path} is not empty, cannot clone a project into it" unless (Dir.entries(checkout_path) - ['.', '..']).empty?
      FileUtils.rm_rf(checkout_path)

      # need to read from command output, because otherwise tests break
      hg('clone', [@repository, checkout_path], :execute_in_project_directory => false) do |io|
        begin
          while line = io.gets
            stdout.puts line
          end
        rescue EOFError
        end
      end

      update_options = []
      update_options << '-C' << @branch if @branch
      update_options << '-r' << revision if revision
      hg('update', update_options) unless update_options.empty?
    end

    def latest_revision
      pull_new_changesets

      # If branch is set then honor it
      if @branch
        hg_output = hg('log', ['-v', '-l', '1', '-b', @branch])

      # otherwise just get the very latest changeset regardless of branch
      else
        hg_output = hg('log', ['-v', '-r', 'tip'])
      end

      Mercurial::LogParser.new.parse(hg_output).first
    end

    def update(revision = nil)
      pull_new_changesets

      update_local(revision)
    end

    def update_local(revision=nil)
      if @branch
        hg("update", ['-C', @branch])
      elsif revision
        hg("update", ['-r', revision.number])
      else
        hg("update")
      end
    end

    def up_to_date?(reasons = [])
      # Change to the target branch before checking for new changesets
      update_local

      _new_revisions = new_revisions
      if _new_revisions.empty?
        return true
      else
        reasons.concat(_new_revisions)
        return false
      end
    end

    def creates_ordered_build_labels?() false end

    def new_revisions
      pull_new_changesets
      hg_output = hg('parents', ['-v'])
      current_local_revision = Mercurial::LogParser.new.parse(hg_output).first
      revisions_since(current_local_revision)
    end

    def revisions_since(revision)
      log_output = hg("log", ['-v', '-r', "#{revision.number}:#{latest_revision.number}"])
      revs = LogParser.new.parse(log_output)
      revs.delete_if do |rev|
        rev.number == revision.number
      end
      revs
    end

    protected

    def pull_new_changesets
      hg("pull")
    end

    def hg(operation, arguments = [], options = {}, &block)
      command = ["hg", operation] + arguments.compact
## TODO: figure out how to handle the same thing with hg
##      command << "--non-interactive" unless @interactive
      execute_in_local_copy(command, options, &block)
    end

  end
end
