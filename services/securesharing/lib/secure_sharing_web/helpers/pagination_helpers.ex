defmodule SecureSharingWeb.Helpers.PaginationHelpers do
  @moduledoc """
  Helper functions for pagination in API endpoints.

  Provides consistent pagination across all list endpoints with configurable
  defaults and maximum limits to prevent unbounded queries.

  ## Usage

      import SecureSharingWeb.Helpers.PaginationHelpers

      def index(conn, params) do
        pagination = parse_pagination(params)
        items = MyContext.list_items(pagination)
        render(conn, :index, items: items, pagination: pagination)
      end
  """

  @default_page 1
  @default_page_size 20
  @max_page_size 100

  @doc """
  Parses pagination parameters from request params.

  Returns a map with :page, :page_size, :offset, and :limit keys.

  ## Options

  - "page" - Page number (1-indexed, default: 1)
  - "page_size" - Items per page (default: 20, max: 100)

  ## Examples

      parse_pagination(%{"page" => "2", "page_size" => "50"})
      #=> %{page: 2, page_size: 50, offset: 50, limit: 50}

      parse_pagination(%{})
      #=> %{page: 1, page_size: 20, offset: 0, limit: 20}
  """
  @spec parse_pagination(map()) :: map()
  def parse_pagination(params) do
    page = parse_int(params["page"], @default_page) |> max(1)
    page_size = parse_int(params["page_size"], @default_page_size) |> clamp(1, @max_page_size)
    offset = (page - 1) * page_size

    %{
      page: page,
      page_size: page_size,
      offset: offset,
      limit: page_size
    }
  end

  @doc """
  Builds pagination metadata for response.

  ## Examples

      build_pagination_meta(items, %{page: 1, page_size: 20}, 100)
      #=> %{page: 1, page_size: 20, total_items: 100, total_pages: 5, has_next: true, has_prev: false}
  """
  @spec build_pagination_meta(list(), map(), non_neg_integer()) :: map()
  def build_pagination_meta(_items, pagination, total_count) do
    total_pages = ceil(total_count / pagination.page_size)

    %{
      page: pagination.page,
      page_size: pagination.page_size,
      total_items: total_count,
      total_pages: total_pages,
      has_next: pagination.page < total_pages,
      has_prev: pagination.page > 1
    }
  end

  @doc """
  Applies pagination to an Ecto query.

  ## Examples

      query
      |> paginate(%{offset: 20, limit: 10})
      |> Repo.all()
  """
  @spec paginate(Ecto.Query.t(), map()) :: Ecto.Query.t()
  def paginate(query, %{offset: offset, limit: limit}) do
    import Ecto.Query, only: [offset: 2, limit: 2]

    query
    |> offset(^offset)
    |> limit(^limit)
  end

  @doc """
  Returns the default page size.
  """
  @spec default_page_size() :: pos_integer()
  def default_page_size, do: @default_page_size

  @doc """
  Returns the maximum allowed page size.
  """
  @spec max_page_size() :: pos_integer()
  def max_page_size, do: @max_page_size

  # Private helpers

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(value, _default) when is_integer(value), do: value
  defp parse_int(_, default), do: default

  defp clamp(value, min, max) do
    value |> max(min) |> min(max)
  end
end
