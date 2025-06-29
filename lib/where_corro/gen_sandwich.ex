defmodule WhereCorro.GenSandwich do
  use GenServer

  @all_sandwiches [
    "smoked meat",
    "halloumi",
    "saucisson",
    "burger",
    "brie and cranberry",
    "reuben",
    "avocado",
    "grilled cheese",
    "smoked salmon",
    "shiitake",
    "ham",
    "BLT",
    "portobello"
  ]

  def start_link(_opts \\ []) do
    GenServer.start_link(WhereCorro.GenSandwich, [], name: GenSandwich)
  end

  def do_the_swap(menu) do
    Process.send_after(self(), {:do_the_swap, menu}, 2500)
  end

  def init(_opts) do
    # If I don't do this, all the VMs get the same set of sandwiches.
    :rand.seed(:exsplus, :erlang.system_time())
    # I feel like they're still getting at least one sandwich the same every time.
    # I don't know anything about the algorithms for this, but it really doesn't matter in this app
    menu = Enum.take_random(@all_sandwiches, 3)

    IO.inspect(
      "On Machine #{Application.fetch_env!(:where_corro, :fly_vm_id)}, the sandwich menu is #{menu}."
    )

    do_the_swap(menu)
    {:ok, []}
  end

  def handle_info({:do_the_swap, menu}, _state) do
    sandwich = Enum.random(menu)
    Phoenix.PubSub.broadcast(WhereCorro.PubSub, "sandwichmsg", {:sandwich, sandwich})
    do_the_swap(menu)
    {:noreply, sandwich}
  end

  def handle_call(:get_sandwich, _from, state) do
    # Logger.info("handle call state: "<>state)
    {:reply, %{sandwich: state}, state}
  end

  def get_sandwich() do
    GenServer.call(GenSandwich, :get_sandwich)
  end
end
