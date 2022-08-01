defmodule Hass.Rest do
  def get_state(entity_id) do
    rest_get("states/#{entity_id}")
  end

  defp rest_get(endpoint) do
    case Hass.open_http_socket() do
      {:error, _} = error ->
        error

      {:ok, {conn_pid, conn_ref}} ->
        stream_ref =
          :gun.get(conn_pid, Hass.endpoint_path(endpoint), %{
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{Hass.auth_token()}"
          })

        case receive_http_response(conn_pid, conn_ref, stream_ref) do
          {:ok, data} -> JSON.decode(data)
          {:error, _} = error -> error
        end
    end
  end

  defp receive_http_response(conn_pid, conn_ref, stream_ref) do
    receive do
      {:gun_response, ^conn_pid, ^stream_ref, :fin, status, _headers} ->
        if status == 200 do
          {:ok, nil}
        else
          {:error, {status, nil}}
        end

      {:gun_response, ^conn_pid, ^stream_ref, :nofin, status, _headers} ->
        case receive_http_data(conn_pid, conn_ref, stream_ref, []) do
          {:error, _} = error ->
            error

          {:ok, data} ->
            if status == 200 do
              {:ok, data}
            else
              {:error, {status, data}}
            end
        end

      {:DOWN, ^conn_ref, :process, ^conn_pid, reason} ->
        {:error, {:disconnected, reason}}
    end
  end

  defp receive_http_data(conn_pid, conn_ref, stream_ref, data) do
    receive do
      {:gun_data, ^conn_pid, ^stream_ref, :nofin, new_data} ->
        receive_http_data(conn_pid, conn_ref, stream_ref, [new_data | data])

      {:gun_data, ^conn_pid, ^stream_ref, :fin, new_data} ->
        {:ok, [new_data | data] |> Enum.reverse() |> Enum.join()}

      {:DOWN, ^conn_ref, :process, ^conn_pid, reason} ->
        {:error, {:disconnected, reason}}
    end
  end
end
