# frozen_string_literal: true

require "digest"
require "fileutils"
require "net/http"
require "open3"
require "tempfile"
require "uri"

module ThrowGeography
  MAXIMUM_GRID_DIAGONAL_NAUTICAL_MILES_AT_SCALE_ONE = 85.0

  class SourceError < StandardError; end

  # Resolves one pinned local file or ZIP archive from the source cache.
  class SourceArchive
    REDIRECT_LIMIT = 5

    def initialize(source_directory:, specification:, fetch: false)
      @source_directory = source_directory
      @specification = specification
      @fetch = fetch
    end

    def bytes
      path = verified_path
      return File.binread(path) unless zipped?

      member(@specification.fetch("members").fetch("shp"))
    end

    def shapefile_members
      raise SourceError, "#{identifier} is not a shapefile archive" unless zipped?

      members = @specification.fetch("members")
      [member(members.fetch("shp")), member(members.fetch("dbf"))]
    end

    def verified_path
      FileUtils.mkdir_p(@source_directory)
      path = File.join(@source_directory, file_name)
      fetch(path) if @fetch && !valid_digest?(path)
      unless File.file?(path)
        raise SourceError,
          "Missing pinned source #{file_name}. Run the generator with --fetch or copy it to #{@source_directory}."
      end

      actual = Digest::SHA256.file(path).hexdigest
      expected = @specification.fetch("sha256")
      return path if actual == expected

      raise SourceError, "Unexpected SHA-256 for #{path}: #{actual} (expected #{expected})"
    end

    private

    def file_name
      @specification.fetch("file")
    end

    def identifier
      @specification.fetch("id", file_name)
    end

    def zipped?
      @specification.key?("members")
    end

    def valid_digest?(path)
      File.file?(path) && Digest::SHA256.file(path).hexdigest == @specification.fetch("sha256")
    end

    def fetch(path)
      url = @specification.fetch("url")
      Tempfile.create(["throw-geography", ".download"], @source_directory) do |temporary|
        temporary.binmode
        download(URI(url), temporary, REDIRECT_LIMIT)
        temporary.flush
        actual = Digest::SHA256.file(temporary.path).hexdigest
        expected = @specification.fetch("sha256")
        if actual != expected
          raise SourceError,
            "Downloaded SHA-256 for #{url} was #{actual} (expected #{expected})"
        end
        temporary.close
        FileUtils.mv(temporary.path, path)
      end
      warn "Fetched #{url} -> #{path}"
    rescue SystemCallError, SocketError, Timeout::Error, URI::InvalidURIError => error
      raise SourceError, "Could not fetch #{url}: #{error.message}"
    end

    def download(uri, output, redirects_left)
      raise SourceError, "Too many redirects while fetching #{uri}" if redirects_left.negative?

      request = Net::HTTP::Get.new(uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 30,
        read_timeout: 120,
      ) do |http|
        http.request(request) do |response|
          case response
          when Net::HTTPSuccess
            response.read_body { |chunk| output.write(chunk) }
          when Net::HTTPRedirection
            location = response["location"]
            raise SourceError, "Redirect from #{uri} has no location" unless location
            output.truncate(0)
            output.rewind
            download(uri + location, output, redirects_left - 1)
          else
            raise SourceError, "Download failed for #{uri}: HTTP #{response.code}"
          end
        end
      end
    end

    def member(name)
      path = verified_path
      stdout, stderr, status = Open3.capture3("unzip", "-p", path, name, binmode: true)
      return stdout if status.success?

      detail = stderr.strip
      detail = "unzip exited #{status.exitstatus}" if detail.empty?
      raise SourceError, "Could not read #{name} from #{path}: #{detail}"
    rescue Errno::ENOENT
      raise SourceError, "The generator requires the system unzip command"
    end
  end
end
