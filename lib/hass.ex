defmodule Hass.UtilMacros do
  defmacro ws_call(name, params) do
    quote do
      def unquote(name)(hass, unquote_splicing(params)) do
        ws_pid = GenServer.call(hass, :get_ws_pid)
        Hass.WebSocket.unquote(name)(ws_pid, unquote_splicing(params))
      end
    end
  end
end

defmodule Hass do
  use GenServer
  require Logger

  #############################################################################
  ## Public API

  def start(opts) do
    GenServer.start(__MODULE__, :ok, opts)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  import Hass.UtilMacros

  ws_call(:call_service, [domain, service, opts])

  #############################################################################
  ## GenServer callbacks

  defstruct [:ws_pid]

  @impl true
  def init(:ok) do
    {:ok, ws_pid} = Hass.WebSocket.start_link([])
    {:ok, %__MODULE__{ws_pid: ws_pid}}
  end

  @impl true
  def handle_call(:get_ws_pid, _, state) do
    {:reply, state.ws_pid, state}
  end

  #############################################################################
  ## Configuration

  def get_host_port() do
    {
      Application.fetch_env!(:elightscape, :hass_host),
      Application.fetch_env!(:elightscape, :hass_port)
    }
  end

  @spec endpoint_path(String.t()) :: String.t()
  def endpoint_path(endpoint) do
    "/api/#{endpoint}"
  end

  @spec auth_token :: String.t()
  def auth_token() do
    Application.fetch_env!(:elightscape, :hass_token)
  end

  @spec open_http_socket :: {:ok, {pid, reference}} | {:error, any}
  def open_http_socket() do
    {host, port} = get_host_port()

    Logger.debug(fn -> "Opening connection to home assistant on #{inspect(host)}:#{port}" end)

    case :gun.open(host, port, %{transport: :tcp}) do
      {:error, e} ->
        {:error, {:cannot_open, {host, port}, e}}

      {:ok, conn_pid} ->
        conn_ref = Process.monitor(conn_pid)

        case :gun.await_up(conn_pid) do
          {:error, e} ->
            {:error, {:cannot_open, {host, port}, e}}

          {:ok, :http} ->
            {:ok, {conn_pid, conn_ref}}
        end
    end
  end
end
