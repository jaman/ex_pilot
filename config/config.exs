import Config

config :ex_pilot, ExPilot.Web.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  url: [host: "localhost"],
  render_errors: [formats: [html: ExPilot.Web.ErrorHTML], layout: false],
  pubsub_server: ExPilot.Web.PubSub,
  live_view: [signing_salt: "ex_pilot_live"],
  secret_key_base: String.duplicate("ex-pilot-development-secret-", 3),
  http: [ip: {0, 0, 0, 0}, port: 2280],
  server: false

config :phoenix, :json_library, Jason

if config_env() == :test do
  config :ex_pilot, ExPilot.Web.Endpoint, http: [ip: {127, 0, 0, 1}, port: 4915], server: false
  config :logger, level: :warning
end
