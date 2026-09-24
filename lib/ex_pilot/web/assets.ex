defmodule ExPilot.Web.Assets do
  @moduledoc """
  Versioned paths for the static files the pages load, so a browser or a cache in
  front of the server — Cloudflare caches stylesheets and scripts by extension —
  fetches a file again once it changes.

      ExPilot.Web.Assets.path(:ex_pilot, "expilot.css")
      #=> "/expilot.css?vsn=3f2a9c1e"

  The version is a digest of the file's contents in the application's `priv/static`;
  `Plug.Static` serves a `vsn`-tagged request as cacheable for a year. `sheet_path/0`
  is the same for the sprite sheet, whose version is a hash of the sheet's PNG.
  """

  alias Cauldron2D.Net.Sheet

  @doc "The path to `file` in `app`'s `priv/static`, under `at:` (default `/`), with its version."
  @spec path(atom(), String.t(), keyword()) :: String.t()
  def path(app, file, opts \\ []) do
    at = Keyword.get(opts, :at, "/")
    version = app |> Application.app_dir(["priv", "static", file]) |> version()
    Path.join(at, file) <> "?vsn=" <> version
  end

  @doc "The path of the sprite sheet, with a version that changes with its pixels."
  @spec sheet_path() :: String.t()
  def sheet_path do
    sheet = Sheet.cached(ExPilot.Client.atlas())

    "/atlas.png?vsn=" <>
      String.downcase(Integer.to_string(:erlang.phash2(sheet.png, 4_294_967_296), 16))
  end

  @doc "Eight hex characters of the file's content digest; `\"00000000\"` when it cannot be read."
  @spec version(Path.t()) :: String.t()
  def version(file) do
    case File.read(file) do
      {:ok, contents} ->
        :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower) |> binary_part(0, 8)

      {:error, _reason} ->
        "00000000"
    end
  end
end
