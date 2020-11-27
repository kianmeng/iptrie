defmodule Iptrie.Dot do
  @moduledoc """
  Functions to save an Iptrie as a simple graphviz dot file.

  """

  alias Iptrie.Pfx
  alias Iptrie.Rdx

  @color %{
    root: "orange",
    node: "yellow",
    leaf: "green"
  }

  # Helpers

  defp to_ascii(key) do
    key
    |> Pfx.to_ascii()
    |> Pfx.ok()
  end

  # DUMP nodes, accumulator is [ids, nodes, verts]
  # A leaf:
  # - adds node to nodes (id = length of nodes)
  # - adds id to ids
  # A node:
  # - adds node to nodes (id = length of nodes) -- if non-nil
  # - ads id or nil to ids
  # - adds self-id -> child-id to verts

  defp dump([ids, nodes, verts], {pos, _l, _r}) do
    id = length(nodes)
    [rid, lid | rest] = ids
    bgcolor = if pos == 0, do: @color[:root], else: @color[:node]

    node = """
    N#{id} [label=<
      <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD PORT="N#{id}" COLSPAN="2" BGCOLOR="#{bgcolor}">bit #{pos}</TD></TR>
        <TR><TD PORT=\"L\">0</TD><TD PORT=\"R\">1</TD></TR>
      </TABLE>
    >, shape="plaintext"];
    """

    nodes = [node | nodes]
    verts = if lid != nil, do: ["N#{id}:L -> N#{lid};\n" | verts], else: verts
    verts = if rid != nil, do: ["N#{id}:R -> N#{rid};\n" | verts], else: verts

    [[id | rest], nodes, verts]
  end

  defp dump([ids, nodes, verts], nil), do: [[nil | ids], nodes, verts]

  defp dump([ids, nodes, verts], leaf) do
    id = length(nodes)

    body =
      leaf
      |> Enum.map(fn x -> to_ascii(elem(x, 0)) end)
      |> Enum.map(fn x -> "  <TR><TD>#{x}</TD></TR>" end)
      |> Enum.join("\n  ")

    node = """
    N#{id} [label=<
      <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
        <TR><TD PORT="N#{id}" BGCOLOR="#{@color[:leaf]}">LEAF</TD></TR>
      #{body}
      </TABLE>
      >, shape="plaintext"];
    """

    [[id | ids], [node | nodes], verts]
  end

  # TODO:
  #  add opts to color specific key(s) differently
  #  - perhaps an Iptrie with properties for drawing and using lpm match
  def dotify(bst, _title) do
    [_ids, nodes, verts] = Rdx.traverse([[], [], []], fn n, x -> dump(n, x) end, bst, :postorder)

    body = Enum.join(nodes) <> "\n" <> Enum.join(verts)

    # To add a title, include:
    # label="#{title}";

    """
    digraph G {

      labelloc="t";
      rankdir="TB";
      ranksep="0.5 equally";


      #{body}
    }
    """
  end

  def to_dotfile(bst, fname) do
    File.write(fname, dotify(bst, fname))
  end
end
