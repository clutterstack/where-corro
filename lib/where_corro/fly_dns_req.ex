defmodule WhereCorro.FlyDnsReq do
  require Logger

  def get_txt_record(dnsname) do
    # IO.inspect(dnsname, label: "dnsname")
    request_string = ":inet_res.getbyname(#{dnsname}, :txt)"
    # IO.inspect(request_string, label: "request string")
    with {{:ok, {:hostent, _internaldnsname, [], :txt, 1, [output]}}, []} <- Code.eval_string(request_string) do
      # IO.inspect(Code.eval_string(request_string), label: "in get_txt_record, response was")
      #IO.inspect(output)
      {:ok, output}
    else
      {{:error, reason},[]}  -> inspect(reason) |> IO.inspect()
        IO.puts("get_txt_record returned an error")
      something_unexpected -> inspect(something_unexpected) |> IO.inspect()
        IO.puts("get_txt_record returned a result I didn't expect")
    end
  end

  def get_aaaa_record(dnsname) do
    # IO.inspect(dnsname, label: "dnsname")
    request_string = ":inet_res.getbyname(#{dnsname}, :aaaa)"
    # IO.inspect(request_string, label: "request string")
    with {{:ok, {:hostent, _internaldnsname, [], :inet6, _, ip_list}}, []} <- Code.eval_string(request_string) do
      ip_list |> format_ipv6()
      # IO.inspect(output)
    else
      {{:error, :nxdomain}, []} -> IO.puts("get_aaaa_record received an nxdomain error.")
      {:error, :nxdomain}
      {{:error, reason},[]} -> inspect(reason) |> IO.inspect()
        IO.puts("get_aaaa_record received an error other than nxdomain")
        somethingelse -> inspect(somethingelse) |> IO.inspect()
        IO.puts("get_aaaa_record received a result I didn't expect")
    end
  end

  def get_corro_ipv6() do
    dnsname = "'top1.nearest.of.#{Application.fetch_env!(:where_corro, :fly_corrosion_app)}.internal'"
    get_aaaa_record(dnsname)
    |> IO.inspect(label: "result of get_aaaa_record inside get_corro_ipv6")
    # |> format_ipv6()
  end

  def get_corro_instance() do
    ip = get_corro_ipv6()
    everything = get_all_instances()
    # IO.inspect("Closest corrosion is #{everything[ip]["instance"]} in #{everything[ip]["region"]} at #{ip}")
    everything[ip]
  end

  def dns_corro_vms() do
    dnsname = "'vms.#{Application.fetch_env!(:where_corro, :fly_corrosion_app)}.internal'"
    get_txt_record(dnsname)
  end

  def dns_corro_regions() do
    dnsname = "'regions.#{Application.fetch_env!(:where_corro, :fly_corrosion_app)}.internal'"
    get_txt_record(dnsname)
  end

  def get_all_instances() do
    with {:ok, stringlist} <- get_txt_record("'_instances.internal'") do
      Enum.join(stringlist)
      # |> IO.inspect(label: "joined string")
      |> String.split(";")
      #|> IO.inspect(label: "resplit string")
      |> Enum.reduce(%{}, fn instance_string, acc ->
          Map.put(acc, map_from_instance_string(instance_string)["ip"], map_from_instance_string(instance_string))
      end)
      # |> IO.inspect()
    end
  end

  defp map_from_instance_string(string) do
    String.split(string,",")
    #|> IO.inspect(label: "split in map_from_instance_string")
    |> Enum.reduce(%{}, fn pair, acc ->
      [key, value] = String.split(pair, "=")
      Map.put(acc, key, value)
      end)
    #|> IO.inspect(label: "after reduce in map_from_instance_string")
  end

  defp format_ipv6(ip_list) do
    # TODO: generalise this to work when the list has
    # more than one ip in it
    # That means return a list of normal-looking ipv6
    # addresses, I think
      List.first(ip_list)
      |> Tuple.to_list()
      |> Enum.map(fn x -> Integer.to_string(x,16) end)
      |> Enum.join(":")
      |> String.downcase()
      # |> IO.inspect(label: "Extracted IP")
    end
end
