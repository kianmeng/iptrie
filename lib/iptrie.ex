defmodule Iptrie do
  @moduledoc """
  A Key,Value-store for IPv4 and IPv6 networks or addresses with
  longest prefix matching.

  ## Examples

      iex> elms = [{"1.1.1.0/24", 24}, {"3.0.0.0/8", 8},
      ...>  {"1.1.1.0/25", "lower"}, {"1.1.1.128/25", "upper"},
      ...>  {"acdc:1975::", "T.N.T"}, {"acdc:1976::", "High Voltage"},
      ...>  {"abba:1975::", "abba"}, {"abba:1976::", "Arrival"}]
      iex> ipt = new(elms)
      iex> Iptrie.Dot.write(ipt, "doc/img/example.dot", "example")

  # ![example](img/example.dot.png)

  """
  import Prefix
  import Prefix.IP
  alias PrefixError
  alias Radix
  alias Iptrie.Dot

  defstruct root: nil

  @type t :: %__MODULE__{}

  # IP v4/v6 markers
  @ip4 <<0::1>>
  @ip6 <<1::1>>

  # Key/Unkey
  # - key returns a prefix's bits with an IPv4/IPv6 marker preprended
  # - unkey does the opposite and returns the original prefix
  # used so both types can be stuffed down the same Radix tree
  defp key(%Prefix{bits: bits, maxlen: 32}),
    do: <<@ip4, bits::bitstring>>

  defp key(%Prefix{bits: bits, maxlen: 128}),
    do: <<@ip6, bits::bitstring>>

  defp unkey(<<@ip4, bits::bitstring>>),
    do: %Prefix{bits: bits, maxlen: 32}

  defp unkey(<<@ip6, bits::bitstring>>),
    do: %Prefix{bits: bits, maxlen: 128}

  # given to Dot to dump a Iptrie to graphviz file
  def key_tostring(key) do
    key
    |> unkey()
    |> decode()
  end

  # Table

  @doc """
  Create an new, empty Iptrie.

  ## Example

      iex> Iptrie.new()
      %Iptrie{root: {0, nil, nil}}

  """
  def new, do: %__MODULE__{root: Radix.new()}

  @doc """
  Create a new Iptrie populated with the given prefix,value pair(s).

  """
  def new(elements), do: new() |> set(elements)

  # for convenience: add a list of [{k,v},...] to a tree
  @doc """
  Enter a single prefix-value pair or list thereof, into an iptrie.

  """
  def set(tree, pfx, val) do
    case encode(pfx) do
      x when is_exception(x) -> raise x
      x -> %{tree | root: Radix.set(tree.root, key(x), val)}
    end
  end

  def set(tree, elements) do
    Enum.reduce(elements, tree, fn {k, v}, t -> set(t, k, v) end)
  end

  @doc """
  Look for the longest matching prefix in an Iptrie.

  """
  @spec lookup(t(), String.t() | Prefix.t() | :inet.ip_address()) :: term
  def lookup(%__MODULE__{} = tree, pfx) when is_binary(pfx),
    do: lookup(tree, encode(pfx))

  def lookup(%__MODULE__{} = tree, x) when is_tuple(x),
    do: lookup(tree, encode(x))

  def lookup(%__MODULE__{} = tree, %Prefix{} = x),
    do: Radix.lpm(tree.root, key(x))

  def lookup(_, _), do: nil

  def dot(tree, fname),
    do: Dot.write(tree, fname)

  # IP prefixes

  @doc """
  Return the this-network address for given *prefix*.

  ## Examples

      iex> network("1.1.1.10/24")
      "1.1.1.0"

      iex> network({{1, 1, 1, 10}, 24})
      "1.1.1.0"

  """
  def network(prefix) do
    prefix
    |> encode()
    |> padr()
    |> decode()
  end

  @doc """
  Return the broadcast address for given *prefix*.

  ## Examples

      iex> broadcast("1.1.1.10/24")
      "1.1.1.255"

      iex> broadcast({{1, 1, 1, 10}, 24})
      "1.1.1.255"

  """
  def broadcast(prefix) do
    prefix
    |> encode()
    |> padr(1)
    |> decode()
  end

  @doc """
  Return the list of host addresses for given *prefix*.

  ## Example

      iex> hosts("1.1.1.0/30")
      ["1.1.1.0", "1.1.1.1", "1.1.1.2", "1.1.1.3"]

  """
  def hosts(prefix) do
    prefix
    |> encode()
    |> Enum.map(fn ip -> decode(ip) end)
  end

  @doc """
  Returns the mask for given prefix.

  ## Example

      iex> mask("1.1.1.0/24")
      "255.255.255.0"

      iex> mask("1.1.1.0/22")
      "255.255.252.0"
  """
  def mask(prefix) do
    prefix
    |> encode()
    |> (&bxor(&1, &1)).()
    |> bnot()
    |> padr()
    |> decode()
  end

  @doc """
  Returns the inverse mask for given prefix.

  ## Example

      iex> inv_mask("1.1.1.0/24")
      "0.0.0.255"

      iex> inv_mask("1.1.1.0/23")
      "0.0.1.255"

  """
  def inv_mask(prefix) do
    prefix
    |> encode()
    |> (&bxor(&1, &1)).()
    |> padr(1)
    |> decode()
  end

  @doc """
  Returns the neighboring prefix such that both can be combined in a supernet.

  ## Example

      iex> neighbor("1.1.1.0/25")
      "1.1.1.128/25"

  """
  def neighbor(prefix) do
    x = encode(prefix)
    n = 1 - 2 * bit(x, bit_size(x.bits) - 1)

    sibling(x, n)
    |> decode()
  end

  @doc """
  Jump to another prefix at distance `n`.

  This will wrap around the available address space without warning.

  ## Examples

      iex> jump("1.1.1.0/24", 1)
      "1.1.2.0/24"

      iex> jump("1.1.1.0/30", 64)
      "1.1.2.0/30"

      iex> jump("0.0.0.0", -1)
      "255.255.255.255"

      iex> jump("255.255.255.255", 1)
      "0.0.0.0"

  """
  def jump(prefix, n) do
    prefix
    |> encode()
    |> sibling(n)
    |> decode()
  end

  @doc """
  Return the host address for the *nth*-member of the prefix.

  This will wrap around the available address space without warning.

  ## Examples

      iex> host("1.1.1.0/24", 129)
      "1.1.1.129"

      iex> host("1.1.1.0/24", 256)
      "1.1.1.0"

  """
  def host(prefix, nth) do
    prefix
    |> encode()
    |> member(nth)
    |> decode()
  end

  @doc """
  Return the number of host addresses available in given *prefix*.

  ## Example

      iex> numhosts("acdc:1976::/32")
      79228162514264337593543950336
  """
  def numhosts(prefix) do
    prefix
    |> encode()
    |> size()
  end

  # TODO Table funcs
  # o exec :: apply function to all nodes & leafs
  # o get :: get exact match
  # o less :: return all less specifics (option inclusive)
  # o map :: apply function to all {k,v}-pairs
  # o more :: return all more specifics (option inclusive)

  # TODO Prefix funcs
  # o hosts_lazy :: return stream that returns hosts addresses
end
