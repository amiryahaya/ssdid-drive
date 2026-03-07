import Config

# Do not print debug messages in production
config :logger, level: :info

# Structured JSON logging for production (machine-parseable by log aggregators)
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, []}

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
