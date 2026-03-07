defmodule SecureSharingWeb.Helpers.PaginationHelpersTest do
  use ExUnit.Case, async: true

  alias SecureSharingWeb.Helpers.PaginationHelpers

  describe "parse_pagination/1" do
    test "returns defaults for empty params" do
      result = PaginationHelpers.parse_pagination(%{})

      assert result.page == 1
      assert result.page_size == 20
      assert result.offset == 0
      assert result.limit == 20
    end

    test "parses page and page_size from string params" do
      result = PaginationHelpers.parse_pagination(%{"page" => "3", "page_size" => "50"})

      assert result.page == 3
      assert result.page_size == 50
      # (3-1) * 50
      assert result.offset == 100
      assert result.limit == 50
    end

    test "parses integer params" do
      result = PaginationHelpers.parse_pagination(%{"page" => 2, "page_size" => 25})

      assert result.page == 2
      assert result.page_size == 25
      assert result.offset == 25
      assert result.limit == 25
    end

    test "enforces minimum page of 1" do
      result = PaginationHelpers.parse_pagination(%{"page" => "0"})
      assert result.page == 1

      result = PaginationHelpers.parse_pagination(%{"page" => "-5"})
      assert result.page == 1
    end

    test "enforces minimum page_size of 1" do
      result = PaginationHelpers.parse_pagination(%{"page_size" => "0"})
      assert result.page_size == 1

      result = PaginationHelpers.parse_pagination(%{"page_size" => "-10"})
      assert result.page_size == 1
    end

    test "enforces maximum page_size of 100" do
      result = PaginationHelpers.parse_pagination(%{"page_size" => "200"})
      assert result.page_size == 100
      assert result.limit == 100

      result = PaginationHelpers.parse_pagination(%{"page_size" => "1000"})
      assert result.page_size == 100
    end

    test "handles invalid string values with defaults" do
      result = PaginationHelpers.parse_pagination(%{"page" => "invalid", "page_size" => "abc"})

      assert result.page == 1
      assert result.page_size == 20
    end

    test "calculates offset correctly for various pages" do
      # Page 1, size 10 -> offset 0
      result = PaginationHelpers.parse_pagination(%{"page" => "1", "page_size" => "10"})
      assert result.offset == 0

      # Page 5, size 10 -> offset 40
      result = PaginationHelpers.parse_pagination(%{"page" => "5", "page_size" => "10"})
      assert result.offset == 40

      # Page 3, size 25 -> offset 50
      result = PaginationHelpers.parse_pagination(%{"page" => "3", "page_size" => "25"})
      assert result.offset == 50
    end
  end

  describe "build_pagination_meta/3" do
    test "builds correct metadata" do
      pagination = %{page: 2, page_size: 10, offset: 10, limit: 10}
      items = Enum.to_list(1..10)
      total_count = 35

      meta = PaginationHelpers.build_pagination_meta(items, pagination, total_count)

      assert meta.page == 2
      assert meta.page_size == 10
      assert meta.total_items == 35
      # ceil(35/10)
      assert meta.total_pages == 4
      assert meta.has_next == true
      assert meta.has_prev == true
    end

    test "has_next is false on last page" do
      pagination = %{page: 4, page_size: 10, offset: 30, limit: 10}
      items = Enum.to_list(1..5)
      total_count = 35

      meta = PaginationHelpers.build_pagination_meta(items, pagination, total_count)

      assert meta.has_next == false
      assert meta.has_prev == true
    end

    test "has_prev is false on first page" do
      pagination = %{page: 1, page_size: 10, offset: 0, limit: 10}
      items = Enum.to_list(1..10)
      total_count = 35

      meta = PaginationHelpers.build_pagination_meta(items, pagination, total_count)

      assert meta.has_next == true
      assert meta.has_prev == false
    end

    test "handles single page of results" do
      pagination = %{page: 1, page_size: 20, offset: 0, limit: 20}
      items = Enum.to_list(1..5)
      total_count = 5

      meta = PaginationHelpers.build_pagination_meta(items, pagination, total_count)

      assert meta.total_pages == 1
      assert meta.has_next == false
      assert meta.has_prev == false
    end

    test "handles empty results" do
      pagination = %{page: 1, page_size: 20, offset: 0, limit: 20}
      items = []
      total_count = 0

      meta = PaginationHelpers.build_pagination_meta(items, pagination, total_count)

      assert meta.total_items == 0
      assert meta.total_pages == 0
      assert meta.has_next == false
      assert meta.has_prev == false
    end
  end

  describe "default_page_size/0" do
    test "returns 20" do
      assert PaginationHelpers.default_page_size() == 20
    end
  end

  describe "max_page_size/0" do
    test "returns 100" do
      assert PaginationHelpers.max_page_size() == 100
    end
  end

  describe "paginate/2" do
    test "applies offset and limit to query" do
      # Create a simple query-like structure to test
      import Ecto.Query

      query = from(u in "users", select: u.id)
      pagination = %{offset: 10, limit: 5}

      paginated = PaginationHelpers.paginate(query, pagination)

      # The query should have offset and limit clauses
      assert paginated != query
    end
  end
end
