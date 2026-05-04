# Leaf

Dual-mode visual WYSIWYG + markdown editor for Phoenix LiveView.

**[Live Demo](https://sasha.don.ee/demo/leaf)**

![Leaf Editor](https://sasha.don.ee/phoenix_kit/file/019d0675-4bb1-7e02-8e51-17f02a37fafe/original/f2bd)

- **Visual mode**: contenteditable div with toolbar formatting (bold, italic, headings, lists, links, code blocks, tables, blockquotes, inline spoilers, etc.)
- **Drag-and-drop reordering**: drag any block element (headings, paragraphs, lists, images, blockquotes, code blocks) to rearrange content
- **Markdown mode**: plain textarea with toolbar support
- **HTML mode**: raw HTML editing for power users
- **Resizable**: drag the bottom-right grip to change height; double-click the grip to auto-fit to content
- **Spoilers**: Discord-style `||hidden||` markdown that renders as a click-to-reveal censored block in published content
- Content syncs between modes via [Earmark](https://hex.pm/packages/earmark) and client-side HTML→Markdown conversion
- No npm dependencies — vendored JS bundle

## Installation

Add `leaf` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:leaf, "~> 0.2.0"}
  ]
end
```

### JavaScript Setup

In your `app.js`, import the JS and register the hook:

```javascript
import "../../../deps/leaf/priv/static/assets/leaf.js"

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: {
    Leaf: window.LeafHooks.Leaf,
    // ... your other hooks
  }
})
```

#### CDN Alternative

If you prefer not to use the `deps/` import path (e.g., non-standard project structure), you can load the JS from CDN instead:

```javascript
// Load Leaf from CDN
const script = document.createElement("script");
script.src = "https://cdn.jsdelivr.net/gh/alexdont/leaf@v0.2.12/priv/static/assets/leaf.js";
script.onload = () => {
  // Leaf is now available at window.LeafHooks
};
document.head.appendChild(script);
```

### Peer Requirements

Leaf's toolbar uses [Tailwind CSS](https://tailwindcss.com/) + [daisyUI](https://daisyui.com/) classes (`btn`, `btn-xs`, `divider`, `textarea`, etc.) and [Heroicons](https://heroicons.com/) CSS classes (`hero-*`). Make sure these are available in your project.

## Usage

First, import the component in your view helpers (e.g., in `my_app_web.ex`):

```elixir
import Leaf, only: [leaf_editor: 1]
```

Then use it in your templates:

```heex
<.leaf_editor
  id="my-editor"
  content={@content}
  mode={:visual}
  toolbar={[:image, :video]}
  placeholder="Write something..."
  readonly={false}
  height="480px"
  debounce={400}
/>
```

<details>
<summary>Alternative: direct LiveComponent syntax</summary>

```heex
<.live_component
  module={Leaf}
  id="my-editor"
  content={@content}
  mode={:visual}
  toolbar={[:image, :video]}
  placeholder="Write something..."
  readonly={false}
  height="480px"
  debounce={400}
/>
```
</details>

### Assigns

| Assign | Type | Default | Description |
|---|---|---|---|
| `id` | string | required | Unique editor ID |
| `content` | string | `""` | Markdown content |
| `mode` | `:visual` \| `:markdown` \| `:html` | `:visual` | Initial editor mode |
| `preset` | `:advanced` \| `:simple` | `:advanced` | Toolbar preset; `:simple` is a compact subset for comments and lightweight editing |
| `toolbar` | list | `[]` | Extra toolbar buttons (`:image`, `:video`) |
| `placeholder` | string | `"Write something..."` | Placeholder text shown when the editor is empty |
| `readonly` | boolean | `false` | Read-only mode |
| `height` | string | `"480px"` | Editor height (the body resizes from this baseline) |
| `debounce` | integer | `400` | Debounce interval in ms for content-change events |
| `loading_preset` | atom | `:random` | Pre-mount loading label preset: `:random` picks from `:unpuzzling`, `:brewing`, `:polishing`, `:composing`, `:crafting`, `:tidying`. `:default` shows plain `"Loading…"` |
| `loading_text` | string | `nil` | Custom loading label; takes precedence over `loading_preset` when set |
| `upload_handler` | any | `nil` | Hint that the consumer supports uploads. When set, the main image button asks the parent for an upload via `:leaf_insert_request`; when `nil`, it opens the by-URL dialog directly |
| `class` | string | `nil` | Extra classes for the wrapper |
| `script_nonce` | string | `""` | CSP nonce for the inline `<style>` block |

### Messages to Parent

Handle these in your LiveView's `handle_info/2`:

```elixir
def handle_info({:leaf_changed, %{editor_id: id, markdown: md, html: html}}, socket) do
  # Content was updated
  {:noreply, assign(socket, :content, md)}
end

def handle_info({:leaf_insert_request, %{editor_id: id, type: :image}}, socket) do
  # User clicked the image toolbar button — show your image picker
  {:noreply, socket}
end

def handle_info({:leaf_mode_changed, %{editor_id: id, mode: mode}}, socket) do
  # Mode switched between :visual and :markdown
  {:noreply, socket}
end
```

### Commands from Parent

```elixir
# Insert an image at the cursor position
send_update(Leaf, id: "my-editor", action: :insert_image, url: "https://...", alt: "description")

# Replace all content
send_update(Leaf, id: "my-editor", action: :set_content, content: "# New content")

# Switch mode programmatically
send_update(Leaf, id: "my-editor", action: :set_mode, mode: :markdown)
```

## Gettext (optional)

To enable translations for toolbar tooltips:

```elixir
# config/config.exs
config :leaf, :gettext_backend, MyApp.Gettext
```

Without this config, English strings are used as-is.

## License

MIT — see [LICENSE](LICENSE).
