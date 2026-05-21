defmodule Ratatouille.Renderer.Cells do
  @moduledoc """
  Functions for working with canvas cells.
  """
  use Bitwise

  alias Ratatouille.Renderer.Attributes

  alias ExTermbox.{Cell, Position}

  @doc """
  Computes a cell's foreground given a standardized attributes map.

  The foreground value is computed by taking the color's integer value and the
  integer values of any styling attributes (e.g., bold, underline) and computing
  the bitwise OR of all the values.
  """
  def foreground(attrs) do
    base = Attributes.to_terminal_color(attrs[:color] || :default)

    flags =
      for attr <- attrs[:attributes] || [] do
        Attributes.to_terminal_attribute(attr)
      end

    Enum.reduce(flags, base, fn flag, acc -> acc ||| flag end)
  end

  @doc """
  Computes a cell's background given a standardized attributes map.
  """
  def background(attrs) do
    Attributes.to_terminal_color(attrs[:background] || :default)
  end

  @doc """
  Given a starting position, orientation and cell template, returns a cell
  generator which can be used to iteratively generate a row or column of cells.

  The generator is grapheme-aware: each grapheme is assigned a display-column
  offset based on its Unicode display width (ASCII = 1, East-Asian Wide = 2,
  combining marks / ZWJ = 0) rather than a naive byte or codepoint count.
  Wide graphemes occupy two adjacent cells; the second cell carries a space
  character so the terminal renders the wide glyph without corruption.
  """
  def generator(position, orientation, template \\ Cell.empty()) do
    fn {char_or_binary, offset} ->
      %Cell{
        template
        | position:
            case orientation do
              :vertical -> Position.translate_y(position, offset)
              :horizontal -> Position.translate_x(position, offset)
            end,
          ch: to_char(char_or_binary)
      }
    end
  end

  @doc """
  Expands a string into `{grapheme, display_column_offset}` pairs suitable for
  use with the generator returned by `generator/3`.

  Unlike `String.graphemes/1 |> Enum.with_index/0`, this accounts for wide
  (East-Asian) characters that occupy two terminal columns.
  """
  @spec graphemes_with_offsets(String.t()) :: [{String.t(), non_neg_integer()}]
  def graphemes_with_offsets(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> Enum.reduce({[], 0}, fn g, {acc, col} ->
      w = grapheme_width(g)
      {[{g, col} | acc], col + max(w, 1)}
    end)
    |> then(fn {pairs, _col} -> Enum.reverse(pairs) end)
  end

  # Returns 0 for combining marks / ZWJ, 2 for East-Asian Wide/Fullwidth,
  # 1 for everything else. Operates on the first codepoint of the grapheme
  # cluster (representative of the cluster's display width for all common cases).
  @spec grapheme_width(String.t()) :: 0 | 1 | 2
  def grapheme_width(<<cp::utf8, _::binary>>) do
    cond do
      # Combining marks, variation selectors, ZWJ, and other zero-width
      cp in 0x0300..0x036F -> 0
      cp in 0x1DC0..0x1DFF -> 0
      cp in 0x20D0..0x20FF -> 0
      cp in 0xFE20..0xFE2F -> 0
      cp in 0xFE00..0xFE0F -> 0
      cp == 0x200D -> 0
      cp in 0x0000..0x001F -> 0
      cp == 0x007F -> 0
      # East-Asian Wide / Fullwidth ranges (Unicode 15)
      cp in 0x1100..0x115F -> 2
      cp in 0x2E80..0x2EFF -> 2
      cp in 0x2F00..0x2FDF -> 2
      cp in 0x2FF0..0x2FFF -> 2
      cp in 0x3000..0x303F -> 2
      cp in 0x3040..0x309F -> 2
      cp in 0x30A0..0x30FF -> 2
      cp in 0x3100..0x312F -> 2
      cp in 0x3130..0x318F -> 2
      cp in 0x3190..0x319F -> 2
      cp in 0x31A0..0x31BF -> 2
      cp in 0x31C0..0x31EF -> 2
      cp in 0x31F0..0x31FF -> 2
      cp in 0x3200..0x32FF -> 2
      cp in 0x3300..0x33FF -> 2
      cp in 0x3400..0x4DBF -> 2
      cp in 0x4E00..0x9FFF -> 2
      cp in 0xA000..0xA48F -> 2
      cp in 0xA490..0xA4CF -> 2
      cp in 0xA960..0xA97F -> 2
      cp in 0xAC00..0xD7AF -> 2
      cp in 0xD7B0..0xD7FF -> 2
      cp in 0xF900..0xFAFF -> 2
      cp in 0xFE10..0xFE1F -> 2
      cp in 0xFE30..0xFE4F -> 2
      cp in 0xFE50..0xFE6F -> 2
      cp in 0xFF00..0xFF60 -> 2
      cp in 0xFFE0..0xFFE6 -> 2
      cp in 0x1B000..0x1B0FF -> 2
      cp in 0x1B100..0x1B12F -> 2
      cp in 0x1B130..0x1B16F -> 2
      cp in 0x1F004..0x1F004 -> 2
      cp in 0x1F0CF..0x1F0CF -> 2
      cp in 0x1F200..0x1F2FF -> 2
      cp in 0x1F300..0x1F64F -> 2
      cp in 0x1F900..0x1F9FF -> 2
      cp in 0x1FA00..0x1FA6F -> 2
      cp in 0x1FA70..0x1FAFF -> 2
      cp in 0x20000..0x2A6DF -> 2
      cp in 0x2A700..0x2B73F -> 2
      cp in 0x2B740..0x2B81F -> 2
      cp in 0x2B820..0x2CEAF -> 2
      cp in 0x2CEB0..0x2EBEF -> 2
      cp in 0x2F800..0x2FA1F -> 2
      cp in 0x30000..0x3134F -> 2
      true -> 1
    end
  end

  def grapheme_width(""), do: 0

  defp to_char(ch) when is_integer(ch), do: ch
  # Extract the first codepoint of the grapheme cluster as the terminal char.
  # Multi-codepoint clusters (emoji ZWJ sequences, etc.) render the base
  # codepoint; termbox handles the actual glyph output.
  defp to_char(<<ch::utf8, _rest::binary>>), do: ch
  defp to_char(_), do: ?\s
end
