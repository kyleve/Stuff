# frozen_string_literal: true

require "cgi"
require "set"

# Local-link syntax used by repository guidance: inline and reference links,
# ATX/setext headings, and explicit HTML anchors. No network or rendering.
class AgentMarkdown
  Link = Struct.new(:target, :line, keyword_init: true)

  def initialize(text)
    @prose = without_examples(text)
  end

  def links
    prose = @prose.gsub(/(`+)(?!`)(.*?)\1(?!`)/m) { |code| code.gsub(/[^\n]/, " ") }
    definitions = {}
    prose = prose.gsub(/^ {0,3}\[([^\]]+)\]:[ \t]*(<[^>]*>|\S+).*$/) do |definition|
      definitions[normalize(Regexp.last_match(1))] = Regexp.last_match(2).delete_prefix("<").delete_suffix(">")
      " " * definition.length
    end
    result = []
    pattern = /(?<!!)(?:!)?\[((?:\\.|[^\[\]]|\[[^\]]*\])*)\]/m
    offset = 0
    while (match = pattern.match(prose, offset))
      label = match[1]
      finish = match.end(0)
      target = nil
      if prose[finish] == "("
        target, finish = inline_destination(prose, finish + 1)
      elsif prose[finish] == "[" && (close = prose.index("]", finish + 1))
        reference = prose[(finish + 1)...close]
        target = definitions[normalize(reference.empty? ? label : reference)]
        finish = close + 1
      else
        target = definitions[normalize(label)]
      end
      result << Link.new(target: CGI.unescapeHTML(target.gsub(/\\([[:punct:]])/, '\\1')), line: prose[0...match.begin(0)].count("\n") + 1) if target
      offset = [finish, match.end(0)].max
    end
    result
  end

  def anchors
    found = Set.new
    previous = ""
    @prose.each_line do |line|
      heading = line.match(/^ {0,3}\#{1,6}[ \t]+(.+?)(?:[ \t]+\#+)?[ \t]*$/)&.[](1)
      heading = previous.strip if line.match?(/^ {0,3}(?:=+|-+)[ \t]*$/) && !previous.strip.empty?
      if heading
        heading = heading.gsub(/\[([^\]]+)\]\([^)]*\)/, '\\1').gsub(/<[^>]*>/, "")
        slug = CGI.unescapeHTML(heading).downcase.gsub(/[^\p{L}\p{M}\p{N}_\-\s]/, "").gsub(/\s/, "-")
        candidate = slug
        suffix = 0
        while found.include?(candidate)
          suffix += 1
          candidate = "#{slug}-#{suffix}"
        end
        found << candidate
      end
      previous = line
    end
    @prose.scan(/<[a-z][^>]*\s(?:id|name)=["']([^"']+)["'][^>]*>/i) { |anchor| found << CGI.unescapeHTML(anchor.first) }
    found
  end

  private

  def normalize(label)
    label.downcase.split.join(" ")
  end

  def without_examples(text)
    text = text.sub(/\A---\r?\n.*?\r?\n---(?:\r?\n|\z)/m) { |header| header.gsub(/[^\n]/, " ") }
    text = text.gsub(/<!--.*?-->/m) { |comment| comment.gsub(/[^\n]/, " ") }
    fence = nil
    text.lines.map do |line|
      marker = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/)
      if fence
        fence = nil if marker && marker[1][0] == fence[0] && marker[1].length >= fence.length && marker[2].strip.empty?
        line.gsub(/[^\n]/, " ")
      elsif marker
        fence = marker[1]
        line.gsub(/[^\n]/, " ")
      else
        line
      end
    end.join
  end

  def inline_destination(text, offset)
    offset += 1 while text[offset]&.match?(/\s/)
    start = offset
    if text[offset] == "<"
      closing = text.index(">", offset + 1)
      return [nil, offset] unless closing
      target = text[(offset + 1)...closing]
      offset = closing + 1
    else
      depth = 0
      while offset < text.length
        char = text[offset]
        if char == "\\"
          offset += 2
          next
        end
        break if depth.zero? && (char == ")" || char.match?(/\s/))
        depth += 1 if char == "("
        depth -= 1 if char == ")"
        offset += 1
      end
      target = text[start...offset]
    end
    # Consume an optional quoted title and the final delimiter.
    rest = text[offset..]
    ending = rest.match(/\A\s*(?:(?:"[^"]*"|'[^']*'|\([^)]*\))\s*)?\)/m)
    ending ? [target, offset + ending.end(0)] : [nil, offset]
  end
end
