# erb_safety
Asserts the safety of ERB interpolations

## How does it work?

This gem will build a representation of a html/erb file and determine which
interpolations are unsafe based on simple rules.

Some of the rules include:
* Always use javascript-safe method around a interpolated ruby variable. For example, `<%= something %>` is not safe, but `<%= something.to_json %>` or `<%= j(something) %>` are both safe.
* In a html attribute, it is *never safe* to use `<= (...).html_safe %>` or `<%== ... %>` or `<%= raw(...) %>`.
* In a `<script>` tag or `javascript_tag do` block, the presence of `<= (...).html_safe %>` or `<%== ... %>` or `<%= raw(...) %>` is safe.

## Usage

In your rails project, create a test, like this:

```ruby
class EscapingTest < ActiveSupport::TestCase
  ERB_GLOB = File.join(Rails.root, 'app/views/**/{*.htm,*.html,*.htm.erb,*.html.erb}')

  Dir[ERB_GLOB].each do |filename|
    test "missing javascript escapes in #{filename}" do
      tester = ErbSafety::Tester.new(filename)
      tester.errors.each do |error|
        puts "-------"
        puts error.to_s
      end
      assert_equal 0, tester.errors.size
    end
  end
end
```

The test will raise if there are unsafe interpolations in your views. The detection
is limited to inline html, but it can catch low hanging fruits effectively.

For example:
```html
<div>
  <a onclick="<%= something %>">
</div>
```

The above example will raise the following error:
```
Found: unsafe ERB tag inside html attribute
  <a onclick="<%= something %>">
The unsafe interpolation is:
  <%= something %>
```
