defmodule Leaf.ClientStringsTest do
  # The strings leaf.js draws itself reach it translated, as `data-leaf-i18n`.
  use ExUnit.Case, async: false

  defmodule Backend do
    use Gettext.Backend, otp_app: :leaf, priv: "test/fixtures/gettext"
  end

  setup do
    on_exit(fn ->
      Process.delete(:leaf_gettext_backend)
      Gettext.put_locale(Backend, "en")
    end)
  end

  test "no backend: no attribute" do
    Process.delete(:leaf_gettext_backend)
    assert Leaf.client_strings_json() == nil
  end

  test "a backend with no translation for the locale: no attribute" do
    Process.put(:leaf_gettext_backend, Backend)
    Gettext.put_locale(Backend, "fr")
    assert Leaf.client_strings_json() == nil
  end

  test "only the strings that are translated, keyed by their English" do
    Process.put(:leaf_gettext_backend, Backend)
    Gettext.put_locale(Backend, "de")

    assert Jason.decode!(Leaf.client_strings_json()) == %{
             "Cancel" => "Abbrechen",
             "Delete" => "Löschen",
             "Edit <{tag}> source" => "Quelle von <{tag}> bearbeiten"
           }
  end

  test "the client strings are in the catalog template" do
    msgids = Leaf.Gettext.Pot.msgids(File.read!("lib/leaf.ex"))

    for s <- ["Edit <{tag}> source", "Insert date", "Remove link", "Search emoji..."] do
      assert s in msgids
    end
  end
end
