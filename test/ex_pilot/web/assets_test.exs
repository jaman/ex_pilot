defmodule ExPilot.Web.AssetsTest do
  use ExUnit.Case, async: true

  alias ExPilot.Web.Assets

  test "a static file's path carries a version that changes with the file" do
    assert Assets.path(:ex_pilot, "expilot.css") =~ ~r"\A/expilot\.css\?vsn=[0-9a-f]{8}\z"
    assert Assets.path(:cauldron_2d_net, "cauldron.js") =~ ~r"\A/cauldron\.js\?vsn=[0-9a-f]{8}\z"

    assert Assets.path(:phoenix, "phoenix.min.js", at: "/vendor") =~
             ~r"\A/vendor/phoenix\.min\.js\?vsn=[0-9a-f]{8}\z"

    assert Assets.sheet_path() =~ ~r"\A/atlas\.png\?vsn=[0-9a-f]{1,8}\z"

    dir = Path.join(System.tmp_dir!(), "ex_pilot_assets_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    file = Path.join(dir, "a.css")
    File.write!(file, "a { color: red }")
    first = Assets.version(file)
    File.write!(file, "a { color: blue }")
    assert Assets.version(file) != first
    assert Assets.version(Path.join(dir, "missing.css")) == "00000000"
  end
end
