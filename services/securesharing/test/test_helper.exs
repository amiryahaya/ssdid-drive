# Exclude benchmark tests by default - run with: mix test --include benchmark
# Exclude nif_behavior tests when using stubs - run with: mix test --include nif_behavior
# Exclude external_service tests that require API keys - run with: mix test --include external_service
# Exclude rate_limit tests when rate limiting is disabled - run with: mix test --include rate_limit
ExUnit.start(exclude: [:benchmark, :nif_behavior, :external_service, :rate_limit])
Ecto.Adapters.SQL.Sandbox.mode(SecureSharing.Repo, :manual)
