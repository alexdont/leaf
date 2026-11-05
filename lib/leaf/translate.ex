defmodule Leaf.Translate do
  @moduledoc false
  # The editor's gettext lookup, shared by the component and the chip renderer.

  # Per-instance gettext: render/1 stashes the editor's `gettext_backend`
  # assign in the process dictionary (render runs synchronously in the
  # LiveView process), so the bare `t(...)` calls in the template pick it
  # up without threading the backend through every call site. Falls back to
  # the app-global config, then to the untranslated string.
  #
  # Lookups try the `"leaf"` domain first (what the shipped
  # `priv/gettext/leaf.pot` merges into) and fall back to `"default"` for
  # hosts that would rather keep everything in one catalog. Gettext returns
  # the msgid unchanged when there is no translation, which is exactly the
  # signal for "try the other domain".
  @doc false
  def t(string) do
    backend =
      Process.get(:leaf_gettext_backend) ||
        Application.get_env(:leaf, :gettext_backend)

    case backend do
      nil ->
        string

      backend ->
        case Gettext.dgettext(backend, "leaf", string) do
          ^string -> Gettext.gettext(backend, string)
          translated -> translated
        end
    end
  end
end
