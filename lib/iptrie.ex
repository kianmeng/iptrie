defmodule Iptrie do
  @moduledoc """
  A Key,Value-store for IPv4 and IPv6 in CIDR notation and longest prefix matching.

  Iptrie provides an interface to store, retrieve or modify prefix,value-pairs
  in an IP lookup table, where the prefix is a regular string like "1.1.1.0/30"
  or "acdc:1976::/32".

  It uses `Iptrie.Pfx` to convert prefixes between their string- and bitstring
  formats which are used as keys to index into a radix tree (r=2), as provided
  by the `Radix` module.

  By convention,  *pfx* refers to a prefix in its string-form, while *key*
  refers to the bitstring-encoded form as used by the radix tree.

  ## Examples

      iex> ipt = new([
      ...> {"1.1.1.0/30", "1.1.1.0/30"},
      ...> {"1.1.1.252/30", "1.1.1.252/30"},
      ...> {"1.1.1.0/24", "1.1.1.0/24"},
      ...> {"acdc:1975::/32", "High Voltage"},
      ...> {"acdc:1976::/32", "Jailbreak"},
      ...> {"acdc:1977::/32", "Dog eat dog"},
      ...>])
      iex>
      iex> lookup(ipt, "acdc:1976:abba::")
      {<<1::8, 0xacdc::16, 0x1976::16>>, "Jailbreak"}
      iex>
      iex> lookup(ipt, "1.1.1.3")
      {<<0::8, 1::8, 1::8, 1::8, 0::6>>, "1.1.1.0/30"}
      iex>
      iex> lookup(ipt, "1.1.1.45")
      {<<0::8, 1::8, 1::8, 1::8>>, "1.1.1.0/24"}
      iex>
      iex> ipt
      {0,
        {7, {32, {-1, [{<<0, 1, 1, 1, 0::size(6)>>, "1.1.1.0/30"},
                       {<<0, 1, 1, 1>>, "1.1.1.0/24"}]},
                 {-1, [{<<0, 1, 1, 1, 63::size(6)>>, "1.1.1.252/30"}]}
            },
            {38, {-1, [{<<1, 172, 220, 25, 117>>, "High Voltage"}]},
                 {39, {-1, [{<<1, 172, 220, 25, 118>>, "Jailbreak"}]},
                      {-1, [{<<1, 172, 220, 25, 119>>, "Dog eat dog"}]}}
            }
            },
        nil
      }
      iex>
      iex> Iptrie.Dot.write(ipt, "doc/img/example.dot")
      :ok

  ![example](img/example.dot.png)

  """
  alias Prefix.IP
  alias PrefixError
  alias Radix

  # TODO
  # - use pfx instead of key(s), the latter is used in Radix only

  # HELPERS

  @doc """
  Return a prefix-string representation of a radix key or `{:error, reason}`

  ## Examples

      iex> ascii(<<0::8, 1::8, 1::8>>)
      "1.1.0.0/16"

      iex> ascii(<<1::8, 0xacdc::16, 0x1979::16>>)
      "acdc:1979::/32"

      iex> ascii(<<0::8, 1::33>>)  # an IPv4 key with too many bits
      %PrefixError{id: :eaddress, detail: "<<0, 0, 0, 0, 0, 1::size(1)>>"}
  """
  def ascii(key),
    do:
      key
      |> IP.format()

  # Api
  @doc """
  Create an new, empty Iptrie.

  ## Example

      iex> Iptrie.new()
      {0, nil, nil}

  """
  def new, do: Radix.new()

  @doc """
  Create a new Iptrie populated with the given list of prefix-value pairs.

  The prefixes are converted into radix keys whose first bit indicates whether it
  is an IPv4 address or an IPv6 address.  Hence, the left subtree of the root
  node is the v4-tree and its right subtree is the v6-tree.

  ## Example
      iex> elements = [{"1.1.1.1", "1.1.1.1"}, {"1.1.1.0/30", "1.1.1.0/30"}]
      iex> new(elements)
      {0,
        {39, {-1, [{<<0, 1, 1, 1, 0::size(6)>>, "1.1.1.0/30"}]},
             {-1, [{<<0, 1, 1, 1, 1>>, "1.1.1.1"}]}
        },
        nil
      }

  """
  def new(elements) when is_list(elements) do
    Enum.reduce(elements, Radix.new(), fn elm, t -> set(t, elm) end)
  end

  # for convenience: add a list of [{k,v},...] to a tree
  @doc """
  Enter a single prefix-value pair or list thereof, into an iptrie.

  ## Example

      iex> new()
      ...> |> set([{"1.1.1.0/30", "1.1.1.0/30"}, {"1.1.1.1", "1.1.1.1"}])
      {0,
        {39, {-1, [{<<0, 1, 1, 1, 0::size(6)>>, "1.1.1.0/30"}]},
             {-1, [{<<0, 1, 1, 1, 1>>, "1.1.1.1"}]}
        },
        nil}

      iex> new()
      ...> |> set({"1.1.1.1", "1.1.1.1"})
      ...> |> set({"acdc::1976/16", "jailbreak"})
      {0,
        {7, {-1, [{<<0, 1, 1, 1, 1>>, "1.1.1.1"}]},
            {-1, [{<<1, 172, 220>>, "jailbreak"}]}
        },
        nil
      }
  """
  def set(tree, element_or_elements)

  def set(tree, elements) when is_list(elements) do
    Enum.reduce(elements, tree, fn elm, t -> set(t, elm) end)
  end

  def set(tree, {pfx, val}) do
    case IP.encode(pfx) do
      %PrefixError{} = x -> x
      key -> Radix.set(tree, {key, val})
    end
  end

  @doc """
  Lookup the longest matching prefix given a Iptrie and a prefix or address.
  Returns the {key, value}-pair when a match was found, nil otherwise.  Note
  that the key, in bitstring format, is not converted to its string form.

  ## Examples

      iex> table = new([{"1.1.1.1", "1.1.1.1"}, {"1.1.1.0/30", "1.1.1.0/30"}])
      iex> lookup(table, "1.1.1.3")
      {<<0, 1, 1, 1, 0::size(6)>>, "1.1.1.0/30"}
      iex>
      iex> lookup(table, "1.1.1.1")
      {<<0::8, 1::8, 1::8, 1::8, 1::8>>, "1.1.1.1"}
      iex>
      iex> lookup(table, "1.1.1.5")
      nil
      iex> lookup(table, "1.1.1.256")
      %PrefixError{id: :eaddress, detail: "1.1.1.256"}


  """
  def lookup(tree, key) do
    case IP.encode(key) do
      %PrefixError{} = x -> x
      key -> Radix.lpm(tree, key)
    end
  end
end
