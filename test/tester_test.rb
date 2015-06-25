require 'test_helper'

class ErbSafety::TesterTest < ActiveSupport::TestCase
  test "plain erb tag in html attribute" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%= unsafe %>)">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a onclick="method(<%= unsafe %>)">', errors[0].token.to_s
    assert_equal '<%= unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe ERB tag inside html attribute', errors[0].message
  end

  test "to_json is safe in html attribute" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%= unsafe.to_json %>)">
    EOF
    assert_equal 0, errors.size
  end

  test "j is safe in html attribute" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method('<%= j unsafe %>')">
    EOF
    assert_equal 0, errors.size
  end

  test "j() is safe in html attribute" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method('<%= j(unsafe) %>')">
    EOF
    assert_equal 0, errors.size
  end

  test "escape_javascript is safe in html attribute" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%= escape_javascript unsafe %>)">
    EOF
    assert_equal 0, errors.size
  end

  test "escape_javascript() is safe in html attribute" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%= escape_javascript(unsafe) %>)">
    EOF
    assert_equal 0, errors.size
  end

  test "html_safe is never safe in html attribute, even non javascript attributes like href" do
    errors = tokenize(<<-EOF).errors
      <a href="<%= unsafe.html_safe %>">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a href="<%= unsafe.html_safe %>">', errors[0].token.to_s
    assert_equal '<%= unsafe.html_safe %>', errors[0].erb.to_s
    assert_includes 'unsafe use of html_safe inside html attribute', errors[0].message
  end

  test "html_safe is never safe in html attribute, even with to_json" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%= unsafe.to_json.html_safe %>)">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a onclick="method(<%= unsafe.to_json.html_safe %>)">', errors[0].token.to_s
    assert_equal '<%= unsafe.to_json.html_safe %>', errors[0].erb.to_s
    assert_includes 'unsafe use of html_safe inside html attribute', errors[0].message
  end

  test "<%== is never safe in html attribute, even non javascript attributes like href" do
    errors = tokenize(<<-EOF).errors
      <a href="<%== unsafe %>">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a href="<%== unsafe %>">', errors[0].token.to_s
    assert_equal '<%== unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe use of html_safe inside html attribute', errors[0].message
  end

  test "<%== is never safe in html attribute, even with to_json" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%== unsafe.to_json %>)">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a onclick="method(<%== unsafe.to_json %>)">', errors[0].token.to_s
    assert_equal '<%== unsafe.to_json %>', errors[0].erb.to_s
    assert_includes 'unsafe use of html_safe inside html attribute', errors[0].message
  end

  test "raw is never safe in html attribute, even non javascript attributes like href" do
    errors = tokenize(<<-EOF).errors
      <a href="<%= raw unsafe %>">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a href="<%= raw unsafe %>">', errors[0].token.to_s
    assert_equal '<%= raw unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe use of html_safe inside html attribute', errors[0].message
  end

  test "raw is never safe in html attribute, even with to_json" do
    errors = tokenize(<<-EOF).errors
      <a onclick="method(<%= raw unsafe.to_json %>)">
    EOF

    assert_equal 1, errors.size
    assert_equal '<a onclick="method(<%= raw unsafe.to_json %>)">', errors[0].token.to_s
    assert_equal '<%= raw unsafe.to_json %>', errors[0].erb.to_s
    assert_includes 'unsafe use of html_safe inside html attribute', errors[0].message
  end

  test "unsafe erb in <script> tag without type" do
    errors = tokenize(<<-EOF).errors
      <script>
        if (a < 1) { <%= unsafe %> }
      </script>
    EOF

    assert_equal 1, errors.size
    assert_equal "<script>\n        if (a < 1) { <%= unsafe %> }\n      </script>", errors[0].token.to_s
    assert_equal '<%= unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe ERB tag inside javascript tag', errors[0].message
  end

  test "unsafe erb in javascript_tag" do
    errors = tokenize(<<-EOF).errors
      <%= javascript_tag do %>
        if (a < 1) { <%= unsafe %> }
      <% end %>
    EOF

    assert_equal 1, errors.size
    assert_equal "<%= javascript_tag do %>\n        if (a < 1) { <%= unsafe %> }\n      <% end %>", errors[0].token.to_s
    assert_equal '<%= unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe ERB tag inside javascript tag', errors[0].message
  end

  test "unsafe erb in <script> tag with text/javascript content type" do
    errors = tokenize(<<-EOF).errors
      <script type="text/javascript">
        if (a < 1) { <%= unsafe %> }
      </script>
    EOF

    assert_equal 1, errors.size
    assert_equal "<script type=\"text/javascript\">\n        if (a < 1) { <%= unsafe %> }\n      </script>", errors[0].token.to_s
    assert_equal '<%= unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe ERB tag inside javascript tag', errors[0].message
  end

  test "unsafe html is parsed out of <script> tag with non executable content type" do
    errors = tokenize(<<-EOF).errors
      <script type="text/html">
        <a onclick="<%= unsafe %>">
      </script>
    EOF

    assert_equal 1, errors.size
    assert_equal '<a onclick="<%= unsafe %>">', errors[0].token.to_s
    assert_equal '<%= unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe ERB tag inside html attribute', errors[0].message
  end

  test "unsafe html is parsed out of <script> tag with text/template content type" do
    errors = tokenize(<<-EOF).errors
      <script type="text/template">
        <a onclick="<%= unsafe %>">
      </script>
    EOF

    assert_equal 1, errors.size
    assert_equal '<a onclick="<%= unsafe %>">', errors[0].token.to_s
    assert_equal '<%= unsafe %>', errors[0].erb.to_s
    assert_includes 'unsafe ERB tag inside html attribute', errors[0].message
  end

  private
  def tokenize(data)
    ErbSafety::Tester.new('app/path/test_file.rb', data: data)
  end
end
