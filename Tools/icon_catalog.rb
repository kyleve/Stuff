# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

require_relative "file_transaction"

# Plans and transactionally commits Where alternate-icon catalog mutations.
class IconCatalog
  class Error < StandardError; end

  PRIMARY_SET = "AppIcon"
  PRIMARY_ID = "classic"

  def initialize(root:, app_catalog:, preview_catalog:, manifest:, transaction_factory:)
    @root = File.expand_path(root)
    @app_catalog = File.expand_path(app_catalog, @root)
    @preview_catalog = File.expand_path(preview_catalog, @root)
    @manifest = File.expand_path(manifest, @root)
    @transaction_factory = transaction_factory
  end

  def list(output: $stdout)
    icons = load_manifest.fetch("icons")
    if icons.empty?
      output.puts "(no icons in the manifest)"
      return
    end

    id_width = icons.map { |icon| icon.fetch("id").length }.max
    name_width = icons.map { |icon| icon.fetch("displayName").length }.max
    icons.each do |icon|
      alternate = icon["alternateIconName"] || "(primary)"
      output.printf("  %-#{id_width}s  %-#{name_width}s  %s\n", icon.fetch("id"), icon.fetch("displayName"), alternate)
    end
  end

  def add(light:, name:, id:, dark:, tinted:, dry_run:)
    light = resolve_input(light)
    dark = resolve_optional_input(dark)
    tinted = resolve_optional_input(tinted)
    name = name.empty? ? pascal_case(File.basename(light, File.extname(light))) : name
    raise Error, "couldn't derive a name; pass --name" if name.empty?

    id = id.empty? ? slug(name) : id
    raise Error, "couldn't derive an id; pass --id" if id.empty?

    set_name = PRIMARY_SET + pascal_case(name)
    if set_name == PRIMARY_SET || id == PRIMARY_ID
      raise Error, %("#{PRIMARY_ID}" / "#{PRIMARY_SET}" is the reserved primary icon)
    end

    [light, dark, tinted].compact.each { |path| require_1024(path) }
    data = load_manifest
    icons = data.fetch("icons")
    raise Error, %(an icon with id "#{id}" already exists (use --id to pick another)) if icons.any? { |icon| icon.fetch("id") == id }
    if icons.any? { |icon| icon["alternateIconName"] == set_name }
      raise Error, %(an icon named "#{set_name}" already exists)
    end

    app_target = File.join(@app_catalog, "#{set_name}.appiconset")
    preview_target = File.join(@preview_catalog, "#{set_name}.imageset")
    [app_target, preview_target].each do |path|
      raise Error, "#{relative(path)} already exists" if File.exist?(path) || File.symlink?(path)
    end

    data["icons"] = icons + [{
      "id" => id,
      "displayName" => name,
      "alternateIconName" => set_name,
      "previewImageName" => set_name,
    }]
    validate_manifest(data)

    Dir.mktmpdir(".icons-stage-", @root) do |stage|
      staged_app = File.join(stage, "#{set_name}.appiconset")
      staged_preview = File.join(stage, "#{set_name}.imageset")
      staged_manifest = File.join(stage, "AppIcons.json")
      stage_app_icon(staged_app, set_name: set_name, light: light, dark: dark, tinted: tinted)
      stage_preview(staged_preview, set_name: set_name, light: light, dark: dark)
      write_json(staged_manifest, data)
      validate_staged_add(staged_app, staged_preview, staged_manifest, set_name)

      unless dry_run
        transaction = @transaction_factory.call
        transaction.replace(target: app_target, staged: staged_app)
        transaction.replace(target: preview_target, staged: staged_preview)
        transaction.replace(target: @manifest, staged: staged_manifest)
        transaction.commit
      end
    end

    verb = dry_run ? "Would add" : "Added"
    %(#{verb} "#{name}" (id: #{id}, asset: #{set_name}).)
  end

  def remove(target:, dry_run:)
    raise Error, %(the primary "Classic" icon can't be removed) if [PRIMARY_ID, PRIMARY_SET.downcase].include?(target.downcase)

    data = load_manifest
    icons = data.fetch("icons")
    match = icons.find do |icon|
      values = [icon.fetch("id"), icon.fetch("displayName"), icon["alternateIconName"]].compact
      values.any? { |value| value.downcase == target.downcase }
    end
    raise Error, %(no icon matching "#{target}" (try ./icons --list)) unless match
    raise Error, %(the primary "Classic" icon can't be removed) unless match["alternateIconName"]

    set_name = match.fetch("alternateIconName")
    data["icons"] = icons.reject { |icon| icon.equal?(match) }
    validate_manifest(data)
    app_target = File.join(@app_catalog, "#{set_name}.appiconset")
    preview_target = File.join(@preview_catalog, "#{set_name}.imageset")

    Dir.mktmpdir(".icons-stage-", @root) do |stage|
      staged_manifest = File.join(stage, "AppIcons.json")
      write_json(staged_manifest, data)
      validate_manifest(JSON.parse(File.read(staged_manifest)))

      unless dry_run
        transaction = @transaction_factory.call
        transaction.remove(target: app_target)
        transaction.remove(target: preview_target)
        transaction.replace(target: @manifest, staged: staged_manifest)
        transaction.commit
      end
    end

    verb = dry_run ? "Would remove" : "Removed"
    %(#{verb} "#{match.fetch('displayName')}" (id: #{match.fetch('id')}).)
  end

  private

  def require_layout
    missing = [@manifest, @app_catalog, @preview_catalog].reject { |path| File.exist?(path) }
    raise Error, "couldn't find #{missing.map { |path| relative(path) }.join(', ')} — run ./icons from the repo root" if missing.any?
  end

  def load_manifest
    require_layout
    data = JSON.parse(File.read(@manifest))
    validate_manifest(data)
    data
  rescue JSON::ParserError => error
    raise Error, "#{relative(@manifest)} is not valid JSON: #{error.message}"
  end

  def validate_manifest(data)
    raise Error, "#{relative(@manifest)} must contain an icons array" unless data.is_a?(Hash) && data["icons"].is_a?(Array)

    ids = []
    alternates = []
    data.fetch("icons").each_with_index do |icon, index|
      raise Error, "icon #{index + 1} must be an object" unless icon.is_a?(Hash)
      %w[id displayName previewImageName].each do |key|
        raise Error, "icon #{index + 1} has no #{key}" unless icon[key].is_a?(String) && !icon[key].empty?
      end
      alternate = icon["alternateIconName"]
      raise Error, "icon #{index + 1} has an invalid alternateIconName" unless alternate.nil? || (alternate.is_a?(String) && !alternate.empty?)
      ids << icon.fetch("id")
      alternates << alternate if alternate
    end
    raise Error, "manifest contains duplicate icon ids" unless ids.uniq.length == ids.length
    raise Error, "manifest contains duplicate alternate icon names" unless alternates.uniq.length == alternates.length
  end

  def stage_app_icon(directory, set_name:, light:, dark:, tinted:)
    FileUtils.mkdir_p(directory)
    images = [{ "filename" => "#{set_name}.png", "idiom" => "universal", "platform" => "ios", "size" => "1024x1024" }]
    copy(light, directory, "#{set_name}.png")
    if dark
      images << appearance_image("#{set_name}-Dark.png", "dark", platform: true)
      copy(dark, directory, "#{set_name}-Dark.png")
    end
    if tinted
      images << appearance_image("#{set_name}-Tinted.png", "tinted", platform: true)
      copy(tinted, directory, "#{set_name}-Tinted.png")
    end
    write_json(File.join(directory, "Contents.json"), "images" => images, "info" => xcode_info)
  end

  def stage_preview(directory, set_name:, light:, dark:)
    FileUtils.mkdir_p(directory)
    images = [{ "filename" => "#{set_name}.png", "idiom" => "universal" }]
    copy(light, directory, "#{set_name}.png")
    if dark
      images << appearance_image("#{set_name}-Dark.png", "dark", platform: false)
      copy(dark, directory, "#{set_name}-Dark.png")
    end
    write_json(File.join(directory, "Contents.json"), "images" => images, "info" => xcode_info)
  end

  def appearance_image(filename, value, platform:)
    image = {
      "appearances" => [{ "appearance" => "luminosity", "value" => value }],
      "filename" => filename,
      "idiom" => "universal",
    }
    image["platform"] = "ios" if platform
    image["size"] = "1024x1024" if platform
    image
  end

  def validate_staged_add(app, preview, manifest, set_name)
    app_contents = JSON.parse(File.read(File.join(app, "Contents.json")))
    preview_contents = JSON.parse(File.read(File.join(preview, "Contents.json")))
    [app_contents, preview_contents].each do |contents|
      contents.fetch("images").each do |image|
        path = File.join(contents.equal?(app_contents) ? app : preview, image.fetch("filename"))
        raise Error, "staged catalog is missing #{File.basename(path)}" unless File.file?(path)
      end
    end
    staged_data = JSON.parse(File.read(manifest))
    validate_manifest(staged_data)
    unless staged_data.fetch("icons").any? { |icon| icon["alternateIconName"] == set_name }
      raise Error, "staged manifest does not include #{set_name}"
    end
  rescue JSON::ParserError, KeyError => error
    raise Error, "staged icon output is invalid: #{error.message}"
  end

  def require_1024(path)
    raise Error, "no such file: #{relative(path)}" unless File.file?(path)

    header = File.binread(path, 24)
    raise Error, "not a PNG: #{relative(path)}" unless header.start_with?("\x89PNG\r\n\x1A\n".b)

    width, height = header.byteslice(16, 8).unpack("NN")
    raise Error, "#{relative(path)} is #{width}x#{height}; app icons must be 1024x1024" unless [width, height] == [1024, 1024]
  rescue EOFError
    raise Error, "not a PNG: #{relative(path)}"
  end

  def resolve_input(path)
    File.expand_path(path, @root)
  end

  def resolve_optional_input(path)
    path.empty? ? nil : resolve_input(path)
  end

  def copy(source, directory, filename)
    FileUtils.copy_file(source, File.join(directory, filename))
  end

  def write_json(path, data)
    output = JSON.pretty_generate(
      data,
      indent: "  ",
      space: " ",
      space_before: " ",
      object_nl: "\n",
      array_nl: "\n",
    )
    File.write(path, "#{output}\n")
  end

  def xcode_info
    { "author" => "xcode", "version" => 1 }
  end

  def pascal_case(text)
    text.split(/[^A-Za-z0-9]+/).reject(&:empty?).map { |part| part[0].upcase + part[1..] }.join
  end

  def slug(text)
    text.downcase.gsub(/[^a-z0-9]+/, "")
  end

  def relative(path)
    path.delete_prefix("#{@root}/")
  end
end

def icon_catalog_main
  catalog = IconCatalog.new(
    root: ENV.fetch("ROOT"),
    app_catalog: ENV.fetch("APP_CATALOG"),
    preview_catalog: ENV.fetch("PREVIEW_CATALOG"),
    manifest: ENV.fetch("MANIFEST"),
    transaction_factory: -> { FileTransaction.new },
  )
  dry_run = ENV.fetch("DRY_RUN") == "true"
  case ENV.fetch("MODE")
  when "list"
    catalog.list
  when "add"
    puts catalog.add(
      light: ENV.fetch("LIGHT"),
      name: ENV.fetch("NAME"),
      id: ENV.fetch("ID"),
      dark: ENV.fetch("DARK"),
      tinted: ENV.fetch("TINTED"),
      dry_run: dry_run,
    )
    puts dry_run ? "Dry run — nothing was changed." : "Run `./ide --no-open` to regenerate so the new icon is compiled in."
  when "remove"
    puts catalog.remove(target: ENV.fetch("TARGET"), dry_run: dry_run)
    unless dry_run
      puts "If it was the active icon, the app falls back to Classic on next launch."
      puts "Run `./ide --no-open` to regenerate."
    end
    puts "Dry run — nothing was changed." if dry_run
  else
    raise IconCatalog::Error, "unknown mode: #{ENV.fetch('MODE')}"
  end
  0
rescue IconCatalog::Error, FileTransaction::CleanupError, SystemCallError => error
  warn "error: #{error.message}"
  1
end

exit(icon_catalog_main) if __FILE__ == $PROGRAM_NAME
