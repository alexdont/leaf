# A room broadcasts to the sessions in it, so the tests need somewhere for that
# to go. Nothing subscribes; the point is that the room can be started at all.
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: Leaf.TestPubSub)

ExUnit.start()
