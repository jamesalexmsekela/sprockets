require "digest/sha1"
require "rack/utils"
require "set"
require "tilt"

module Sprockets
  class ConcatenatedAsset
    attr_reader :environment, :content_type, :format_extension
    attr_reader :mtime, :length

    def initialize(environment, pathname)
      @environment      = environment
      @content_type     = pathname.content_type
      @format_extension = pathname.format_extension
      @source_paths     = Set.new
      @source           = []
      @mtime            = Time.at(0)
      @length           = 0
      @digest           = Digest::SHA1.new
      require(pathname)
    end

    def digest
      @digest.hexdigest
    end

    def each(&block)
      @source.each(&block)
    end

    def stale?
      @source_paths.any? { |p| mtime < File.mtime(p) }
    end

    def to_s
      @source.join
    end

    protected
      attr_reader :source_paths, :source

      def <<(str)
        @length += str.length
        @digest << str
        @source << str
      end

      def requirable?(pathname)
        content_type == pathname.content_type
      end

      def require(pathname)
        if requirable?(pathname)
          unless source_paths.include?(pathname.path)
            source_paths << pathname.path
            self << process(pathname)
          end
        else
          raise ContentTypeMismatch, "#{pathname.path} is " +
            "'#{pathname.format_extension}', not '#{format_extension}'"
        end
      end

      def process(pathname)
        result = process_source(pathname)
        pathname.engine_extensions.reverse_each do |extension|
          result = Tilt[extension].new(pathname.path) { result }.render
        end
        result
      end

      def process_source(pathname)
        source_file = SourceFile.new(pathname)
        processor   = Processor.new(environment, source_file)
        result      = ""

        if source_file.mtime > mtime
          @mtime = source_file.mtime
        end

        processor.required_pathnames.each { |p| require(p) }
        result << source_file.header << "\n" unless source_file.header.empty?
        processor.included_pathnames.each { |p| result << process(p) }
        result << source_file.body

        # LEGACY
        if processor.compat? && (constants = processor.constants).any?
          result.gsub!(/<%=(.*?)%>/) { constants[$1.strip] }
        end

        result
      end
  end
end
