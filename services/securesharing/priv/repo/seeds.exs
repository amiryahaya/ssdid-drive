# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     SecureSharing.Repo.insert!(%SecureSharing.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

if Mix.env() in [:dev, :test] do
  Code.eval_file("priv/repo/seeds/e2e_seed.exs")
end
