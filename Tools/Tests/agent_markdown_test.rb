# frozen_string_literal: true

require "minitest/autorun"
require_relative "../agent_markdown"

class AgentMarkdownTest < Minitest::Test
  def test_inline_reference_multiline_and_image_links_with_titles_and_balanced_paths
    markdown = <<~MD
      [multi
      line](<dir/a file.md#section> "Title")
      [parentheses](a(b).md) ![image](assets/image.png)
      [full][REF] [collapsed][] [shortcut]
      [REF]: ../guide.md#next "Guide"
      [collapsed]: other.md
      [shortcut]: #top
      [escaped](path\\(1\\).md)
      [outside](https://example.com?a=1&amp;b=2)
    MD
    links = AgentMarkdown.new(markdown).links
    assert_equal ["dir/a file.md#section", "a(b).md", "assets/image.png", "../guide.md#next", "other.md", "#top", "path(1).md", "https://example.com?a=1&b=2"], links.map(&:target)
    assert_equal 1, links.first.line
    assert_equal 3, links[1].line
  end

  def test_examples_frontmatter_and_comments_do_not_create_links_or_headings
    markdown = <<~MD
      ---
      description: '[fake](missing)'
      ---
      ````md
      # Hidden
      ```
      [fake](missing)
      ````
      ~~~
      # Also hidden
      [fake](missing)
      ~~~
      `[fake](missing)` and ``[fake](missing)``
      <!-- [fake](missing) -->
      # Visible
      [real](#visible)
    MD
    parser = AgentMarkdown.new(markdown)
    assert_equal ["#visible"], parser.links.map(&:target)
    assert_equal ["visible"], parser.anchors.to_a
  end

  def test_heading_anchors_handle_unicode_formatting_duplicates_setext_and_html
    markdown = <<~MD
      # Café: `Type` & API
      # Same
      # Same
      # Same-1
      # Same
      Section name
      ------------
      ## [Linked title](guide.md) ##
      <a id="explicit-anchor"></a>
    MD
    assert_equal ["café-type--api", "same", "same-1", "same-1-1", "same-2", "section-name", "linked-title", "explicit-anchor"], AgentMarkdown.new(markdown).anchors.to_a
  end
end
