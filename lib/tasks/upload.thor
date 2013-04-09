# require defined gems
Bundler.require(:default)

# require lib classes
require File.expand_path("../../compressor.rb", __FILE__)

class Upload < Thor
  class_option :threads, :aliases => '-t', :default => Parallel.processor_count, :desc => 'Number of threads to use for processing'
  class_option :compress, :aliases => '-c', :banner => Compressor.compression_types.map(&:to_s), :desc => 'Compress files before sending'
  class_option :map, :aliases => '-m', :banner => true, :desc => 'Queue files for mapping after uploading'

  desc "auto URL PATH", "Upload files using auto-detection based on MIME-type"

  def auto(url, path)
    files = resolve_files(path)
    url = compose_url(url)

    # detect file mime-types
    mime = FileMagic.fm(:mime_type, :compress)

    files.each do |file_name|
      # guess the file type based on MIME type
      type = mime.file(file_name)
      case type
        when 'application/marc'
          marc(url, path)
        else
          puts "==== Uncertain MIME type '#{type}' for file: #{file_name}"
      end
    end
  end

  desc "marc URL PATH", "Upload MARC files"

  def marc(url, path)
    files = resolve_files(path)
    url = compose_url(url)

    files.each do |file_name|
      puts "==== Processing MARC file: #{file_name}"

      # TODO: may wish to include encoding options
      records = MARC::ForgivingReader.new(file_name, :invalid => :replace)

      Parallel.each(records, :in_threads => options[:threads]) do |marc_record|
        # POST to Ladder as MARCHASH
        json = marc_record.to_marchash.to_json

        response = RestClient.post url, json, :content_type => 'application/marc+json'

        puts "#{response.code} : #{response.body}"
      end
    end
  end

  desc "marcxml URL PATH", "Upload MARCXML files"
  method_option :map
  def marcxml(url, path)
    files = resolve_files(path)
    url = compose_url(url)

    files.each do |file_name|
      puts "==== Processing MARCXML file: #{file_name}"

      records = MARC::XMLReader.new(file_name, :parser => :nokogiri)

      Parallel.each(records, :in_threads => options[:threads]) do |marc_record|
        # POST to Ladder as MARCHASH
        json = marc_record.to_marchash.to_json

        response = RestClient.post url, json, :content_type => 'application/marc+json'

        puts "#{response.code} : #{response.body}"
      end
    end
  end

  desc "marchash URL PATH", "Upload MARCHASH (JSON) files"

  def marchash(url, path)
    files = resolve_files(path)
    url = compose_url(url)

    files.each do |file_name|
      puts "==== Processing MARCHASH (JSON) file: #{file_name}"

      response = RestClient.post url, File.read(file_name), :content_type => 'application/marc+json'

      puts "#{response.code} : #{response.body}"
    end
  end

  desc "modsxml URL PATH", "Upload MODSXML files"

  def modsxml(url, path)
    files = resolve_files(path)
    url = compose_url(url)

    files.each do |file_name|
      puts "==== Processing MODSXML file: #{file_name}"

      # parse XML into records using XPath
      records = Nokogiri::XML(File.read(file_name)).remove_namespaces!.xpath('//mods') # TODO: smarter namespace handling

      Parallel.each(records, :in_threads => options[:threads]) do |mods_record|
        # POST to Ladder as MODSXML
        response = RestClient.post url, mods_record.to_xml, :content_type => 'application/mods+xml'

        puts "#{response.code} : #{response.body}"
      end
    end
  end

  private

  # take an argument and return a cleansed array of files
  def resolve_files(path)
    path = File.expand_path(path, __FILE__)

    if File::directory? path
      files = Dir.entries(path).reject! {|s| s =~ /^\./}  # don't include dotfiles
      files.map! {|file| File.join(path, file)}
      files = files.sort_by {|filename| File.size(File.expand_path(filename, path)) }
    else
      files = [path]
    end

    files.reject! {|file| File::directory? file}

    files
  end

  # ensure that a string matches proper HTTP/HTTPS syntax
  def validate_url(string)
    schemes = ['http', 'https']
    match = string.match(URI.regexp(schemes))
    return (0 == match.begin(0) and string.size == match.end(0)) if match
    false
  end

  # format a URL for POSTing
  def compose_url(url)
    abort "Invalid URL: #{url}" unless validate_url(url)

    uri = URI(url)
    uri.path = '/files'
    uri.query = URI.encode_www_form('map' => 'true') if options['map']
    uri.to_s
  end
end
