import Config

config :logger, :console,
  format: {Curl.Logger, :format},
  colors: [enabled: false],
  metadata: :all
