defmodule PowAssent.HTTPAdapter.Httpc do
  @moduledoc """
  HTTP adapter module for making http requests.

  SSL support will automatically be enabled if the `:certifi` and
  `:ssl_verify_fun` libraries exists in your project. You can also override
  the httc opts by setting `config :pow, httpc_opts: opts`.
  """
  alias PowAssent.HTTPResponse

  @type method :: :get | :post
  @type body :: binary() | nil
  @type headers :: [{binary(), binary()}]

  @doc """
  Make a HTTP request using :httpc.
  """
  @spec request(method(), binary(), body(), headers()) :: {:ok, map()} | {:error, map()}
  def request(method, url, body, headers) do
    request = httpc_request(url, body, headers)

    method
    |> :httpc.request(request, opts(url), [])
    |> format_response()
  end

  defp httpc_request(url, body, headers) do
    url          = to_charlist(url)
    headers      = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    do_httpc_request(url, body, headers ++ [default_user_agent_header()])
  end

  defp default_user_agent_header do
    version =
      case :application.get_key(:pow_assent, :vsn) do
        {:ok, vsn} -> vsn
        _ -> '0.0.0'
      end

    {'User-Agent', version}
  end

  defp do_httpc_request(url, nil, headers) do
    {url, headers}
  end
  defp do_httpc_request(url, body, headers) do
    {content_type, headers} = split_content_type_headers(headers)
    body                    = to_charlist(body)

    {url, headers, content_type, body}
  end

  defp split_content_type_headers(headers) do
    case List.keytake(headers, 'content-type', 0) do
      nil -> {'text/plain', headers}
      {{_, ct}, headers} -> {ct, headers}
    end
  end

  defp format_response({:ok, {{_, status, _}, headers, body}}) do
    headers = Enum.map(headers, fn {key, value} -> {String.downcase(to_string(key)), to_string(value)} end)
    body    = IO.iodata_to_binary(body)

    {:ok, %HTTPResponse{status: status, headers: headers, body: body}}
  end
  defp format_response({:error, {:failed_connect, _}}), do: {:error, :econnrefused}
  defp format_response(response), do: response

  defp opts(url), do: Application.get_env(:pow, :httpc_opts) || default_opts(url)

  defp default_opts(url) do
    case certifi_and_ssl_verify_fun_available?() do
      true  -> [ssl: ssl_opts(url)]
      false -> []
    end
  end

  defp certifi_and_ssl_verify_fun_available?() do
    app_available?(:certifi) && app_available?(:ssl_verify_fun)
  end

  defp app_available?(app) do
    case :application.get_key(app, :vsn) do
      {:ok, _vsn} -> true
      _           -> false
    end
  end

  defp ssl_opts(url) do
    %{host: host} = URI.parse(url)

    Application.ensure_all_started(:certifi)
    Application.ensure_all_started(:ssl_verify_hostname)

    # This will prevent warnings from showing up if :certifi or
    # :ssl_verify_hostname isn't available
    certifi_mod = :certifi
    ssl_verify_hostname_mod = :ssl_verify_hostname

    [
      verify: :verify_peer,
      depth: 99,
      cacerts: certifi_mod.cacerts(),
      verify_fun: {&ssl_verify_hostname_mod.verify_fun/3, check_hostname: to_charlist(host)}
    ]
  end
end
